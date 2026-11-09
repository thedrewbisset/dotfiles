#!/usr/bin/env bash
#
# Collects a hardware inventory from every machine on the LAN and prints a
# comparison table, for planning what to run where (see docs/llm-cluster.md).
#
#     scripts/fleet-inventory.sh                       # hosts from the config file
#     scripts/fleet-inventory.sh studio box:windows    # or named as arguments
#
# Hosts are ssh aliases, not addresses: put the real HostName, User and IdentityFile
# in ~/.ssh/config.local, which source/.ssh/config includes and this repo never
# tracks. That keeps machine names and LAN addresses out of a public repo.
#
# The host list lives outside the repo for the same reason, in
# ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/fleet.hosts -- the same place and for
# the same reason as the privacy gate's deny-list. One host per line:
#
#     # alias        platform
#     studio         local       # this machine, collected without ssh
#     box            windows
#     pi             unix        # the default, so the word is optional
#
# The platform is declared rather than probed: the Windows nodes set sshd's
# DefaultShell to PowerShell, so `ssh host uname -s` fails there and any probe
# would have to guess from the shape of the error.
#
# Nothing is copied to the nodes. The matching collector is piped over ssh on
# stdin, so a node can never run a stale version of it.
#
# Load your key into the agent first (ssh-add) if it has a passphrase; otherwise
# ssh prompts once per host.

set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sh_collector="$repo_root/scripts/inventory.sh"
ps1_collector="$repo_root/scripts/inventory.ps1"

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
hosts_file="$config_home/dotfiles/fleet.hosts"

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
out_dir="$data_home/dotfiles/inventory"

for f in "$sh_collector" "$ps1_collector"; do
  if [ ! -f "$f" ]; then
    printf 'fleet-inventory: missing collector %s\n' "$f" >&2
    exit 1
  fi
done

# --- host list ---------------------------------------------------------------

aliases=()
platforms=()

add_host() { # alias platform
  case "$2" in
    windows | unix | local ) ;;
    * )
      printf 'fleet-inventory: %s: unknown platform "%s" (want windows, unix or local)\n' "$1" "$2" >&2
      exit 1
      ;;
  esac
  aliases+=("$1")
  platforms+=("$2")
}

if [ "$#" -gt 0 ]; then
  for spec in "$@"; do
    case "$spec" in
      *:* ) add_host "${spec%%:*}" "${spec#*:}" ;;
      * )   add_host "$spec" unix ;;
    esac
  done
elif [ -r "$hosts_file" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    set -- $line
    [ "$#" -gt 0 ] || continue
    if [ "$#" -ge 2 ]; then add_host "$1" "$2"; else add_host "$1" unix; fi
  done < "$hosts_file"
else
  printf 'fleet-inventory: no hosts given and no %s\n\n' "$hosts_file" >&2
  printf 'Create it with one "<alias> [windows|unix|local]" per line, or pass\n' >&2
  printf 'aliases as arguments: scripts/fleet-inventory.sh studio box:windows\n' >&2
  exit 1
fi

if [ "${#aliases[@]}" -eq 0 ]; then
  printf 'fleet-inventory: host list is empty\n' >&2
  exit 1
fi

# --- collect -----------------------------------------------------------------

mkdir -p "$out_dir"

python3_bin="$(command -v python3 2>/dev/null || true)"
# Windows' WindowsApps python3 stub exists but only prints a Microsoft Store
# message, so test that python3 actually runs rather than that it is on PATH --
# the same check recipes/hooks/install.ps1 makes, for the same reason. Without it
# every host would be reported as failing its JSON validation.
if [ -n "$python3_bin" ]; then
  "$python3_bin" -c 'pass' >/dev/null 2>&1 || python3_bin=''
fi

# Rejects a truncated or error-filled capture, so a broken ssh never poisons the
# table with a half-written file. Falls back to a brace check without python3.
is_json() {
  if [ -n "$python3_bin" ]; then
    "$python3_bin" -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null
  else
    head -c 1 "$1" 2>/dev/null | grep -q '{'
  fi
}

failed=0
i=0
while [ "$i" -lt "${#aliases[@]}" ]; do
  alias="${aliases[$i]}"
  platform="${platforms[$i]}"
  i=$(( i + 1 ))

  out="$out_dir/$alias.json"
  tmp="$out.partial"
  printf '==> %s (%s)\n' "$alias" "$platform"

  case "$platform" in
    local )
      bash "$sh_collector" > "$tmp" 2>/dev/null
      ;;
    unix )
      ssh -o ConnectTimeout=10 "$alias" bash -s < "$sh_collector" > "$tmp" 2>/dev/null
      ;;
    windows )
      # -Command - reads the whole of stdin as one script block, so the
      # collector's top-level param() block is accepted.
      ssh -o ConnectTimeout=10 "$alias" \
        'powershell -NoProfile -ExecutionPolicy Bypass -Command -' \
        < "$ps1_collector" > "$tmp" 2>/dev/null
      ;;
  esac

  if is_json "$tmp"; then
    mv "$tmp" "$out"
    printf '    ok -> %s\n' "$out"
  else
    rm -f "$tmp"
    printf '    FAILED (no usable JSON; try the ssh by hand)\n' >&2
    failed=$(( failed + 1 ))
  fi
done

printf '\n'

# --- report ------------------------------------------------------------------

if [ -z "$python3_bin" ]; then
  printf 'fleet-inventory: python3 not found, so no table. Collected files:\n'
  ls -1 "$out_dir"/*.json 2>/dev/null || true
  exit "$( [ "$failed" -gt 0 ] && echo 1 || echo 0 )"
fi

"$python3_bin" - "$out_dir" <<'PY'
import json, os, sys

out_dir = sys.argv[1]
rows, notes = [], []
total_ram = total_vram = 0.0

def best_gpu(gpus):
    # Prefer a vendor that reports real VRAM; nvidia-smi and system_profiler do,
    # the WMI fallback does not.
    ranked = sorted(
        gpus,
        key=lambda g: (g.get("vendor") in ("nvidia", "apple"), g.get("vram_mib") or -1),
        reverse=True,
    )
    return ranked[0] if ranked else {}

for name in sorted(os.listdir(out_dir)):
    if not name.endswith(".json"):
        continue
    alias = name[:-5]
    try:
        with open(os.path.join(out_dir, name)) as fh:
            d = json.load(fh)
    except (OSError, ValueError):
        continue

    cpu, mem, net = d.get("cpu", {}), d.get("memory", {}), d.get("network", {})
    gpu = best_gpu(d.get("gpus") or [])
    vram = gpu.get("vram_mib")
    ram = mem.get("total_gb")

    if isinstance(ram, (int, float)):
        total_ram += ram
    if isinstance(vram, (int, float)):
        total_vram += vram / 1024.0

    active = (net.get("active") or {}).get("interface")
    adapters = net.get("adapters") or []
    link = next((a.get("link_speed") for a in adapters if a.get("name") == active), None)
    if not link:
        link = next((a.get("link_speed") for a in adapters if a.get("link_speed")), None)

    rows.append([
        alias,
        str(d.get("host") or "?"),
        str(d.get("platform") or "?"),
        "{}c/{}t".format(cpu.get("cores") or "?", cpu.get("threads") or "?"),
        "{:.1f}".format(ram) if isinstance(ram, (int, float)) else "?",
        str(gpu.get("name") or "none"),
        "{:.1f}".format(vram / 1024.0) if isinstance(vram, (int, float)) else "?",
        str(link or "?"),
    ])

    # A wired port with no cable in it, beside a wireless link doing the work, is
    # the cheapest fix available on a cluster that pays latency per token.
    wired_idle = [
        a for a in adapters
        if str(a.get("status")).lower() in ("disconnected", "down", "inactive")
        and "wi-fi" not in str(a.get("name", "")).lower()
        and "wireless" not in str(a.get("description", "")).lower()
    ]
    if wired_idle and active and ("wi-fi" in active.lower() or active.lower().startswith("en0")):
        names = ", ".join(str(a.get("description") or a.get("name")) for a in wired_idle)
        notes.append("{}: routing over {} while a wired port sits idle ({})".format(alias, active, names))

    if mem.get("modules_populated") == 1:
        notes.append("{}: one memory module, so single-channel -- a matching second "
                     "module roughly doubles bandwidth".format(alias))

if not rows:
    print("No inventory found in {}. Run a collection first.".format(out_dir))
    raise SystemExit(0)

header = ["ALIAS", "HOST", "PLATFORM", "CPU", "RAM GB", "GPU", "VRAM GB", "LINK"]
widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
line = lambda r: "  ".join(str(c).ljust(widths[i]) for i, c in enumerate(r)).rstrip()

print(line(header))
print("  ".join("-" * w for w in widths))
for r in rows:
    print(line(r))

print("\n{} node(s): {:.1f} GB RAM, {:.1f} GB VRAM in total".format(
    len(rows), total_ram, total_vram))
print("Totals are a ceiling, not a budget: see docs/llm-cluster.md on why pooling "
      "VRAM over a LAN buys capacity rather than speed.")

if notes:
    print("\nNotes:")
    for n in notes:
        print("  - " + n)
PY

if [ "$failed" -gt 0 ]; then
  printf '\nfleet-inventory: %d host(s) failed\n' "$failed" >&2
  exit 1
fi
