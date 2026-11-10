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
| **exo** | Verify before investing -- the repository found for it is archived. |
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
The caveat is practical rather than technical: the repository located for it
(`exo-explore/ex-exo`) is **archived**, and claims that it matured during 2026 into
a packaged product with a macOS app and a cluster dashboard trace back to a
community wiki that could not be confirmed against any release. Check the official
repository's current state first.

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
work, `qwen2.5-coder:7b` for editor completion (it has the fill-in-middle tokens that
needs, and no Qwen3 coder is small enough), `qwen3:4b` for anything that should feel
instant, and `qwen2.5vl:7b` for image input, since the other three are text-only.
About 17.1 GB of weights in total.

Four models on an 8 GB card is not a contradiction: `OLLAMA_MAX_LOADED_MODELS` is 1,
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

Still to do, and the reason this is only half of step 3 below: a **gateway**. One
OpenAI-compatible endpoint in front of the per-machine runtimes (LiteLLM, llama-swap
or nginx) is what turns several boxes each running ollama into something worth calling
a cluster. Nothing distributed is required for it.

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

## Next steps

1. **Wire up any node still on Wi-Fi** and re-run the inventory to confirm the link
   speed. Clustering only; a single node never touches the network.
2. **Collect every node**, then decide which machine should be primary. The one with
   the most VRAM takes the interactive model.
3. **Stand up one runtime plus a gateway** before attempting anything distributed.
   The runtime is done: `bin\install.ps1 ollama` (see *[Running models](#running-models)*).
   The gateway is not.
4. **Only then** evaluate llama.cpp RPC, and only if a model worth running fits
   nowhere on a single node.

## Sources

Secondary sources except where noted; flags, ports, and project status should be
confirmed against each project's own documentation before relying on them.

- [llama.cpp distributed benchmarks](https://github.com/kjaiswal/llama-cpp-distributed-benchmarks)
- [Distributed llama.cpp RPC on Jetson (Seeed Studio wiki)](https://wiki.seeedstudio.com/ai_robotics_distributed_llama_cpp_rpc_jetson/)
- [Multi-node local LLM inference guide, 2026](https://fungies.io/multi-node-local-llm-inference-guide-2026)
- [llama.cpp across multiple CPU nodes](https://hpcwithus.discoverer.bg/?p=439)
- [exo-explore/ex-exo (archived)](https://github.com/exo-explore/ex-exo)
- [exo overview (CNX Software)](https://www.cnx-software.com/2025/02/18/exo-software-a-distributed-llm-solution-running-on-a-cluster-of-computers-smartphones-or-sbcs/)
- [Deep dive: exo on consumer hardware](https://medium.com/@leif.markthaler/deep-dive-exo-distributed-ai-inference-on-consumer-hardware-068e341d8e3c)
- [Prima.cpp: fast 30-70B inference on heterogeneous home clusters (paper)](https://arxiv.org/pdf/2504.08791)
- [Hetis: serving LLMs in heterogeneous GPU clusters (paper)](https://arxiv.org/pdf/2509.08309)
