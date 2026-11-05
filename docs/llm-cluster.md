# Local LLM cluster

Running local models across the machines on a private LAN: what the hardware
supports, what the available tooling actually does, and which of the two things
people mean by "use the collective compute" is worth building.

The inventory scripts described at the end collect the numbers this planning needs.
Nothing here installs a runtime yet; that waits on real figures for every node.

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

With six nodes this gets worse, not better: pipeline depth is a liability, because
every extra hop is latency added to every token. If a model has to be split, split
it across the two or three strongest machines and leave the rest out of it.

## The interconnect comes first

Before any software, check what the nodes are actually talking over. On the Windows
node the inventory found a **2.5GbE port sitting disconnected while the machine
routed over Wi-Fi 6** at a 1.2 Gbps negotiated rate.

That number flatters Wi-Fi. It is a half-duplex shared medium with variable
multi-millisecond latency, and distributed inference pays that jitter *per token*
rather than once per bulk transfer. Plugging in the wired port is the cheapest
large win available here, and it costs nothing. `fleet-inventory.sh` flags this
case in its notes, because an idle wired port beside a working wireless link is
easy to miss and expensive to keep.

## Options surveyed

| Option | Verdict |
|---|---|
| **llama.cpp RPC backend** | Start here if capacity pooling is genuinely needed. The most mature option and the only comfortable one for mixed CUDA + Metal + CPU nodes. |
| **exo** | Verify before investing -- the repository found for it is archived. |
| **prima.cpp** | Research-grade, but aimed exactly at heterogeneous low-resource home clusters. Closest match to this problem. |
| **vLLM + Ray** | Excellent and production-grade, but not for this cluster: it wants homogeneous GPUs, a fast interconnect, and more than 8 GB per worker. |
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

For six machines on a LAN, throughput pooling is almost certainly the better
investment:

- **One runtime per machine behind a single endpoint.** A gateway such as a LiteLLM
  proxy, llama-swap, or plain nginx gives one OpenAI-compatible URL, six-way
  concurrency, and per-model routing. This is the highest value for the least
  effort.
- **Specialise by hardware.** The strongest GPU takes the interactive chat and
  coding model. Weaker boxes take embeddings, rerankers, speech-to-text, and OCR,
  all of which are small and tolerate modest hardware.
- **Batch work scales nearly linearly.** Document embedding, dataset generation,
  and eval suites are embarrassingly parallel, so six machines really do finish
  roughly six times sooner. This is where a LAN cluster genuinely shines, and it
  needs none of the tooling above.
- **Keep speculative decoding on one box.** Draft and verifier models must sit
  together; a network round trip per token erases the benefit entirely.

## Node profiles

Hardware classes only -- real inventory, with host names and addresses, stays out
of this repo (see *Taking inventory* below).

**The Windows node.** Ryzen 7 7700 (8 cores / 16 threads), RTX 3060 Ti with 8192
MiB of VRAM at compute capability 8.6, and **15.2 GB of RAM in a single DDR5-6000
module**. Compute 8.6 is a good place to be: bf16, INT8/INT4 tensor cores, and
FlashAttention-2 are all supported, with first-class support in llama.cpp CUDA,
ollama, and exllamav2.

Two constraints matter more than the GPU:

- **Single-channel memory.** One module roughly halves memory bandwidth. It costs
  nothing while a model sits entirely in VRAM, but the moment anything spills to
  system RAM throughput roughly halves. A second matching module is the single
  highest-value upgrade, and it reaches 32 GB at the same time.
- **Storage for weights.** The 64 GB ReFS Dev Drive holds `D:\models`, which four
  or five 7B files plus one 14B will fill. The `devdrive` recipe caps the backing
  file at 64 GB and growing it later is straightforward (`diskpart` `expand vdisk`,
  then extend the partition), so decide early whether to expand it or keep weights
  on the system drive.

What fits in 8 GB of VRAM, at roughly Q4:

| Model class | Q4 weights | On an 8 GB card |
|---|---|---|
| 3-4B | ~2-2.5 GB | Trivial and fast. Good for autocomplete, classification, cheap local tooling. |
| 7-8B | ~4.5-5 GB | The sweet spot: fully GPU-resident with room for a useful context window. |
| 12-14B | ~7.5-8.5 GB | Marginal. Needs a smaller quant and a short context to stay resident, or it spills. |
| 30B-class MoE | ~17 GB | Few active parameters per token makes it tempting, but it fits neither the VRAM nor comfortably in system RAM. Revisit after the memory upgrade. |

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
outside the repo. That is deliberate: a collected set names every machine and its
LAN address, which is exactly the inventory a public dotfiles repo must not carry.
`.gitignore` also refuses it in-tree, as a second line of defence.

Load your key into the agent first (`ssh-add`) if it has a passphrase, or SSH will
prompt once per host.

## Next steps

1. **Wire up the Windows node** and re-run the inventory to confirm the link speed.
2. **Collect the other five nodes**, then revisit which machine should be primary.
   If any has more VRAM than 8 GB, that one takes the interactive model.
3. **Stand up one runtime plus a gateway** before attempting anything distributed.
   An `ollama` recipe pinning `OLLAMA_MODELS` to `D:\models` with `Set-UserEnv`
   would follow the pattern the other Windows recipes already use.
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
