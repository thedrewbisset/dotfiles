# Overview

This project holds dotfile configuration and setup scripts used to bootstrap a dev environment; it is designed to be run on osx.

The installer sources various recipe files for setting up dotfiles, vim-plugins, and homebrews.

The dotfile recipe will establish symbolic links in`$HOME` to the dotfiles in `source`. This way configuration can easily be removed from the environment without impacting the source. It will also respect any existing dotfiles in `$HOME`, prompting you to either overwrite the file with the symbolic link or skip without overwriting. This makes it easy to use the source files a la carte although some awareness should be shown to interdependencies between say ``.vim` and `.vimrc`.

The vim-plugins recipe was designed to work with vim 8. If your system doesn't have this version installed, the homebrew recipe will take care of reconciling that.

# Setup

To setup, run:

```bash
$ bin/install
```
