#!/usr/bin/env bash
#
# Collects this machine's hardware inventory as JSON on stdout (macOS and Linux).
#
#     scripts/inventory.sh
#
# Counterpart of scripts/inventory.ps1, which emits the same schema on Windows.
# scripts/fleet-inventory.sh pipes whichever one fits each host over SSH and
# collects the results. See docs/llm-cluster.md for what the numbers are for.
#
# Read-only: installs nothing and changes no state, so it is safe on a machine you
# are only surveying. The output names the host and its LAN address, so a collected
# set is local-only and never belongs in this repo.
#
# Self-contained on purpose: it is delivered over SSH as `bash -s`, so it must not
# read anything else from the repo. Targets bash 3.2, the stock macOS shell, so no
# associative arrays and no ${var^^}.
#
# Collectors print JSON fragments on stdout rather than appending to a shared
# variable: a `while read` at the end of a pipeline runs in a subshell, so appends
# made there are silently discarded.

set -u

# --- JSON helpers ------------------------------------------------------------

# A JSON string, or null when empty. sed rather than bash pattern substitution,
# whose backslash escaping differs between bash 3.2 and later versions. Backslashes
# are escaped before quotes, or the escapes would be escaped again.
json_str() {
  if [ -z "${1-}" ]; then printf 'null'; return; fi
  printf '"%s"' "$(printf '%s' "$1" |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[[:cntrl:]]/ /g')"
}

# A bare JSON number, or null for anything that is not one. Keeps a failed probe
# from becoming 0, which would read as a real measurement of zero.
json_num() {
  case "${1-}" in
    '' | '.' | *[!0-9.]* ) printf 'null' ;;
    * ) printf '%s' "$1" ;;
  esac
}

# Joins stdin lines with commas, dropping blanks, for use inside a JSON array.
join_lines() {
  awk 'NF { if (n++) printf ","; printf "%s", $0 }'
}

have() { command -v "$1" >/dev/null 2>&1; }

bytes_to_gb() { awk -v b="${1:-0}" 'BEGIN { printf "%.1f", b / 1073741824 }'; }
kb_to_gb()    { awk -v k="${1:-0}" 'BEGIN { printf "%.1f", k / 1048576 }'; }

gpu_object() { # vendor name vram_mib driver compute_cap
  printf '{"vendor":%s,"name":%s,"vram_mib":%s,"driver":%s,"compute_cap":%s}' \
    "$(json_str "$1")" "$(json_str "$2")" "$(json_num "$3")" \
    "$(json_str "$4")" "$(json_str "$5")"
}

nic_object() { # name description status link_speed media
  printf '{"name":%s,"description":%s,"status":%s,"link_speed":%s,"media":%s}' \
    "$(json_str "$1")" "$(json_str "$2")" "$(json_str "$3")" \
    "$(json_str "$4")" "$(json_str "$5")"
}

# --- platform ----------------------------------------------------------------

uname_s="$(uname -s)"
case "$uname_s" in
  Darwin ) platform=darwin ;;
  Linux  ) platform=linux ;;
  # Anything else (BSD, MSYS, Cygwin) takes the generic probes below and reports
  # null for whatever it cannot answer, rather than failing outright.
  * ) platform="$(printf '%s' "$uname_s" | tr '[:upper:]' '[:lower:]')" ;;
esac

host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
collected_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- nvidia (either platform) ------------------------------------------------

# Authoritative for VRAM where it exists, so it runs on Linux and on any Mac with
# an NVIDIA card. One JSON object per line.
collect_nvidia() {
  have nvidia-smi || return 0
  nvidia-smi --query-gpu=name,memory.total,driver_version,compute_cap \
             --format=csv,noheader,nounits 2>/dev/null |
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    name="$(printf '%s' "$row" | awk -F', *' '{ print $1 }')"
    vram="$(printf '%s' "$row" | awk -F', *' '{ print $2 }')"
    drv="$(printf  '%s' "$row" | awk -F', *' '{ print $3 }')"
    cap="$(printf  '%s' "$row" | awk -F', *' '{ print $4 }')"
    gpu_object nvidia "$name" "$vram" "$drv" "$cap"
    printf '\n'
  done
}

# --- darwin ------------------------------------------------------------------

darwin_gpus() {
  have system_profiler || return 0
  # Apple Silicon has no discrete VRAM: the GPU shares system memory. vram_mib is
  # left null rather than guessed, so memory.total_gb is the budget to reason about.
  system_profiler SPDisplaysDataType 2>/dev/null | awk '
    /Chipset Model:/ { sub(/^ *Chipset Model: */, ""); chip = $0; vram = "" }
    /VRAM/ { line = $0; gsub(/[^0-9]/, "", line); vram = line }
    /^$/ { if (chip != "") { print chip "\t" vram; chip = "" } }
    END { if (chip != "") print chip "\t" vram }
  ' | while IFS="$(printf '\t')" read -r chip vram; do
    [ -n "$chip" ] || continue
    gpu_object apple "$chip" "$vram" "" ""
    printf '\n'
  done
}

# Every hardware port, including ones with no cable in them: an idle 2.5/10GbE port
# beside an active Wi-Fi link is exactly the finding this tool exists to surface.
darwin_nics() {
  have networksetup || return 0
  networksetup -listallhardwareports 2>/dev/null | awk '
    /^Hardware Port:/ { sub(/^Hardware Port: */, ""); port = $0 }
    /^Device:/ { sub(/^Device: */, ""); if (port != "") print port "\t" $0 }
  ' | while IFS="$(printf '\t')" read -r port dev; do
    [ -n "$dev" ] || continue
    status="$(ifconfig "$dev" 2>/dev/null | awk '/status:/ { print $2; exit }')"
    [ -n "$status" ] || status=unknown
    media="$(ifconfig "$dev" 2>/dev/null | sed -n 's/^[[:space:]]*media: *//p' | head -1)"
    nic_object "$dev" "$port" "$status" "$media" ""
    printf '\n'
  done
}

# --- linux -------------------------------------------------------------------

linux_gpus() {
  # Only consulted when nvidia-smi is absent; lspci gives a name but no VRAM.
  have nvidia-smi && return 0
  have lspci || return 0
  lspci 2>/dev/null | grep -iE 'vga|3d controller|display controller' |
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    gpu_object other "$(printf '%s' "$row" | sed -e 's/^[^:]*: *//')" "" "" ""
    printf '\n'
  done
}

linux_nics() {
  [ -d /sys/class/net ] || return 0
  for path in /sys/class/net/*; do
    [ -e "$path" ] || continue
    dev="$(basename "$path")"
    case "$dev" in lo ) continue ;; esac
    state=''; speed=''
    [ -r "$path/operstate" ] && state="$(cat "$path/operstate" 2>/dev/null)"
    # Reads -1 or errors on a down or virtual link; only report a real number.
    if [ -r "$path/speed" ]; then
      raw="$(cat "$path/speed" 2>/dev/null || true)"
      case "$raw" in '' | -* ) speed='' ;; * ) speed="$raw Mbps" ;; esac
    fi
    nic_object "$dev" "" "${state:-unknown}" "$speed" ""
    printf '\n'
  done
}

# --- storage (either platform) -----------------------------------------------

# df -P forces the portable single-line format; -k forces 1K blocks on both.
collect_storage() {
  df -Pk 2>/dev/null | tail -n +2 | while IFS= read -r line; do
    mount="$(printf '%s' "$line" | awk '{ print $6 }')"
    size_k="$(printf '%s' "$line" | awk '{ print $2 }')"
    free_k="$(printf '%s' "$line" | awk '{ print $4 }')"
    [ -n "$mount" ] || continue
    # Pseudo and ephemeral filesystems say nothing about model storage.
    case "$mount" in
      /dev | /dev/* | /proc | /proc/* | /sys | /sys/* | /run | /run/* ) continue ;;
      /System/Volumes/VM | /System/Volumes/Preboot | /System/Volumes/Update* ) continue ;;
    esac
    case "$size_k" in '' | *[!0-9]* ) continue ;; esac
    printf '{"mount":%s,"fs":null,"label":null,"size_gb":%s,"free_gb":%s}\n' \
      "$(json_str "$mount")" \
      "$(json_num "$(kb_to_gb "$size_k")")" \
      "$(json_num "$(kb_to_gb "$free_k")")"
  done
}

# --- runtimes ----------------------------------------------------------------

collect_runtimes() {
  for name in ollama lms llama-server llama-cli rpc-server python3 uv; do
    printf '%s:%s\n' "$(json_str "$name")" "$(json_str "$(command -v "$name" 2>/dev/null || true)")"
  done
}

# --- probe -------------------------------------------------------------------

os_name=''; os_build=''
cpu_model=''; cpu_cores=''; cpu_threads=''; cpu_max_mhz=''
mem_total_gb=''; mem_free_gb=''
active_if=''; active_ip=''; active_gw=''
gpus_json=''; nics_json=''

if [ "$platform" = darwin ]; then
  os_name="$(sw_vers -productName 2>/dev/null || true) $(sw_vers -productVersion 2>/dev/null || true)"
  os_name="$(printf '%s' "$os_name" | sed -e 's/^ *//' -e 's/ *$//')"
  os_build="$(sw_vers -buildVersion 2>/dev/null || true)"

  cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || true)"
  [ -n "$cpu_model" ] || cpu_model="$(uname -m)"
  cpu_cores="$(sysctl -n hw.physicalcpu 2>/dev/null || true)"
  cpu_threads="$(sysctl -n hw.logicalcpu 2>/dev/null || true)"
  # Intel Macs only; Apple Silicon does not expose a max frequency here.
  hz="$(sysctl -n hw.cpufrequency_max 2>/dev/null || true)"
  case "$hz" in
    '' | *[!0-9]* ) cpu_max_mhz='' ;;
    * ) cpu_max_mhz="$(awk -v h="$hz" 'BEGIN { printf "%d", h / 1000000 }')" ;;
  esac

  # Guarded rather than defaulted: bytes_to_gb would turn a failed sysctl into
  # "0.0", which reads as a machine with no memory instead of an unknown.
  mem_raw="$(sysctl -n hw.memsize 2>/dev/null || true)"
  case "$mem_raw" in
    '' | *[!0-9]* ) mem_total_gb='' ;;
    * ) mem_total_gb="$(bytes_to_gb "$mem_raw")" ;;
  esac
  if have vm_stat; then
    # free + inactive is the usual "available" approximation on macOS. The page
    # size is in vm_stat's header, so take the first all-digit token there.
    mem_free_gb="$(vm_stat 2>/dev/null | awk '
      /page size of/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { ps = $i; break } }
      /Pages free/ { v = $3; gsub(/\./, "", v); free = v }
      /Pages inactive/ { v = $3; gsub(/\./, "", v); inact = v }
      END { if (ps == "") ps = 4096; printf "%.1f", (free + inact) * ps / 1073741824 }')"
  fi

  active_if="$(route -n get default 2>/dev/null | awk '/interface:/ { print $2; exit }')"
  if [ -n "$active_if" ]; then
    active_ip="$(ipconfig getifaddr "$active_if" 2>/dev/null || true)"
    active_gw="$(route -n get default 2>/dev/null | awk '/gateway:/ { print $2; exit }')"
  fi

  gpus_json="$( { darwin_gpus; collect_nvidia; } | join_lines )"
  nics_json="$(darwin_nics | join_lines)"
else
  if [ -r /etc/os-release ]; then
    os_name="$(awk -F= '/^PRETTY_NAME=/ { gsub(/"/, "", $2); print $2; exit }' /etc/os-release)"
  fi
  [ -n "$os_name" ] || os_name="$uname_s"
  os_build="$(uname -r 2>/dev/null || true)"

  if [ -r /proc/cpuinfo ]; then
    cpu_model="$(awk -F': *' '/^model name/ { print $2; exit }' /proc/cpuinfo)"
  fi
  [ -n "$cpu_model" ] || cpu_model="$(uname -m)"
  cpu_threads="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  if have lscpu; then
    per_socket="$(lscpu 2>/dev/null | awk -F': *' '/^Core\(s\) per socket/ { print $2; exit }')"
    sockets="$(lscpu 2>/dev/null | awk -F': *' '/^Socket\(s\)/ { print $2; exit }')"
    case "$per_socket$sockets" in
      '' | *[!0-9]* ) ;;
      * ) cpu_cores="$(( per_socket * sockets ))" ;;
    esac
  fi
  [ -n "$cpu_cores" ] || cpu_cores="$cpu_threads"

  if [ -r /proc/meminfo ]; then
    mem_total_gb="$(awk '/^MemTotal:/ { printf "%.1f", $2 / 1048576; exit }' /proc/meminfo)"
    mem_free_gb="$(awk '/^MemAvailable:/ { printf "%.1f", $2 / 1048576; exit }' /proc/meminfo)"
  fi

  if have ip; then
    active_if="$(ip route 2>/dev/null | awk '/^default/ { print $5; exit }')"
    active_gw="$(ip route 2>/dev/null | awk '/^default/ { print $3; exit }')"
    if [ -n "$active_if" ]; then
      active_ip="$(ip -4 addr show "$active_if" 2>/dev/null |
        awk '/inet / { split($2, a, "/"); print a[1]; exit }')"
    fi
  fi

  gpus_json="$( { linux_gpus; collect_nvidia; } | join_lines )"
  nics_json="$(linux_nics | join_lines)"
fi

# /proc/cpuinfo pads the model name to a fixed width, and some BIOSes double-space
# it, so collapse runs of spaces and strip the ends before it reaches the report.
cpu_model="$(printf '%s' "$cpu_model" | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')"

storage_json="$(collect_storage | join_lines)"
runtimes_json="$(collect_runtimes | join_lines)"

# Physical module layout needs root (dmidecode) on Linux and does not exist on
# Apple Silicon, where memory is on-package. Reported null rather than guessed;
# scripts/inventory.ps1 fills these in from WMI, which needs no privileges.
cat <<JSON
{
  "schema": 1,
  "collected_at": $(json_str "$collected_at"),
  "host": $(json_str "$host"),
  "platform": $(json_str "$platform"),
  "os": {
    "name": $(json_str "$os_name"),
    "build": $(json_str "$os_build")
  },
  "cpu": {
    "model": $(json_str "$cpu_model"),
    "cores": $(json_num "$cpu_cores"),
    "threads": $(json_num "$cpu_threads"),
    "max_mhz": $(json_num "$cpu_max_mhz"),
    "virtualization": null
  },
  "memory": {
    "total_gb": $(json_num "$mem_total_gb"),
    "free_gb": $(json_num "$mem_free_gb"),
    "modules_populated": null,
    "modules": []
  },
  "gpus": [$gpus_json],
  "storage": [$storage_json],
  "network": {
    "adapters": [$nics_json],
    "active": {
      "interface": $(json_str "$active_if"),
      "ipv4": $(json_str "$active_ip"),
      "gateway": $(json_str "$active_gw")
    }
  },
  "runtimes": {$runtimes_json}
}
JSON
