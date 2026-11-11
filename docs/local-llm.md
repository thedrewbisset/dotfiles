# Driving a local model

How to talk to a local Ollama server, and what it takes to put an agentic coding
harness in front of one. To check any of it on a machine instead of reading about it,
[verify-local-llm.md](verify-local-llm.md) is the same ground as a runbook: each
command, and the output it gives when it is right. The companion document,
[llm-cluster.md](llm-cluster.md),
covers *which* models a given machine can hold; this one covers what to do with them
once they are there.

Everything below was measured against an Ollama 0.40.x server on an 8 GB-class CUDA
card. Numbers that describe a specific machine's hardware stay out of this repository
— per-machine notes belong in `$XDG_DATA_HOME/dotfiles/inventory/`.

## Three API surfaces, not one

A single Ollama server answers on three different request shapes at the same port.
Which one to use is decided by the client, not by preference:

| Path | Shape | Use it for |
|---|---|---|
| `/api/generate`, `/api/chat` | Ollama's own | Scripts. The only surface that accepts `options` such as `num_ctx` per request |
| `/v1/chat/completions` | OpenAI | Anything built on an OpenAI SDK, including most editor plugins |
| `/v1/messages` | Anthropic Messages | Claude Code and anything else written against the Anthropic SDK |

The Anthropic surface is the one that matters for a Claude Code harness, and it is
recent: Ollama v0.14.0 added it, which is why older write-ups insist on a translation
proxy such as LiteLLM. On a current server no proxy is involved.

Two traps on the URL. The base URL for the Anthropic surface ends at the port —
`http://127.0.0.1:11434`, with no `/v1`, because the client appends the path itself.
And `/v1` alone is the OpenAI surface, so a client pointed at `.../v1` and expecting
Anthropic semantics gets a 404 that reads like the server is down.

## Invocation shapes

### Command line

```powershell
ollama run qwen3:8b                      # interactive REPL
ollama run qwen3:8b "one-shot prompt"    # one turn, then exit
ollama run qwen3:8b --verbose "..."      # same, plus a timing report
Get-Content file.py | ollama run qwen3:4b "What does this do?"
```

`--verbose` is the cheapest honest benchmark available, because it separates the
numbers that get conflated:

```
total duration:       3.2155395s
load duration:        2.1443168s     <- weights off disk; not inference
prompt eval rate:     350.37 tokens/s <- prefill, scales with prompt length
eval rate:            84.62 tokens/s  <- generation; the number people quote
```

A first run after a load reports a `total duration` dominated by `load duration`.
Measure the second run, not the first — see *Measure warm, not cold* in
[llm-cluster.md](llm-cluster.md).

Server-side state, all of it worth checking before concluding anything about speed:

```powershell
ollama ps                  # what is loaded, how big, and GPU vs CPU placement
ollama list                # what is on disk
ollama show qwen3:8b       # context length, quantisation, and capabilities
ollama show --template ... # the chat template, including its tool-call contract
ollama stop qwen3:8b       # evict now rather than at OLLAMA_KEEP_ALIVE
```

The `PROCESSOR` column of `ollama ps` is the ground truth for whether a model is
resident. A model reading `22%/78% CPU/GPU` has spilled, and no amount of arithmetic
about weight sizes overrides it.

### HTTP

Ollama's own surface, which is the only one that takes per-request options:

```sh
curl -s http://127.0.0.1:11434/api/chat -d '{
  "model": "qwen3:4b",
  "stream": false,
  "options": { "num_ctx": 32768, "temperature": 0.2 },
  "messages": [{ "role": "user", "content": "Hello" }]
}'
```

The response carries `eval_count` and `eval_duration` (nanoseconds), so
`eval_count / (eval_duration / 1e9)` is generation throughput without a stopwatch.

The Anthropic surface, which is what a Claude Code harness sends:

```sh
curl -s http://127.0.0.1:11434/v1/messages \
  -H 'content-type: application/json' \
  -H 'x-api-key: ollama' \
  -H 'anthropic-version: 2023-06-01' \
  -d '{"model":"qwen3:8b","max_tokens":256,
       "messages":[{"role":"user","content":"Hello"}]}'
```

The API key is required by the protocol and ignored by the server; `ollama` is the
conventional placeholder. There is no authentication on this port, which is the
reason to leave the server bound to localhost.

### Baking a context window into a model

`OLLAMA_CONTEXT_LENGTH` is a server-wide default, and the Anthropic and OpenAI
surfaces have nowhere to put a per-request `num_ctx`. So a client that needs a
different window cannot ask for one — the way to give it one is a derived model:

```
FROM qwen3:4b
PARAMETER num_ctx 32768
```

```powershell
ollama create qwen3-agent:4b -f Modelfile
```

This costs no disk worth measuring: a derived model shares the parent's weight blobs
and adds a manifest. It is also the only way to let two models run at two different
windows on one server, which matters because the right window is per-model — a window
that keeps a 4B model fully resident will spill an 8B one.

## Tool calling: declared is not emitted

This is the finding that decides which local model can drive a harness at all, and it
is not visible in any model card.

`ollama show` reports a `tools` capability. That flag means the model's chat template
has a tools section — that the plumbing exists. It does **not** mean the model
reliably uses it. The template tells the model to wrap each call in `<tool_call>`
tags; Ollama's parser looks for those tags and, finding them, emits a structured
`tool_use` block. A model that ignores the tag convention and prints bare JSON instead
produces a perfectly valid-looking text response that no harness can act on.

Measured on the same prompt and schema, against `/v1/messages`:

| Model | `tools` in `ollama show` | `stop_reason` | Content block |
|---|---|---|---|
| Qwen3 8B | yes | `tool_use` | structured `tool_use` |
| Qwen3 4B | yes | `tool_use` | structured `tool_use` |
| Qwen2.5-Coder 7B | **yes** | `end_turn` | **`text`**, holding `{"name": ..., "arguments": ...}` |

In a harness the failure is unmistakable once you know to look for it: the agent
prints a JSON object at you and stops, and the file it was asked to edit is
untouched. It looks like a refusal or a confused model. It is a format mismatch.

The lesson generalises past these three models: a code-completion model is tuned for
fill-in-the-middle, and agentic tool-call formatting is a different post-training
objective. **Do not reach for the model with "coder" in the name to drive an agent.**
Its place is editor completion, where there are no tools to call.

Which is where the second half of this finding comes in, and why the `ollama` recipe
no longer installs a completion model at all. Measured on the same `qwen2.5-coder:7b`,
through `/api/generate` with `prompt` and `suffix` -- the fill-in-middle shape, which
is a different request from everything else in this document, with no chat, no tools
and no system prompt:

| Asked for | Result |
|---|---|
| A `HashMap` word-count body, from a doc comment and signature | correct and idiomatic: `*counts.entry(word.to_string()).or_insert(0) += 1` |
| A lifetime-bounded iterator, `impl Iterator<Item = &'a str> + 'a` | **does not compile** -- yields `&String` where the signature says `&'a str` |

That is the shape of a 7B on a strongly typed language: plausible structure, subtly
wrong types. It even got the genuinely subtle part right, since the returned closure
needs `move` or it cannot borrow a local -- and then missed the `as_str()`. On a
language where the type system is most of the work, a completion that has to be
checked against the compiler every time is worth less than the deterministic
completion `rust-analyzer` already provides: method names, trait members and imports,
instantly and always correctly.

Two mechanical notes if a completion model is ever wanted here. Prefer the `-base`
tag: the instruct tag overran every FIM request, emitting the closing brace and then
inventing a `main()`, a markdown fence and a paragraph of prose -- 259 tokens to
produce five useful lines, which a plugin has to truncate. And watch the latency
budget: 365 ms of prefill plus 18 ms per token means a 20-token completion lands
around 700 ms on a near-empty file, where inline ghost-text wants 100-300 ms, and
prefill grows with however much of the file the plugin sends.

Probe any model before trusting it, with `bin\llm-probe.ps1`:

```powershell
bin\llm-probe.ps1                   # every installed model
bin\llm-probe.ps1 qwen3:8b          # just one
```

It sends one tool schema and reports whether a `tool_use` block came back, so a model
that merely declares the capability is caught in about a second rather than in the
middle of a task.

## Context arithmetic for an agentic harness

A chat client sends a few hundred tokens of prompt. An agentic harness sends its
system prompt and the JSON schema of every tool it owns, on every single turn, before
the user has said anything.

Measured, from a Claude Code run against a local server, for the prompt
*"What is 2+2? Answer with just the number."*:

```
input_tokens: 13821
output_tokens: 108
```

**13.8K tokens of fixed overhead.** That reframes the whole sizing question. A 16K
window — the measured ceiling for an 8B model on an 8 GB card — leaves roughly 2.5K
tokens for the conversation, the files read and every tool result. It is enough to
answer one question and nothing else.

So for agentic use the binding constraint is not throughput, it is the window, and the
model that wins is the one that holds the biggest window on the GPU rather than the
one with the most parameters. Measured on an 8 GB-class card:

| Model | Window | Placement | Warm tok/s |
|---|---|---|---|
| 8B | 16384 | 100% GPU | full speed |
| 8B | 32768 | spills to CPU | about 60% of full |
| 4B | 32768 | **100% GPU** | **full speed** |
| 4B | 65536 | spills to CPU | about 55% of full |

A 4B model at 32K beats an 8B at 16K for this job, because 32K minus 13.8K is a
working budget and 16K minus 13.8K is not. That is the reverse of the usual
bigger-is-better instinct, and it is why the recipe builds a derived 32K model
instead of raising the server-wide default: raising the default to 32K would spill
the 8B that interactive chat uses.

Ollama's own guidance for Claude Code is a window of at least 32K, which agrees.

## Claude Code against a local server

Four environment variables, and the third is the one everybody misses:

| Variable | Value | Why |
|---|---|---|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:11434` | No `/v1`. Does not choose a model |
| `ANTHROPIC_AUTH_TOKEN` | `ollama` | Required by the protocol, ignored by the server |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | the model's real window | Without it, see below |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | the same model you are driving | Avoids a reload, see below |

**Why the window has to be declared.** Claude Code cannot know the context window of
a model ID it does not recognise, so it assumes 200K and says so at startup. Left
alone, it will keep packing context long past what the model can hold, and compaction
never fires because by its reckoning the conversation is barely started.
`CLAUDE_CODE_MAX_CONTEXT_TOKENS` applies directly for an unrecognised ID that does not
begin with `claude-`, which is exactly the local case.

`CLAUDE_CODE_AUTO_COMPACT_WINDOW` is *not* the knob. It accepts 100K to 1M and clamps
anything smaller to the 100K floor, which is several times larger than any window a
local model on consumer hardware can offer. Setting it to 16384 earns a warning and no
effect.

**Why the Haiku model matters.** Claude Code routes background work — conversation
titles and similar — to whatever `haiku` resolves to. Behind a local base URL that
default is a model the server does not have. Pointing it at a *different* local model
is worse than useless when `OLLAMA_MAX_LOADED_MODELS` is 1: each background call
evicts the main model and reloads it afterwards. Measured, the same single-edit task
took 38s with Haiku unset and 94s with Haiku pointed at a second local model. Point it
at the same model you are driving.

### Do not persist these

`ANTHROPIC_BASE_URL` as a user environment variable would redirect *every* Claude Code
session on the machine, including the one against the real API, and the failure is
confusing rather than loud. Set these per invocation. `bin\claude-local.ps1` does
exactly that:

```powershell
bin\claude-local.ps1                                  # default local agent model
bin\claude-local.ps1 -Model qwen3:8b -Context 16384   # something else
bin\claude-local.ps1 -- -p "Summarise README.md"      # pass flags through
```

It sets the four variables for the child process only, so nothing it does outlives the
command.

### What it is honestly like

A single-file edit — read the file, call Edit, confirm — took 39 to 83 seconds across
runs on a local 4B model, and a one-word reply took 13. The agentic loop genuinely
works: tool calls come back structured, results feed back in, and the model recovers
sensibly from a tool error such as a missing file. Plan on tens of seconds per turn
and on the variance being wide, since how much the model chooses to write is most of
it.

Two cosmetic artefacts worth recognising so they do not read as faults. Claude Code
prints a `[claude-code:unrecognized_model]` diagnostic for an unknown ID; a
`modelOverrides` entry in `settings.json` mapping the ID to itself silences it. And it
reports a dollar cost for local tokens, priced as if they were API tokens. They were
free.

## OpenCode

For comparison, OpenCode needed no configuration at all:

```powershell
winget install --id Anomaly.OpenCode --exact
opencode models            # local models already listed as ollama/<name>
opencode run --model ollama/qwen3-agent:4b "..."
```

It discovers a running Ollama server on the default port and enumerates its models,
derived ones included, with nothing written to a config file. Against the same local
model it drove a read-and-report task in about 50 seconds and recovered from a
missing-file tool error by falling back to a glob — the same quality of loop.

Older guides describe a hand-written `provider.ollama` block in
`~/.config/opencode/opencode.json` using `@ai-sdk/openai-compatible` against
`http://localhost:11434/v1`. That is still the escape hatch for a server on a
non-default host or port, but it is no longer needed for the local case.

The trade is the reverse of Claude Code's: nothing to configure, and no equivalent of
`CLAUDE_CODE_MAX_CONTEXT_TOKENS`, so the window is whatever the model and server
agree on. With a derived model that bakes in `num_ctx`, that is the right window
anyway.

## Pi

Pi is the third option and the one not installed here. It is a terminal coding agent
with a deliberately small tool core (read, write, edit, bash) and one agent loop over
many providers, configured through a `models.json` that gives a provider a `baseUrl`
and a model `id` with an `api` of `openai-completions` — so an Ollama server is a
provider like any other, and `ollama launch pi` knows how to wire it.

It requires Node.js 22.19 or newer, which used to be the argument against it. That no
longer applies — `bin\install.ps1 fnm` provides Node 24 — so `bin\install.ps1 pi`
installs it and writes the provider entry.

**Measured, and it is not close.** Same prompt, same model, same server as the Claude
Code figure above:

| | Claude Code | Pi |
|---|---|---|
| *"What is 2+2?"* | **13,821** input tokens | **699** input tokens |
| After a full read-edit-confirm turn | 15,061 | 1,753 |
| Of a 32K window, left for work | 58% | **98%** |
| Wall clock, trivial reply | 12.6 s | 6.9 s |
| Wall clock, single-file edit | 39–83 s | 29 s |

Twenty times less overhead, because Pi's core is four tools — read, bash, edit, write —
and a short preamble, where Claude Code ships its full tool surface on every turn.

This is not a verdict on the harnesses. Claude Code's prompt buys subagents, skills,
MCP and far more tooling, and against a hosted model with a 200K window the overhead
is a rounding error. It is a verdict about *this* hardware: when the window is the
binding constraint, the leanest harness wins, and 699 against 13,821 is the whole
argument.

Pi's configuration lives in `~\.pi\agent\models.json` — already home-relative rather
than under AppData, so unlike most tools here there is nothing to pin:

```json
{
  "providers": {
    "ollama": {
      "baseUrl": "http://127.0.0.1:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [
        { "id": "qwen3-agent:4b", "reasoning": true, "contextWindow": 32768, "maxTokens": 4096,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 } }
      ]
    }
  }
}
```

`contextWindow` is the same problem `CLAUDE_CODE_MAX_CONTEXT_TOKENS` solves — Pi
defaults an unknown model to 128000 — but it sits in the same file as the provider, so
there is no environment variable to forget. `maxTokens` is an output cap rather than
the window, and Pi's default of 16384 would reserve half of a 32768 window, so the
recipe sets 4096. `cost` is required by the schema; zeroes keep the session footer from
reporting a hosted model's prices for free tokens.

One property of a global npm install under a version manager, worth knowing before it
surprises you: the package belongs to the Node version it was installed under, so
`fnm default <other>` leaves Pi behind on the old one. Re-run the recipe after changing
the default version.

## Which harness

All three measured the same way — the same trivial prompt, the same model, the same
server — reading the usage each one reports for itself:

| | Claude Code | OpenCode | Pi |
|---|---|---|---|
| **Prompt overhead per turn** | **13,821** tokens | **7,215** tokens | **699** tokens |
| Of a 32K window | 42% | 22% | **2%** |
| After a full read-edit-confirm turn | 15,061 | 8,305 | 1,753 |
| Local wiring | 4 env vars | none | `models.json` |
| Protocol | Anthropic `/v1/messages` | OpenAI `/v1` | OpenAI `/v1` |
| Window control | `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | model's own | `contextWindow`, same file |
| Extra runtime | none | none | Node 22.19+ (`bin\install.ps1 fnm`) |
| In this repo | `bin\claude-local.ps1` | `bin\install.ps1 opencode` | `bin\install.ps1 pi` |

The spread is almost 20× end to end, and OpenCode lands squarely between the two: half
of Claude Code's prompt, ten times Pi's. Its overhead is not a lighter version of the
same thing — it carries a comparable tool surface and spends the tokens describing it,
where Pi's four tools and short preamble are a different design decision.

**On local hardware, start with Pi.** The overhead row dominates everything else. Use
OpenCode when you want a second opinion on whether a problem is the harness or the
model — it needs no configuration at all, so it is the cheapest way to check, and its
22% leaves a workable budget. Use Claude Code locally when you specifically want its
tooling and can pay for the window, which means giving it more than 32K.

None of this is a lock-in decision: all three drive the same server, and the derived
models and the probe script are shared by whichever one is in front.

## The window ceiling: VRAM sets the free one, RAM extends it

It is tempting to read "32768 is the ceiling on an 8 GB card" as a hard wall. It is
not. It is the ceiling on a window that costs *nothing*, and the two are different
claims.

Weights and KV cache both live in VRAM, so 8 GB is what decides how much window stays
GPU-resident. Past that, llama.cpp offloads the overflow to system RAM rather than
failing — so RAM buys more window, paid for in bandwidth. Measured on a 4B model, same
weights, only `num_ctx` changing:

| Window | `ollama ps` SIZE | Placement | Warm tok/s | System RAM left |
|---|---|---|---|---|
| 32768 | 5.3 GB | **100% GPU** | **84.7** | plenty |
| 65536 | 8.6 GB | 26%/74% CPU/GPU | 46.9 | comfortable |
| 131072 | 14 GB | 57%/43% CPU/GPU | 21.5 | **almost none** |

So the honest shape of it: **VRAM sets the speed, RAM sets the reach.** Doubling the
window costs roughly half the throughput each time, and the wall at the bottom of that
table is system RAM, not VRAM — which is why more RAM genuinely does change this
calculation, where for a *dense model above 14B* it does not. The two cases get
confused easily:

- **More window on a model that fits**: RAM helps. The overflow is KV cache, the
  bandwidth penalty applies only to the offloaded share, and the result is usable.
- **A bigger dense model**: RAM does not help. Every parameter is read for every
  token, so the whole model runs at system-RAM bandwidth and lands in low single-digit
  tokens per second regardless of how much RAM there is.
- **A bigger MoE model**: RAM helps, because only a few billion parameters are active
  per token. This is the case the upgrade note in the sizing method is about.

### The same task, all three harnesses

A real multi-file job rather than a token count: three files, one cross-file bug —
`report.py` calls `u.displayname()` where `models.py` defines `display()`. Each
harness had to read all three files, find it and fix it. Same model, same server.

| Harness | Window | Result | Time | Context at the end |
|---|---|---|---|---|
| Pi | 32768 | fixed | **25–54 s** | 3,100–4,900 |
| OpenCode | 32768 | fixed | 101–115 s | ~9,900–10,300 |
| Claude Code | 65536 | fixed, 5 turns | 319 s | 19,194 + 67,803 cache reads |
| Claude Code | 32768 | **failed**, 10 turns | 379 s | 31,056 + 28,603 cache reads |

The last row is the whole argument, and Claude Code diagnoses itself better than any
summary could:

```
Autocompact is thrashing: the context refilled to the limit within 3 turns of the
previous compact, 3 times in a row.
```

At 32768, 13.8K of fixed overhead plus three files plus tool results overruns the
window, compaction fires, the compacted context plus the next turn overruns it again,
and the loop collapses after three rounds. It had actually written the correct fix
before giving up, which makes it worse rather than better — the work was done and the
session failed anyway.

Give it 65536 and the same task completes cleanly. So "Claude Code only has room for
one file" is **exactly right at the window this card gives for free, and wrong one
doubling up.** The fix is a derived model, the same one-liner as before:

```
FROM qwen3:4b
PARAMETER num_ctx 65536
```

Which is why the ollama recipe derives **two** models rather than one, and why
`bin\claude-local.ps1` defaults to the wider of them. The right window is per
*harness*, not per machine: Pi and OpenCode are comfortable at 32768 and run at full
GPU speed there, and Claude Code is not, so it gets the 65536 model and pays ~45% of
throughput for a session that works. Asking for the narrow one explicitly prints a
warning, because a window this harness is known to thrash in should not be something
you discover three compactions into a task.

What that buys is a working session at about half the throughput. What it does not buy
is parity: Pi did the identical task 6–13× faster, at half the window, using a
twentieth of the context, and never came close to compacting. The ordering across all
four rows is monotonic in prompt overhead, which is the point.

### Where clustering comes in, and where it does not

Pooling VRAM across machines is a capacity technique, not a speed one, and it is worth
being precise about which problem it addresses:

- **It does not reduce harness overhead.** 13,821 tokens is 13,821 tokens on any
  hardware. The 20× lever is the harness, and it is free.
- **It does not make a given model faster.** Splitting layers across machines adds a
  network round trip per token to what is already a bandwidth-bound workload. Tensor
  parallelism, which would actually divide the per-token work, needs interconnect
  bandwidth in the NVLink class; over Ethernet the all-reduce traffic per layer
  dominates and throughput collapses. See *Why pooling VRAM over a LAN disappoints*
  in [llm-cluster.md](llm-cluster.md).
- **It does raise the capacity ceiling.** With layers sharded across nodes, each node
  holds the KV cache for its own layers, so total resident window and total model size
  both scale with the number of GPUs. That is a real gain, and it is the only one.

So clustering is the answer to "I want to run a model this machine cannot hold", not
to "I want more context at a usable speed". It also costs a second GPU machine to find
out, which makes it the most expensive item on a list where the cheapest item is 20×.

The order of leverage, measured rather than assumed:

| Lever | Buys | Costs |
|---|---|---|
| A leaner harness | **20×** less overhead; a failing task becomes a 25 s one | nothing |
| A derived 64K model | A window Claude Code can work in | ~45% of throughput |
| More system RAM | Wider windows safely, and the 20–30B MoE class | a pair of DIMMs |
| A GPU one VRAM tier up | Window *and* speed together | one card, if the PSU allows it |
| Clustering | Models no single node can hold | a second GPU node, and latency per token |

A note on that fourth row, because it is easy to write off as "a new machine" and that
is usually wrong. Doubling VRAM moves the *free* window up a tier — on an 8 GB card
32768 is free and 65536 is paid for; on 16 GB the same model holds 131072 fully
resident — and the bandwidth that comes with the tier raises throughput at the same
time. Whether a given machine can take it comes down to two things software cannot
read: the PSU's wattage and spare connectors, and the physical clearance in the case.
Both are a matter of looking rather than guessing, and the motherboard and CPU are
rarely what stops it. The *useful* step is one tier of VRAM, not the flagship: it is
the tier that changes which windows are free, and the flagship mostly changes how fast
a model you could already hold runs.

### Is Claude Code simply not for local inference?

Not quite. It works, it is wired up here, and on a 64K window it completed a
multi-file task correctly. But it was built against a 200K window where 13.8K of
system prompt is 7% of the budget, and on an 8 GB card the same prompt is 42% of what
the hardware gives for free. Nothing about that is a defect; it is a design centre, and
this hardware is a long way outside it.

The practical reading: use Claude Code locally when you want its specific tooling on a
focused task and have given it 64K, and reach for Pi the rest of the time. Revisit
when either number moves — a card with 16 GB or more of VRAM makes 64K free rather
than paid for, and that single change puts Claude Code back in its design centre.

That is the one upgrade worth sizing against a measurement rather than a review score:
what matters is not the benchmark tier but **which windows the VRAM makes free**, and
that is answered by taking `ollama ps`'s SIZE column at the window you actually want
and comparing it to the card's capacity.

## What a local server here will not do

- **Embeddings.** None of the installed chat models carry the `embedding` capability,
  and `/api/embed` against one returns *"This server does not support embeddings"*.
  Retrieval needs a purpose-built embedding model pulled alongside them.
- **Scripted setup through `ollama launch`.** `ollama launch <integration>` configures
  Claude Code, OpenCode, Pi and a dozen others, but it requires an interactive
  terminal and refuses to run headless even when given `--model` and `--yes`. It is a
  convenience for a human at a console, not a building block for a recipe — the same
  lesson as `ollama app.exe` needing a window station. Recipes write the configuration
  themselves, which is more legible anyway.
- **Come back after a reboot, by itself.** Verified rather than assumed, and the
  assumption was wrong: after a `winget` install there is no Ollama entry under either
  `Run` key, nothing in the Startup folder, no service and no scheduled task. The tray
  app appears to write its own `Run` entry the first time it runs, and it never runs
  under this recipe because it has no window station. So a server started by a shell
  lives exactly as long as that shell, and after the next restart every harness fails
  with a connection refused that reads like a configuration problem. The recipe
  registers a logon task (`\dotfiles\Serve ollama`) running `ollama serve` to close
  that — a logon task rather than a `Run` entry because a console program in `Run`
  flashes a window, and as the logged-in user rather than SYSTEM because the `OLLAMA_*`
  settings are *user* environment variables, which a SYSTEM task would not read.
- **Anything over the network.** The server is bound to localhost and unauthenticated.
  Exposing it is a separate decision with its own requirements, not a flag.

## Sources

- [Claude Code with Anthropic API compatibility](https://ollama.com/blog/claude) — Ollama's own setup notes and the v0.14.0 requirement
- [Claude Code model configuration](https://code.claude.com/docs/en/model-config) — `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, the auto-compact window's 100K floor, `modelOverrides`
- [OpenCode self-hosted models](https://www.mintlify.com/opencode-ai/opencode/advanced/self-hosted-models) — the explicit provider block, for non-default hosts
- [pi-mono](https://github.com/badlogic/pi-mono) and [pi.dev provider docs](https://pi.dev/docs/latest/providers) — install requirements and `models.json`
