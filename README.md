TMUX bash completion based on [bash-it's tmux completion](https://github.com/Bash-it/bash-it/blob/master/completion/available/tmux.completion.bash)

# Available completions

* commands (all of them, with their actual flags — see DEVELOPMENT.md)
* files
* sessions
* windows
* panes
* clients
* buffers
* key tables

# Installation

## Manual install

You can simply download the completion file and source it as part of your shell startup.

```sh
$ curl -fSsL "https://raw.githubusercontent.com/aadrian/tmux-bash-completion/master/completions/tmux" > ~/.bash.tmux-bash-completion
$ echo 'source ~/.bash.tmux-bash-completion' >> ~/.bashrc
$ source ~/.bashrc # load it for your current session
```

## Automatic install (via the [`bash-completion`](https://github.com/scop/bash-completion) project)

This installation method __requires__ [`bash-completion`](https://github.com/scop/bash-completion) 1.2 or higher.

> **Limitation:** on `bash-completion` ≥ 2.17, this method may not take
> effect — see [Troubleshooting](#troubleshooting).

1. Follow the installation instructions for [`bash-completion`](https://github.com/scop/bash-completion)

2. Determine the correct spot to place this plugin.

<details><summary>From the <a href="https://github.com/scop/bash-completion#faq"><code>bash-completion FAQ</code></a></summary>

> **Q. Where should I install my own local completions?**
>
> A. Put them in the completions subdir of `$BASH_COMPLETION_USER_DIR` (defaults to `$XDG_DATA_HOME/bash-completion` or `~/.local/share/bash-completion` if `$XDG_DATA_HOME` is not set) to have them loaded automatically on demand when the respective command is being completed. See also the next question's answer for considerations for these files' names, they apply here as well. Alternatively, you can write them directly in `~/.bash_completion` which is loaded eagerly by our main script.

</details>

```sh
$ dir="${BASH_COMPLETION_DIR:-"${XDG_DATA_HOME:-"$HOME/.local/share"}/bash-completion"}/completions"
$ mkdir -p "$dir"
```

3. Download the file

```sh
$ curl -fSsL "https://raw.githubusercontent.com/aadrian/tmux-bash-completion/master/completions/tmux" > "${dir?error: dir not set: you must run the previous commands first}/tmux"
```

4. Reload your configuration files

```sh
$ source ~/.bashrc
```

# Troubleshooting

Check what's actually registered for `tmux`:

```sh
$ complete -p tmux
```

* `complete -F _tmux tmux`: this project's completion is active (old or
  current version). Working as expected.
* `complete -F _comp_cmd_tmux tmux`: this is the tmux completion bundled
  with the [`bash-completion` project](https://github.com/scop/bash-completion)
  itself, included there since its 2.17.0 release. It's taking over
  because its on-demand `completions/` loader never fires for a command
  that's already registered elsewhere. Fix: use
  [Manual install](#manual-install), which registers eagerly and
  overwrites it.
* Nothing printed: nothing is installed yet, or your shell hasn't reloaded
  its configuration since installing — re-run step 4 of whichever method
  you used.

# TODO

* check all cases for `complete -o default`
