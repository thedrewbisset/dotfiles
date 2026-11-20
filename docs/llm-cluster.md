# Local LLM cluster

Running local models across the machines on a private LAN: what the available tooling
actually does, which of the two things people mean by "use the collective compute" is
worth building, and a method for working out what any one node can hold.

**This document is design and method only.** It deliberately contains no hardware
profile, no host name and no per-machine numbers. Those are correlatable inventory of
a kind a public repository should not carry, so they stay local -- see
*[Taking inventory](#taking-inventory)* for where they go and why. Apply the method
below to your own collected figures.

---

## The distinction that decides everything

Two different goals hide behind one sentence:

**Capacity pooling** -- run a single model too large for any one machine, by
splitting it across several. **Throughput pooling** -- get more total work done by
running things on several machines at once.

Most people want the second and set out to build the first. The two need almost
opposite architectures, and only one of them works well over Ethernet.

## Why pooling VRAM over a LAN disappoints

Token generation is bound by memory bandwidth and latency, not arithmetic. That
makes the interconnect, rather than the GPUs, the thing that decides whether
splitting a model works.

**Tensor parallelism** splits every layer across devices and needs an all-reduce at
each one. That is NVLink and InfiniBand territory; on Ethernet it collapses.

**Pipeline parallelism** gives whole layers to each node, so only small hidden
states cross the wire. That is feasible on a LAN -- but for a *single* stream one
node computes while the others idle, and every layer boundary adds a network hop.
You buy **capacity, not speed**. One published two-node measurement reported 48
tok/s falling to 5 tok/s, around a 90% loss. Treat that as a single, older
datapoint rather than a benchmark, but the direction is the point.

More nodes make this worse, not better: pipeline depth is a liability, because every
extra hop is latency added to every token. If a model has to be split, split it
across the two or three strongest machines and leave the rest out of it.

### The one exception: Thunderbolt 5 on Apple Silicon

Everything above assumes Ethernet. One interconnect now in consumer hands escapes it.
Apple's WWDC26 session 233 covers multi-Mac inference with **MLX over RDMA on
Thunderbolt 5**, using their JACCL collective library; `mlx.launch` starts a
distributed job over SSH from a JSON hostfile, which `mlx.distributed_config` can
generate. Apple reports **up to 3x with four nodes** (session 232; the session 233
demo shows nearly 3x on four M3 Ultras) -- throughput scaling rather than merely
capacity, and so the one published case of a LAN-class fabric making tensor
parallelism pay. `exo` runs tensor parallelism on the same stack.

The conditions are narrow enough to settle eligibility on their own:

| Requirement | Consequence |
|---|---|
| Thunderbolt 5 | M4 Pro, M4 Max, M3 Ultra or later Pro/Max/Ultra chips. Base chips ship TB4, and TB3/TB4 nodes do not qualify |
| macOS 26.2+ on every node | Enabled with `rdma_ctl enable` from Recovery, so it **cannot be set up remotely** |
| A full mesh | JACCL supports only fully connected topologies: a direct cable between every pair of Macs |
| Apple Silicon only | MLX has no CUDA backend, so **no Windows or Linux GPU node can join** |

That last row is the one that matters when planning: a mixed fleet cannot use the only
fabric that would make capacity pooling fast. The fast path is Apple-to-Apple; the
cross-platform path is llama.cpp RPC, which is explicitly not speed-optimised. The
speedups above are vendor demos -- Apple's own caveat is that they depend on model size
and architecture -- and no independent benchmark has been checked.

### Architecture class decides eligibility before anything else

Whether a node has a GPU is the wrong screen. The useful one is **unified memory versus
discrete**, and it is read off memory bandwidth:

- **Apple Silicon** is a GPU with unified memory: fitted RAM is usable model capacity,
  from about 68 GB/s on a base M1 (100-120 on later base chips) to around 800 GB/s on an Ultra.
- **An Intel Mac is a dead end here.** No usable GPU for this work, and DDR4 bandwidth
  in the 25-50 GB/s range against ~272 GB/s on a mid-range discrete card. Inference is
  bandwidth-bound, so that gap *is* the result.

A heterogeneous pipeline runs at the pace of its slowest node, so adding a weak machine
to one makes the pipeline worse rather than larger. Exclude any node whose bandwidth is
an order of magnitude below the others -- it belongs in throughput pooling instead,
where slow work still finishes in parallel.

## The interconnect comes first

**This section applies to clustering only.** For a model running on one machine the
network is not in the path at all -- no bytes cross it per token -- so nothing here
is a constraint on single-node inference. It affects how fast weights download, and
nothing else. Do not let it into a single-machine sizing decision.

For clustering, check what the nodes are actually talking over before choosing any
software. The common and costly case is **a wired port sitting disconnected while the
machine routes over Wi-Fi**, which is easy to miss precisely because everything
works. Wireless flatters itself on paper: it is a half-duplex shared medium with
variable multi-millisecond latency, and distributed inference pays that jitter *per
token* rather than once per bulk transfer. Plugging in the cable usually improves the
latency floor more than it improves nominal bandwidth, and it costs nothing.

`fleet-inventory.sh` flags this case in its notes, because an idle wired port beside
a working wireless link is both easy to overlook and expensive to keep.

## Options surveyed

| Option | Verdict |
|---|---|
| **llama.cpp RPC backend** | Start here if capacity pooling is genuinely needed. The most mature option and the only comfortable one for mixed CUDA + Metal + CPU nodes. |
| **exo** | Active, with a macOS app and dashboard. Apple-only in practice: GPU inference runs on MLX on macOS, and on Linux it currently runs on CPU. |
| **prima.cpp** | Research-grade, but aimed exactly at heterogeneous low-resource home clusters. Closest match to this problem. |
| **vLLM + Ray** | Excellent and production-grade, but not for a cluster like this: it wants homogeneous GPUs, a fast interconnect, and more than 8 GB per worker. |
| **Petals** | A different problem -- swarm serving of very large models. |

**llama.cpp RPC.** Build with `-DGGML_RPC=ON` on every machine, run `rpc-server` on
the workers, and point the main binary at them with `--rpc host:port,...`. Three
things to know before starting:

- **Every node must build from the same commit.** The RPC protocol is not
  versioned across commits, and mismatches fail in confusing ways.
- **Set worker thread counts explicitly.** Leaving them default can hit a
  low-utilisation bug where workers sit mostly idle.
- **Confirm the port from upstream.** Secondary guides disagree between 50051 and
  50052; check llama.cpp's own `tools/rpc` README rather than any write-up.

It is designed to pool memory, and is explicit that it is not speed-optimised.
That matches the analysis above: use it to run something that fits nowhere else,
not to make a model that already fits run faster.

**exo.** Connects peer to peer with no master/worker split and partitions a model
by each device's memory ratio, which is the right design for mismatched hardware.
The earlier codebase, `exo-explore/ex-exo`, was archived in December 2025; current
development is in `exo-explore/exo`, which ships a macOS menu-bar app, a cluster
dashboard and day-0 support for RDMA over Thunderbolt 5, and claims up to 1.8x on two
devices and 3.2x on four with tensor parallelism. Its README is also plain that on
Linux it currently runs on CPU, with GPU support still in development -- so in
practice it is Apple-only, and no use to a mixed fleet.

## What to build instead

For a handful of machines on a LAN, throughput pooling is almost certainly the better
investment:

- **One runtime per machine behind a single endpoint.** A gateway such as a LiteLLM
  proxy, llama-swap, or plain nginx gives one OpenAI-compatible URL, N-way
  concurrency, and per-model routing. This is the highest value for the least
  effort.
- **Specialise by hardware.** The strongest GPU takes the interactive chat and
  coding model. Weaker boxes take embeddings, rerankers, speech-to-text, and OCR,
  all of which are small and tolerate modest hardware.
- **Batch work scales nearly linearly.** Document embedding, dataset generation,
  and eval suites are embarrassingly parallel, so N machines really do finish
  roughly N times sooner. This is where a LAN cluster genuinely shines, and it
  needs none of the tooling above.
- **Keep speculative decoding on one box.** Draft and verifier models must sit
  together; a network round trip per token erases the benefit entirely.

## Routing: one endpoint, many machines

This is the design that replaces clustering, and it is worth separating cleanly from
it, because the two have opposite relationships with the network.

**Clustering touches the network once per token. Routing touches it once per request.**
A LAN hop is around a millisecond; on a 30-token-per-second stream that is 3% of one
token's budget, paid once for the whole response. Everything that makes pipeline
parallelism collapse is simply absent here. This is why routing works over 1 GbE, or
even Wi-Fi, while splitting a model does not.

### The gain is residency, not throughput

The gain is easy to state wrongly. Routing does not make any model faster; what it buys
is **several warm models at once**.

On a single 8 GB node, `OLLAMA_MAX_LOADED_MODELS` has to be 1, so every change of model
is an eviction and a reload -- several seconds of dead time, paid on the first request
after any switch. Spread the same set across N machines and each one holds a different
*resident* model, so the switch cost disappears entirely: a vision request, a fast
4B answer and a long-context job can be in flight simultaneously, each on hardware
that already has its weights loaded.

So the honest framing of a mixed fleet is not "more compute". It is **more
simultaneously-resident specialists, reachable at one address** -- which is usually
what people wanted from clustering in the first place.

### Shape

Three layers, and only the middle one is new work:

1. **One runtime per node, bound to loopback.** Each machine serves whatever it holds
   best, on `127.0.0.1` only.
2. **A gateway on the always-on node.** One OpenAI-compatible URL in front of all of
   them, with the per-node addresses as its back ends.
3. **Capability aliases, not machine names.** Harnesses ask for `fast` or `vision`,
   never for a host. This is the part that makes the fleet rearrangeable without
   touching a single harness config.

| Component | Choice | Why |
|---|---|---|
| Gateway | **LiteLLM proxy** | Routes across *hosts*, which is the requirement here. Model aliases, retries, fallbacks, health checks and per-key auth, over an OpenAI-compatible surface |
| Per-node on-demand loading | ollama, or llama-swap for a llama.cpp/MLX node | ollama already loads on demand; llama-swap adds the same behaviour to runtimes that do not have it. Note it swaps *within* one host -- it is not a substitute for the gateway |
| Transport | **SSH tunnels**, one local port per remote node | Reuses the ssh aliases and keys this repo already manages, and leaves every runtime on loopback |

**Do not bind a runtime to `0.0.0.0`.** ollama's server is unauthenticated; on a LAN
that is an open completion endpoint and, worse, an open file-write endpoint via model
creation. An SSH tunnel from the gateway host costs one long-lived process per node and
closes the question:

```sh
ssh -N -L 11435:127.0.0.1:11434 <alias>   # that node now answers on 127.0.0.1:11435
```

A WireGuard or Tailscale mesh is the alternative when nodes roam off the LAN, and is
the better answer once laptops are involved full time -- but it is a second piece of
infrastructure to own, so start with tunnels.

### Assigning roles

Specialise by what each node is *best* at, not by what it can merely run. The pattern,
in capability terms:

| Alias | Wants | Because |
|---|---|---|
| `fast` | The highest-bandwidth GPU, smallest model | Bandwidth sets tok/s, and a 4B model on a discrete card feels instant |
| `chat` | The most unified memory | A 20-30B MoE needs capacity more than bandwidth, and that is what a large Mac has |
| `long` | The most RAM behind the GPU | KV overflow lives in system RAM; reach comes from capacity |
| `vision` | Wherever the vision model is resident | Visual tokens land in the KV cache, so this one wants headroom, not speed |
| `embed`, `rerank`, `stt`, `ocr` | The weakest always-on node | All small, all tolerant of modest hardware, and all better off never competing with interactive work |

Two practical rules fall out of it:

- **Intermittent nodes are never primary.** A laptop sleeps, and leaves the house. Give
  the gateway a health check and a fallback for every alias a laptop serves, and keep
  the always-on machine as the default for anything interactive. A Mac serving a shift
  wants to stay awake while it does -- `caffeinate -s` for the duration, rather than a
  permanent power-setting change.
- **One resident model per node is the point.** Pointing two aliases at the same node
  reintroduces exactly the eviction cost that spreading them out removed.

### Uniform surface beats a faster runtime, at first

On Apple Silicon, MLX-based servers generally beat GGUF-on-Metal for the same model, so
there is a real argument for an MLX runtime on the strongest Mac. There is a better
argument for running **the same ollama surface everywhere** to begin with: identical
API shape, identical environment variables, identical verification, and one recipe
shape per platform. Add the faster runtime to the one node where the gain is worth a
second thing to maintain, not to all of them.

## Status: capacity pooling is closed

Decided 2026-11-10, after the Thunderbolt 5 finding above. **Capacity pooling is not
being pursued on this fleet.** The reasoning is now short enough to state as three
facts:

1. The only fabric that makes splitting a model fast is Apple-to-Apple, and this fleet
   is mixed, so the fast path is unavailable by construction.
2. The cross-platform path, llama.cpp RPC, buys capacity at a throughput cost and says
   so itself. Nothing currently worth running fails to fit on a single node.
3. The cheap lever is elsewhere. Harness overhead and model choice are worth 20x
   between them; clustering is the most expensive item on the list for the smallest
   gain.

So the clustering question resolves to **throughput pooling**, and the only open work
is the gateway in *[What to build instead](#what-to-build-instead)* -- which needs
nothing distributed. Two triggers would reopen the question, and only these two:

- **A model worth running that fits nowhere on one node.** Capacity is the one thing
  pooling genuinely delivers.
- **Two Thunderbolt 5 Macs on macOS 26.2 or later.** The only configuration where
  pooling buys speed as well.

Neither is a reason to hold the question open in the meantime. The sizing method below
is unaffected: it describes single nodes, which is what this fleet will run.

## Sizing a node

The method, to apply to the figures `scripts/inventory.ps1` or `inventory.sh`
collects. Four numbers decide everything: VRAM capacity, VRAM bandwidth, system RAM
capacity, and system RAM bandwidth.

**1. Usable VRAM is not total VRAM.** Subtract roughly 0.5-1.0 GiB for the CUDA (or
Metal) context and the runtime's compute buffers. Subtract another 1.0-1.5 GiB if the
desktop is drawn by this GPU. A machine with an integrated GPU should drive its
display from that instead and leave the discrete card idle -- `nvidia-smi` reporting
`display_active: Disabled` and `memory.used: 0 MiB` is the confirmation, and it is
the cheapest GB of VRAM available anywhere.

**2. Weights and KV cache share that budget.** Per-token KV cost is

```
bytes_per_token = 2 * layers * kv_heads * head_dim * bytes_per_element
```

which for a typical 8B model with grouped-query attention is around 128 KiB per token
at fp16 -- so 1 GiB per 8K of context. A `q8_0` KV cache halves it. Models using
sliding-window attention (Gemma 3 among them) cost far less than the formula suggests
and are disproportionately good on small cards.

Treat the result as a floor rather than a budget. Measured against `ollama ps` on an
8B model with a q8_0 cache, growing 4K to 16K cost about 85 KiB per token where the
formula predicts 72, and 16K to 32K about 119 KiB -- because the compute buffers grow
with context too, and faster than linearly. Allow headroom, then confirm placement.

**3. Estimate generation speed from bandwidth, not from FLOPS.**

```
tok/s ~= (VRAM_bandwidth_GB_s / resident_size_GB) * 0.9
```

Check the bus width of any card before trusting its model number: a 128-bit card can
have barely half the bandwidth of an older, wider one, and that halves the answer
above. For hybrid GPU + CPU execution, the harmonic mean of the two bandwidths
weighted by the fraction of weights on each side gets you close, and it is always
worse than the arithmetic intuition suggests.

The `0.9` is calibrated against measurement, not assumed. Four 2.9-5.3 GB models
measured on one 8 GB card came out at 0.91 to 1.05 of their bandwidth ceiling with
flash attention and a q8_0 KV cache on. An earlier `0.8` here was too pessimistic by
10-40%, so prefer measuring to trusting the formula.

**Measure warm, not cold.** A model's first generation after loading from disk reports
badly inflated timings -- in one case 12 tok/s against a true 49 -- because load and
warmup bleed into the numbers. Generate twice and keep the second. `ollama ps` is the
ground truth for placement: its `PROCESSOR` column says `100% GPU` or gives the split,
and its `SIZE` and `CONTEXT` columns are what the budget arithmetic above should be
checked against.

**4. Prefer fully resident over partially offloaded.** This is the rule that most
often gets broken. A smaller model entirely in VRAM usually beats a larger one that
spills, on both speed *and* quality -- because the quant needed to make the larger one
nearly fit does more damage than the extra parameters repair. Dropping a dense model
to 3-bit to squeeze it in is reliably a downgrade.

**5. Distinguish dense from MoE when sizing system RAM.** For a mixture-of-experts
model only a few billion parameters are active per token, so hybrid execution with
experts in system RAM stays usable. For a dense model it does not: a 24B dense model
at Q4 runs in the low single-digit tok/s regardless of how much RAM is fitted,
because the limit is RAM *bandwidth*, not capacity. This is why "add more RAM" helps
MoE and does nothing for dense -- and why it is worth knowing which you are buying
for before spending.

As a rough map, at Q4 and allowing for a useful context window:

| Model class | Q4 weights | Wants |
|---|---|---|
| 3-4B dense | 2-3 GB | 6 GB VRAM. Trivial; good for autocomplete and classification. |
| 7-8B dense | 4.5-5 GB | 8 GB VRAM. The sweet spot on consumer cards. |
| 12-14B dense | 7.5-9 GB | 12 GB VRAM. Marginal at 8 GB -- it will spill. |
| 20-24B dense | 12-15 GB | 16-24 GB VRAM. Not worth running hybrid. |
| 30B-class MoE, ~3B active | 17-19 GB | 24 GB VRAM, or ~32 GB system RAM for hybrid. |
| 70B dense | 40 GB+ | Multiple GPUs, or the capacity pooling above. |

Keep the resulting per-machine conclusions out of this repository. A short sizing note
beside the collected inventory is the right home; see below.

## Running models

`bin\install.ps1 ollama` installs the runtime on a Windows node and pulls a default
set of models sized for an **8 GB-class CUDA card** -- `qwen3:8b` for interactive
work, `qwen3:4b` as the base for the derived agent models and for anything that should
feel instant, and `qwen2.5vl:7b` for image input, since the other two are text-only.
About 12.8 GB of weights in total.

A fill-in-the-middle completion model was in this set and was dropped: measured against
Rust it produced a correct idiomatic body on an easy case and non-compiling code on a
lifetime-bounded iterator, which is the wrong failure mode for a tool that inserts
rather than suggests.

Three models on an 8 GB card is not a contradiction: `OLLAMA_MAX_LOADED_MODELS` is 1,
so they swap rather than compete, and each one past the first costs disk rather than
VRAM. Sizing is per model, not per set.

**Choosing a vision model** is the one case where parameter count is the wrong
yardstick. Fidelity on dense text and documents comes from the vision encoder's input
resolution, so a model with a native dynamic-resolution encoder beats a larger one
with a fixed low-resolution encoder at the same size. The VRAM cost is also different
in kind: visual tokens land in the KV cache, so what a small card limits is image size
and count per prompt, not whether the model loads. Cap input pixels rather than
reaching for a smaller model.

It is opt-in and not in `all`, because downloading model weights is not something a
machine bootstrap should do as a side effect.

Override the set with `OLLAMA_RECIPE_MODELS` (comma separated) and the location with
`OLLAMA_MODELS`, which otherwise follows `DEVDRIVE_LETTER` to `<letter>:\models\ollama`
-- a subdirectory rather than the root of `models\`, so a second runtime's raw GGUFs
can live beside it without the two interleaving.

The recipe also pins four server settings that an 8 GB budget calls for. They are read
by the ollama *server*, not the CLI, which is why the recipe restarts it after writing
them: a server left running from before keeps its old values and silently ignores the
pinned model directory.

| Variable | Value | Why |
|---|---|---|
| `OLLAMA_FLASH_ATTENTION` | `1` | FlashAttention-2, on any NVIDIA card of compute capability 8.0 or later. Required for the KV cache setting below, and cheaper prefill either way. |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | Halves per-token KV cost, which is what makes the context below affordable. The accuracy cost is small but not zero. |
| `OLLAMA_CONTEXT_LENGTH` | `16384` | ollama defaults to 4096, short for coding and long-document work. Without this the KV setting above buys nothing, because nothing asks for a bigger window. |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | Two models do not fit in 8 GB together; the loser is offloaded to system RAM and runs several times slower. |
| `OLLAMA_KEEP_ALIVE` | `30m` | Reloading several GB of weights dominates short interactive turns. Free when nothing else is using the GPU. |

The context figure is measured rather than derived. On an 8 GB card an 8B model at
`num_ctx` 4096, 8192 and 16384 all stay at 100% GPU and all generate at the same rate;
at 32768 the same model reaches 8.2 GB, spills to a 22%/78% CPU/GPU split, and loses
about 40% of its throughput. So 16384 is free and 32768 is expensive, with nothing in
between to tune. Raise it on a larger card and confirm `ollama ps` still reports
100% GPU; drop `OLLAMA_KV_CACHE_TYPE` to compare quality against an unquantised cache.

Still to do, and the reason this is only half of step 3 below: a **gateway**. That is
now the main open piece of work, and it has its own section -- see
*[Routing](#routing-one-endpoint-many-machines)*.

## Taking inventory

Three scripts, none of which install or change anything:

| Script | Runs on | Does |
|---|---|---|
| `scripts/inventory.ps1` | Windows | Prints this machine's inventory as JSON |
| `scripts/inventory.sh` | macOS, Linux | The same, in the same schema |
| `scripts/fleet-inventory.sh` | the machine you drive from | Collects from every node over SSH and prints a comparison |

```sh
scripts/fleet-inventory.sh                       # hosts from the config file
scripts/fleet-inventory.sh studio box:windows    # or named as arguments
```

Hosts are **ssh aliases, never addresses**: the real `HostName`, `User`, and
`IdentityFile` belong in `~/.ssh/config.local`, which `source/.ssh/config` includes
and this repo never tracks. The host list lives outside the repo for the same
reason, at `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/fleet.hosts` -- the same
place, and the same argument, as the privacy gate's deny-list:

```
# alias        platform
studio         local       # this machine, collected without ssh
box            windows
pi             unix        # the default, so the word is optional
```

The platform is **declared rather than probed**, because the Windows nodes set
sshd's `DefaultShell` to PowerShell, so `ssh host uname -s` fails there and any
probe would be guessing from the shape of an error.

Nothing is copied to the nodes. The matching collector is piped over SSH on stdin
(`bash -s`, or `powershell -Command -`, which reads all of stdin as one script
block and so accepts the collector's top-level `param()`), which means a node can
never run a stale copy.

Results are written to `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/inventory/`,
outside the repo. That is deliberate, and it is where **per-machine sizing notes
belong too**: a collected set names every machine and its hardware, which is exactly
the inventory a public dotfiles repo must not carry. `.gitignore` also refuses
`inventory/` in-tree, as a second line of defence.

Load your key into the agent first (`ssh-add`) if it has a passphrase, or SSH will
prompt once per host.

## Next steps: evaluating the fleet

Six stages, in order, each with the condition that says it is finished. Nothing here is
distributed, and nothing here should be bought before stage 2 says what the fleet
actually is.

**0. Make every node reachable.** Each machine needs an ssh alias in
`~/.ssh/config.local` and a line in `fleet.hosts`; on a Mac that also means enabling
**Remote Login** (System Settings > General > Sharing). Load the key once with
`ssh-add`.
*Done when* `ssh <alias> true` succeeds for every node without a prompt.

**1. Collect, do not estimate.** `scripts/fleet-inventory.sh` with no arguments reads
the host list and pipes the matching collector over SSH.
*Done when* the inventory directory holds one JSON per node. Re-run it after plugging
in any node still on Wi-Fi.

**2. Classify each node from four facts.** This is the stage that answers what routing
can achieve, and it is mechanical once the numbers exist:

| Fact | Threshold | What it decides |
|---|---|---|
| Architecture | Apple Silicon or discrete GPU; **Intel Mac excluded** | Whether the node is a candidate at all |
| Memory bandwidth | ~68 GB/s base M1 and ~100-120 later base chips, ~150-273 Pro, ~300-546 Max, ~800 Ultra, ~272 for a mid-range discrete card | Speed, so which node takes the latency-sensitive aliases |
| Usable memory for weights | Unified memory on a Mac; VRAM on a discrete card | Capacity, so which node takes the large-model aliases |
| Always on, or not | A desktop versus a laptop | Whether an alias may be primary, or needs a fallback behind it |

*Done when* every node has exactly one role and one set of aliases, by the table in
*[Assigning roles](#assigning-roles)* -- and no alias is assigned twice to the same
node, which would reintroduce the eviction cost that spreading them out removed.

**3. Choose the gateway host.** It wants to be always on and always reachable, and it
should be the node that is **least valuable as compute**: a proxy is I/O-bound and
costs a few MB of memory, so putting it on the strongest machine wastes that machine.
*Done when* one host is named, and every other node is a back end rather than a peer.

**4. One runtime per node, on loopback.** The Windows side is done --
`bin\install.ps1 ollama`, see *[Running models](#running-models)*. A macOS counterpart
recipe does not exist yet and is the first piece of code this plan needs. A small
always-on node runs embeddings and nothing else.
*Done when* each node answers on its own `127.0.0.1` and reports the models it holds.

**5. Tunnels, then the gateway.** One `ssh -N -L` per remote node, then LiteLLM in
front with the aliases from stage 2, a health check per back end and a fallback for
every alias a laptop serves.
*Done when* a harness configured with **only** the gateway URL can reach every alias,
and sleeping a laptop does not produce an error the harness sees.

**6. Measure what it bought**, against the criteria below -- which are fixed now, on
purpose, so the answer cannot be rationalised after the build.

### What "meaningful" means, decided in advance

| Question | Measurement | Worth it if |
|---|---|---|
| Residency | Simultaneously-resident models across the fleet; time to first token on an alias untouched for 30 minutes | No evict-and-reload stall anywhere -- the single-node cost today |
| Concurrency | Two harnesses on two aliases at once, versus both on one node | Neither stalls the other |
| Capacity class | Largest model the fleet can serve **fully resident** | It is a class no single node can hold -- the 20-30B MoE band |
| Resilience | Sleep a laptop mid-session | The alias falls back; the harness never sees it |
| Cost of the layer | Gateway overhead per request | Single-digit milliseconds, unmeasurable beside generation |

### The fork this turns on

What stage 2 finds decides how much routing is worth, and the three outcomes are worth
naming before the numbers arrive, so that a disappointing answer is recognised as one:

- **At least one Pro/Max-tier Apple Silicon node with 32 GB or more.** Routing delivers
  a *capacity class the fleet does not have today*. Highest value; build all six stages.
- **Every node base-tier, 24 GB or less.** No new capacity class. What remains is
  residency, concurrency, and moving embeddings and vision off the interactive card --
  real, and still worth the gateway, but a convenience layer rather than a capability
  jump. Do not buy hardware for it.
- **The candidate nodes turn out to be Intel.** They are excluded on bandwidth, and
  routing reduces to a stable URL in front of one GPU node plus an embedding node. Build
  the gateway anyway, for the stable URL; stop there.

**Capacity pooling stays closed** throughout -- see
*[Status](#status-capacity-pooling-is-closed)*. llama.cpp RPC is off the list until one
of the two triggers named there fires, and neither is a thing to go looking for.

## Sources

Secondary sources except where noted; flags, ports, and project status should be
confirmed against each project's own documentation before relying on them.

- [Explore distributed inference and training with MLX (WWDC26 session 233, primary)](https://developer.apple.com/videos/play/wwdc2026/233/)
- [Run local agentic AI on the Mac using MLX (WWDC26 session 232, primary)](https://developer.apple.com/videos/play/wwdc2026/232/)
- [TN3205: Low-latency communication with RDMA over Thunderbolt (primary)](https://developer.apple.com/documentation/technotes/tn3205-low-latency-communication-with-rdma-over-thunderbolt)
- [MLX distributed communication: the JACCL backend (primary)](https://ml-explore.github.io/mlx/build/html/usage/distributed.html)
- [exo-explore/exo (primary)](https://github.com/exo-explore/exo)
- [llama.cpp distributed benchmarks](https://github.com/kjaiswal/llama-cpp-distributed-benchmarks)
- [Distributed llama.cpp RPC on Jetson (Seeed Studio wiki)](https://wiki.seeedstudio.com/ai_robotics_distributed_llama_cpp_rpc_jetson/)
- [Multi-node local LLM inference guide, 2026](https://fungies.io/multi-node-local-llm-inference-guide-2026)
- [llama.cpp across multiple CPU nodes](https://hpcwithus.discoverer.bg/?p=439)
- [exo-explore/ex-exo (archived)](https://github.com/exo-explore/ex-exo)
- [exo overview (CNX Software)](https://www.cnx-software.com/2025/02/18/exo-software-a-distributed-llm-solution-running-on-a-cluster-of-computers-smartphones-or-sbcs/)
- [Deep dive: exo on consumer hardware](https://medium.com/@leif.markthaler/deep-dive-exo-distributed-ai-inference-on-consumer-hardware-068e341d8e3c)
- [Prima.cpp: fast 30-70B inference on heterogeneous home clusters (paper)](https://arxiv.org/pdf/2504.08791)
- [Hetis: serving LLMs in heterogeneous GPU clusters (paper)](https://arxiv.org/pdf/2509.08309)
