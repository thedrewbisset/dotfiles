# tmux cheat sheet

Day-to-day reference for the tmux setup in `source/.tmux.conf`. The design rationale
lives in the README under *tmux session persistence*; this page is what to press and
what to run.

The prefix is `C-a`. Every `prefix` below means `Ctrl-a`, released before the next key.

## Session persistence

| Action | Keys / command |
|---|---|
| Save all sessions now | `prefix` `Ctrl-s` |
| Restore from the last save | `prefix` `Ctrl-r` |
| Where saves live | `~/.local/share/tmux/resurrect/` (`last` symlinks to the newest) |
| Automatic saves | every 15 minutes, and whenever a client detaches or dies |

A save captures the **whole server**: every session, every window, every pane. It does
not matter which pane you are in when you press it, and there is nothing to repeat per
window or per session. Restore is the same: everything in the last save comes back at
once.

What a restore brings back:

- sessions, with their names
- windows and pane layouts
- each pane's working directory
- each pane's visible text (`@resurrect-capture-pane-contents` is on)

What it does not: running processes. Each pane returns as a fresh shell in the saved
directory. resurrect relaunches only its default program list (`vi vim view nvim emacs
man less more tail top htop irssi weechat mutt`); dev servers, ssh sessions, REPLs and
agent sessions must be started again by hand.

## Runbook: recover after a reboot or a killed server

1. Start a plain server: `tmux`. Do **not** start with `tmuxinator`: resurrect restores
   into any session whose name already exists, adding the saved windows and panes next
   to the live ones, so a tmuxinator-built session comes out doubled.
2. Press `prefix` `Ctrl-r`. Every saved session is rebuilt; the terminal you are in stays
   attached to one of them.
3. List what came back: `tmux ls`. The session name is the part before the first colon.
4. Attach the rest, one per terminal window: `tmux attach -t <name>`. From inside tmux,
   `prefix` `s` opens the same list as a picker and switches the current client.

If you are about to kill the server on purpose, press `prefix` `Ctrl-s` first so the
save is current rather than up to 15 minutes old.

## Runbook: "no server running on /private/tmp/tmux-501/default"

If tmux commands say this while sessions are visibly still open, the server is alive
but its socket file is gone (macOS periodically cleans `/private/tmp`). Ask the server
to recreate it:

```bash
pkill -USR1 tmux
tmux ls
```

Nothing is lost: the sessions and their processes were never touched.

## Runbook: load config changes into the running server

The server reads `~/.tmux.conf` only when it starts. After editing the config, or after
`bin/install.sh tmux` adds plugins, reload it into the live server: `prefix` `r`, or
`tmux source-file ~/.tmux.conf` from any shell. A server that predates a plugin install
does not have that plugin until this is done.

## Sessions

| Action | Keys / command |
|---|---|
| List sessions | `tmux ls` |
| Attach to a session | `tmux attach -t <name>` |
| Switch session (picker) | `prefix` `s` |
| Next / previous session | `prefix` `)` / `prefix` `(` |
| Rename current session | `prefix` `$` |
| Detach | `prefix` `d` |
| Start a tmuxinator project | `tmuxinator start <project>` (projects in `source/.tmuxinator/`) |

## Windows

| Action | Keys |
|---|---|
| New window | `prefix` `c` |
| New window with 10 000-line history | `prefix` `C` |
| Next / previous window | `prefix` `n` / `prefix` `p` |
| Last window | `prefix` `Ctrl-a` |
| Jump to window N | `prefix` `0`–`9` |
| Rename window | `prefix` `,` |
| Move window left / right | `prefix` `<` / `prefix` `>` |
| Kill window | `prefix` `&` |

## Panes

| Action | Keys |
|---|---|
| Split side by side | `prefix` `\|` |
| Split top and bottom | `prefix` `-` |
| Move between panes | `Ctrl-h` `Ctrl-j` `Ctrl-k` `Ctrl-l` (no prefix; also `prefix` `h` `j` `k` `l`) |
| Back to the last pane | `Ctrl-\` (no prefix) |
| Resize by 5 | `prefix` `H` `J` `K` `L` (repeatable) |
| Zoom / unzoom pane | `prefix` `z`, or `prefix` `Up` / `prefix` `Down` |
| Swap pane up / down | `prefix` `{` / `prefix` `}` |
| Cycle layouts | `prefix` `Space` |
| Kill pane | `prefix` `x` |

The no-prefix navigation keys are vim-aware: inside vim, nvim or fzf they pass through
to the program, which handles its own splits (vim-tmux-navigator).

## Copy mode (vi keys)

| Action | Keys |
|---|---|
| Enter copy mode | `prefix` `[` |
| Scroll back a page | `prefix` `PageUp` |
| Start selection | `v` |
| Toggle rectangle selection | `V` |
| Copy to the macOS clipboard and exit | `y` |
| Paste | `prefix` `]` |
| Move between panes while in copy mode | `Ctrl-h` `Ctrl-j` `Ctrl-k` `Ctrl-l` |

## Plugins

| Action | Keys |
|---|---|
| Install plugins declared in `.tmux.conf` | `prefix` `I` (or `bin/install.sh tmux`) |
| Update plugins | `prefix` `U` |
| Remove plugins no longer declared | `prefix` `Alt-u` |
| Send a literal `Ctrl-a` to the program | `prefix` `a` |
| List every binding | `prefix` `?` |
