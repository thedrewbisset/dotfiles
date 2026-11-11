# Verifying a local model end to end

Two ways to check that the local-model stack works: one command, or by hand. The
script is the one to use; the by-hand section exists because a check you cannot
perform yourself is not much of a check, and because when something is wrong it is
the individual commands that tell you where.

---

## One command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\src\dotfiles\bin\llm-verify.ps1
```

About 45 seconds, and it changes nothing. It prints the value each check actually
read, because `PASS` from a script is only another claim to take on faith, and a
number is what makes a wrong one obvious:

```
llm-verify: server, env, surfaces, windows, harnesses, node on http://127.0.0.1:11434

== server == is it listening, and what started it
   port                      127.0.0.1:11434 open
   version                   0.40.16
   task                      Running, last run 11/10/2026 6:35:33 PM
   last boot                 11/9/2026 12:00:05 PM
   last result               2147946720 (0x800710E0) a start was refused because an instance was already running
   -- started by the logon task: last run is after the last boot
   -- this shell is an SSH session

== env == the settings the server was started with
   OLLAMA_MODELS             D:\models\ollama
   OLLAMA_CONTEXT_LENGTH     16384
   OLLAMA_MAX_LOADED_MODELS  1
   models on disk            6: qwen3-agent64:4b, qwen3-agent:4b, qwen2.5vl:7b, ...

== surfaces == all three API shapes on port 11434, model qwen3-agent:4b
   native /api/chat          content=[READY] thinking=850 chars in=15 out=195
   openai /v1/chat           finish=stop in=15 out=241 content=[READY]
   anthropic /v1/msg         blocks=thinking+text stop=end_turn in=1 out=121 text=[READY]

== windows == the context window each model actually loads with
   qwen3:8b                  context=16384 size=6.3 GB processor=100% GPU
   qwen3-agent:4b            context=32768 size=5.3 GB processor=100% GPU
   qwen3-agent64:4b          context=65536 size=8.6 GB processor=26%/74% CPU/GPU

== harnesses == installed, and pointed at this server
   pi models                 4 registered
   opencode models           6 discovered
   -- ollama/qwen2.5-coder:7b is listed and sorts first -- it declares tools and does not emit them

== node == the toolchain the harnesses were installed with
   npm cache                 D:\caches\npm
   node resolves to          %LOCALAPPDATA%\fnm_multishells\...\node.exe
   D: dev drive              This is a trusted developer volume. ...

no problems found in 45s.
```

(Abridged. A real run prints every variable, every model and the full `fsutil` line.)

A check that reads something it can argue is wrong prints a line starting `!!` and
repeats it in a summary at the end. **The exit code is the number of those**, so the
script is usable from another script: zero means every check got an answer it could
defend.

The default set is read-only. The three slow or destructive checks are opt-in:

| Flag | Adds | Cost |
|---|---|---|
| `-Tools` | loads every installed model to test tool-call compliance | 2-4 min |
| `-Runs` | one real turn through Pi, OpenCode and Claude Code | 3-5 min |
| `-Restart` | kills the server and brings it back through the logon task | seconds |
| `-All` | all three | |

`-Only <names>` runs exactly those, in declared order, instead of the default set:
`server`, `env`, `surfaces`, `windows`, `tools`, `harnesses`, `runs`, `node`,
`restart`. Comma-separated or space-separated, both work.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\src\dotfiles\bin\llm-verify.ps1 -Only surfaces,windows
```

Two more parameters worth knowing: `-Model` sets which model the API and harness
checks talk to (default `qwen3-agent:4b`, the derived 32768 one, which is the largest
window that stays entirely on the GPU here), and `-Models` sets the list whose windows
the `windows` check reads back.

---

## By hand

Run these from an SSH session, which is the harder case: the shell `sshd` hands you is
**Windows PowerShell 5.1** (`HKLM:\SOFTWARE\OpenSSH\DefaultShell`), so nothing below
uses `&&`, `||` or a ternary. Every line is a complete statement that depends on no
other line, and none is long enough to lose to a truncated paste -- the three API
calls, which were, are now shown as the JSON they send rather than as a PowerShell
one-liner wrapping it.

One thing to know before starting, because it explains most of the latency: 
`OLLAMA_MAX_LOADED_MODELS=1`, so the server holds exactly one model. Every step that
switches model pays an eviction and a reload -- 3 to 10 seconds before the first
token. That is the configuration working, not a stall.

### 1. Is the server there, and did it get there by itself?

`llm-verify.ps1 -Only server`

```powershell
Invoke-RestMethod http://127.0.0.1:11434/api/version
```

An error means nothing is listening. That is the interesting case, so:

```powershell
Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama' | Get-ScheduledTaskInfo
(Get-CimInstance Win32_OperatingSystem).LastBootUpTime
```

Compare `LastRunTime` against the boot time. After the boot means the logon trigger
fired and started the server. Before it, with `State` still `Ready`, means it did not
-- and there is a known reason:

> An OpenSSH logon arrives as **logon type 3 (Network)**. A Task Scheduler logon
> trigger fires on *interactive* logons -- console, RDP, unlock -- and not on network
> ones. So after a reboot, a machine reached only over SSH has the task registered,
> `Ready`, and no server running. Confirm it here rather than taking it on faith (the
> Security log needs an elevated shell; over SSH you already have the privileges):
>
> ```powershell
> Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624} -MaxEvents 400 | Where-Object { $_.Message -match 'sshd' } | Select-Object -First 4 | ForEach-Object { $d = ([xml]$_.ToXml()).Event.EventData.Data; '{0}  user={1}  logonType={2}' -f $_.TimeCreated, ($d | Where-Object { $_.Name -eq 'TargetUserName' }).'#text', ($d | Where-Object { $_.Name -eq 'LogonType' }).'#text' }
> ```

That is why the PowerShell profile carries an `SSH_CONNECTION`-guarded block that
probes the port and starts the task when it finds it closed -- see
`source/windows/profile.ps1`. In practice an SSH shell brings the server with it, and
the check above says *which* mechanism got you there.

`LastTaskResult` needs decoding, because two of its three usual values read as
failures and are not:

| Code | Means |
|---|---|
| `0` | last run completed |
| `267009` (`0x41301`) | currently running -- the healthy steady state |
| `267011` (`0x41303`) | has never run |
| `2147946720` (`0x800710E0`) | a start was refused because an instance was already running |

That last one is what you get from running the line below while the server is already
up. Harmless, and `llm-verify.ps1` prints the meaning rather than the number.

```powershell
Start-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama'
```

Under half a second, cold.

### 2. The server is reading the settings that were pinned for it

`llm-verify.ps1 -Only env`

A server that ignored its environment looks healthy and behaves completely
differently, so this is worth two commands rather than trusting step 1.

```powershell
Get-ChildItem Env: | Where-Object { $_.Name -like 'OLLAMA_*' } | Sort-Object Name
```

```
OLLAMA_CONTEXT_LENGTH          16384
OLLAMA_FLASH_ATTENTION         1
OLLAMA_KEEP_ALIVE              30m
OLLAMA_KV_CACHE_TYPE           q8_0
OLLAMA_MAX_LOADED_MODELS       1
OLLAMA_MODELS                  D:\models\ollama
```

That is this shell's view. The server's view is what matters:

```powershell
ollama list
```

If the weights come back at all, `OLLAMA_MODELS` reached the server -- one that missed
it looks under `%LOCALAPPDATA%\Ollama\models`, finds an empty directory, and reports
no models while looking perfectly healthy. Expect the recipe's three, plus the two
derived agent models, plus anything pulled by hand. The second proof is the `CONTEXT`
column in step 4.

### 3. The three API surfaces

`llm-verify.ps1 -Only surfaces`

One port answers three different request shapes. Each is a separate claim worth
testing, because a client pointed at the wrong one gets a 404 that reads exactly like
the server being down. What the script sends, and what to look for:

**`POST /api/chat`** -- Ollama's own, and the only surface that takes `num_ctx` per
request:

```json
{ "model": "qwen3-agent:4b", "stream": false, "think": true,
  "options": { "num_ctx": 8192 },
  "messages": [ { "role": "user", "content": "Reply with exactly: READY" } ] }
```

`think: true` is deliberate. These models reason whether or not you ask; with it
false the model still emits its reasoning but the server stops parsing it out, so raw
`<think>` tags turn up inside `content`. Leaving it on is what separates
`message.thinking` from `message.content`.

**`POST /v1/chat/completions`** -- OpenAI, what Pi and most editor plugins speak.
Header `Authorization: Bearer ollama`:

```json
{ "model": "qwen3-agent:4b", "max_tokens": 512,
  "messages": [ { "role": "user", "content": "Reply with exactly: READY" } ] }
```

Reasoning does not come back in a field of its own here: it is counted in
`usage.completion_tokens` and dropped from `content`, which is why `content` is five
characters and the count is in the hundreds.

**`POST /v1/messages`** -- Anthropic, what Claude Code speaks. Headers
`x-api-key: ollama` and `anthropic-version: 2023-06-01`. The base URL ends at the
port, with no `/v1` -- the client appends the path itself:

```json
{ "model": "qwen3-agent:4b", "max_tokens": 1024,
  "messages": [ { "role": "user", "content": "Reply with exactly: READY" } ] }
```

Expect two content blocks, `thinking` then `text`, and `stop_reason: end_turn`. A
`thinking` block alone with `stop_reason: max_tokens` means the budget was too small
for the reasoning to finish, which is why this one asks for 1024. And `max_tokens` is
the one field this surface refuses to default: a body without it comes back as
`max_tokens is required and must be positive`.

Token counts are not stable across runs -- the same prompt gave output counts of 121,
145, 195 and 213 here, and the Anthropic surface has reported input as both 15 and 1.
Read the shape, not the digits.

### 4. The derived models really do carry their own windows

`llm-verify.ps1 -Only windows`

The whole point of deriving a model instead of restarting the server with a different
`OLLAMA_CONTEXT_LENGTH`. The `CONTEXT` column is the receipt; any request loads the
model, and then:

```powershell
ollama ps
```

| Model | CONTEXT | SIZE | PROCESSOR | Where the window comes from |
|---|---|---|---|---|
| `qwen3:8b` | 16384 | 6.3 GB | 100% GPU | `OLLAMA_CONTEXT_LENGTH`, the server default |
| `qwen3-agent:4b` | 32768 | 5.3 GB | 100% GPU | baked `num_ctx`, overriding the server |
| `qwen3-agent64:4b` | 65536 | 8.6 GB | 26%/74% CPU/GPU | baked `num_ctx`, past the VRAM the card has |

Three things to read off that table. The baked window beats the server default, which
is the only way two models get different windows out of one server. The last row
spills to CPU because weights plus a 64K KV cache no longer fit in VRAM -- the
configuration Claude Code needs, and the reason it is slow rather than broken. And
`ollama list` reporting 2.5 GB for all three `4b` models while `ollama ps` reports 5.3
and 8.6 GB loaded is correct: the derived models share their parent's blobs on disk.

The script flags a derived model that loads at the server default, which is what a
`num_ctx` that did not take looks like -- invisible until a harness runs out of room.

### 5. Tool calls: declared is not emitted

`llm-verify.ps1 -Tools`, or the probe directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\src\dotfiles\bin\llm-probe.ps1
```

The step that decides whether a model can drive a harness at all. `ollama show`
reporting `tools` only means the chat template has a tools section; it says nothing
about whether the model emits the `<tool_call>` tags the server's parser needs in
order to return a structured `tool_use` block.

```
Model            Declares Returned  Stop     Detail
-----            -------- --------  ----     ------
qwen3-agent64:4b yes      tool_use  tool_use get_weather({"city":"Paris"})
qwen3-agent:4b   yes      tool_use  tool_use get_weather({"city":"Paris"})
qwen2.5vl:7b     no       n/a       -        no tools section in the template; not an agent model
qwen3:4b         yes      tool_use  tool_use get_weather({"city":"Paris"})
qwen2.5-coder:7b yes      text only end_turn {"name": "get_weather", "arguments": {"city": "Paris"}}
qwen3:8b         yes      tool_use  tool_use get_weather({"city":"Paris"})
```

`qwen2.5-coder:7b` is the row that matters, and its `Detail` is the whole argument: it
answered with a correct, well-formed JSON tool call *as prose*, in a text block, with
`stop_reason: end_turn`. The model knows what to call. It just did not wrap it in the
tags its own template asked for, so the server had nothing to parse and the harness
has nothing to execute. A code-completion model is tuned for fill-in-the-middle, not
agentic formatting, which is why it is deliberately not registered with any harness
here. Point one at it anyway and the symptom is a model that describes the edit it
would make, forever, and never makes one.

Read the `Returned` column, not `Declares`. Those two disagreeing is the entire reason
the script exists.

That table is a record of a run made when `qwen2.5-coder:7b` was still in the recipe's
default set. It is no longer pulled -- this finding is half the reason, and its
fill-in-middle completion measuring no better on Rust is the other half, both in
[local-llm.md](local-llm.md) -- so a current run on a machine installed from the
recipe shows five rows rather than six.

### 6-8. The harnesses

`llm-verify.ps1 -Runs` does all three. Individually:

```powershell
pi --offline --list-models
pi --offline --no-session -p --mode text --model ollama/qwen3-agent:4b "Reply with exactly: READY"
```

Four models, windows matching step 4, `4.1K` max output -- the recipe sets that
deliberately, because Pi's default of 16384 would reserve half of a 32K window for a
reply that is never that long. `qwen2.5-coder:7b` is absent on purpose. Then `READY`
in 6 to 9 seconds. `--offline` stops it reaching for a hosted provider, `-p --mode
text` is the non-interactive print mode, which is what you want over SSH.

```powershell
opencode models | Select-String ollama
opencode run -m ollama/qwen3-agent:4b --archived "Reply with exactly: READY"
```

Every model on the server shows up, because OpenCode discovers what is there rather
than reading a list the recipe wrote -- so choosing one is on you. 26 to 35 seconds.
The `NotSpecified ... RemoteException` noise above the answer is not an error:
OpenCode writes an ANSI reset to stderr and PowerShell 5.1 turns native stderr output
into an `ErrorRecord`. `--archived` keeps scripted runs out of the session list.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\src\dotfiles\bin\claude-local.ps1 -Prompt "Reply with exactly: READY"
```

The wrapper says what it is about to do before launching anything:

```
model:   qwen3-agent64:4b
server:  http://127.0.0.1:11434
context: 65536 tokens (about 13,800 of it goes to the system prompt and tool schemas)
```

Two preflight checks run before that. If nothing is listening it starts `ollama serve`
itself and waits up to 30 s -- `ollama serve`, not the tray app, which is a GUI program
and exits without binding the port when there is no interactive window station, which
is exactly the case over SSH. And if the server lacks the model it stops there,
listing what the server does have. Provoke the second once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\src\dotfiles\bin\claude-local.ps1 -Model nope:1b -Prompt hi
```

About 35 seconds for that one word, model load included. Watch `ollama ps` from a
second shell while it runs: 65536 context, 8.6 GB, a quarter on the CPU. That the
trivial case is this quick is not evidence about the multi-file case in step 9 -- the
prompt overhead is the same 13,800 tokens either way, but there it is paid per turn
over five turns with three files in context. The environment is set for
the child process only, which `$env:ANTHROPIC_BASE_URL` being empty on return
confirms. Drop `-Prompt` to work interactively.

`ANTHROPIC_MODEL` and `ANTHROPIC_DEFAULT_HAIKU_MODEL` point at the same model on
purpose: with `OLLAMA_MAX_LOADED_MODELS=1`, a different background model makes every
background call evict the main one and reload it -- 94 s against 38 s on the same
single-edit task. Two notes on the wrapper's interface, both PowerShell 5.1
limitations rather than choices: a script has no `--` pass-through, so arguments go
through `-Prompt` or trailing `-ClaudeArgs`, and single-dash short flags like `-p` are
swallowed by parameter matching before Claude Code sees them -- use the long forms.

### 9. The comparison, on a real task

Steps 6-8 prove the wiring. This shows why the wiring is not the interesting part.
Pick a directory with three or four small source files and give each harness the same
job -- "read these files and tell me what calls what" -- then compare.

| Harness | System prompt + tool schemas | Multi-file task |
|---|---|---|
| Pi | 699 input tokens | 25-54 s |
| OpenCode | 7,215 | 101-115 s |
| Claude Code | 13,821 | 319 s at a 64K window; aborts at 32K |

Monotonic in prompt overhead, and that overhead is resent every turn. At 32K, Claude
Code fails with `autocompact is thrashing`: its own prompt plus three files plus
history no longer leaves room to answer. That is the measurement behind the warning
`claude-local.ps1` prints below 65536, and behind the recipe deriving a 64K model.

### 10. Reboot survival

`llm-verify.ps1 -Only restart` does the first part. By hand:

```powershell
Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force
Invoke-RestMethod http://127.0.0.1:11434/api/version
Start-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama'
Invoke-RestMethod http://127.0.0.1:11434/api/version
Get-Process ollama | Select-Object Id, StartTime
```

The first version call must fail and the second must answer. Measured here: back up
in 0.8 s. Note that the scheduler goes on calling the task `Running` after the process
it started is gone and will refuse to start another instance, so a stop may be needed
first -- the script handles that, which is the one thing the by-hand version above
does not.

**The profile's SSH block.** Kill the server, then open a *second* SSH session and run
nothing but the version call. It should answer: the profile probed the port on the way
in, found it closed, and started the task. Re-running it in the first session shows
nothing, because that shell's profile has already run.

**With a reboot.** Restart, SSH in, and run step 1. `LastRunTime` after boot means the
logon trigger fired, so someone logged in at the console. Before boot, with the server
answering anyway, means the profile block covered you. Either way the server is there;
it is worth knowing which.

For a server that comes up after a reboot with *no* logon of any kind, the logon
trigger is the wrong mechanism and the profile block only helps once someone connects.
That wants a task that runs whether or not the user is logged on: an `S4U` principal
and an at-startup trigger. Registering one needs an elevated shell.

```powershell
Set-ScheduledTask -InputObject (Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama') -Trigger @((New-ScheduledTaskTrigger -AtStartup), (Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama').Triggers[0]) -Principal (New-ScheduledTaskPrincipal -LogonType S4U -RunLevel Limited -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name))
```

The recipe does not do this on its own: it needs elevation the rest of the recipe does
not, and an S4U task is a persistence mechanism that should be a deliberate choice
rather than a side effect of installing a model server. This is also the one command
in this document that has not been run here -- the principal and trigger objects were
verified to construct, the `Set-ScheduledTask` was not applied.

### 11. Node, on the Dev Drive

`llm-verify.ps1 -Only node`

Not about models, but it is what two of the three harnesses are installed with.

```powershell
node -v
npm -v
npm config get cache
(Get-Command node).Source
fsutil devdrv query D:
```

The cache on `D:` is the point -- `node_modules` and the npm cache are what a Dev
Drive's ReFS and Defender performance mode exist for. A `fnm_multishells` path in
`(Get-Command node).Source` means the profile's fnm block is active in this shell; in
a shell that has not loaded the profile (`powershell -NoProfile`, `cmd`, Git Bash)
expect `D:\caches\fnm\aliases\default\node.exe`, the junction the recipe put on PATH
so node works outside PowerShell at all. Both answers are correct, and seeing one in
each place is the verification.

---

## What failure looks like

| Symptom | Cause |
|---|---|
| `Invoke-RestMethod` connection refused | Server down. Step 1 -- most likely the logon trigger did not fire for an SSH logon |
| 404 on a request that looks right | Wrong surface: `/v1` alone is OpenAI; the Anthropic base URL ends at the port |
| `max_tokens is required and must be positive` | The Anthropic surface does not default it. Step 3 |
| `ollama list` empty, server healthy | `OLLAMA_MODELS` not in the server's environment; it is looking under `%LOCALAPPDATA%` |
| One content block, `stop_reason: max_tokens` | `max_tokens` too small for the reasoning. Not a server fault |
| Raw `<think>` tags inside `content` | `think: false`. The model thinks anyway; the server just stops parsing it out |
| Model describes an edit instead of making one | A model that declares tools and does not emit them. Step 5 |
| `autocompact is thrashing` | Window too small for the harness prompt plus the task. Step 9 |
| First token takes 10 s on a model that was fast a moment ago | `OLLAMA_MAX_LOADED_MODELS=1`; you switched models and paid a reload |
| Task `LastTaskResult` `0x800710E0` | A start was refused: it was already running. Harmless. Step 1 |
| `NotSpecified ... RemoteException` from OpenCode | ANSI escape on stderr, which PowerShell 5.1 reports as an error. Harmless |
| Node missing in `cmd` but present in PowerShell | The PATH junction was not added; the profile block is covering for it. Step 11 |
| A pasted command sits at a `>` prompt | The paste was truncated mid-line. Run `llm-verify.ps1` instead of retyping it |

## Paging this file over SSH

Git for Windows ships `less` at `C:\Program Files\Git\usr\bin\less.exe`, which is not
on PowerShell's PATH but runs when called directly. `-S` chops long lines instead of
wrapping them, which makes the structure readable but puts the off-screen part of a
line out of reach of a mouse selection -- so page without `-S` when the plan is to
copy something. `Get-Content <file> | Out-Host -Paging` is the native alternative:
forward-only, no search, nothing to install.

## See also

- [local-llm.md](local-llm.md) -- what each of these commands is doing, and why
- [llm-cluster.md](llm-cluster.md) -- which models a given machine can hold
- `recipes/ollama`, `recipes/pi`, `recipes/opencode`, `recipes/fnm` -- what set this up
