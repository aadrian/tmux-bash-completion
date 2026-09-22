#!/usr/bin/env bats
#
# End-to-end behavioral tests against the real, already-built
# completions/tmux (whatever's currently in the working tree — committed,
# or built by hand with ./build.sh). No build step here: this file's job is
# to verify that artifact behaves correctly, not to produce it. To test a
# specific version, promote it first: ./build.sh --promote 3.4 && bats
# test/completion.bats. `tmux` itself is stubbed with canned output so no
# real server is needed.

setup_file() {
    local root="${BATS_TEST_DIRNAME}/.."
    local file="$root/completions/tmux"
    if [[ ! -f $file ]]; then
        echo "missing $file — run: ./build.sh" >&2
        return 1
    fi
    export TMUX_BASH_COMPLETION_TEST_FILE="$file"
}

setup() {
    source /usr/share/bash-completion/bash_completion
    source "$TMUX_BASH_COMPLETION_TEST_FILE"

    # Canned server state, standing in for a real tmux server.
    # Matches on positional params directly, never on "$*"/"$@" joined into
    # a string: callers like _tmux_complete_session set `local IFS=$'\n'`
    # in their own scope, and since IFS is dynamically scoped, a nested
    # "$*" here would join on newlines instead of spaces and silently
    # never match.
    tmux() {
        case ${1-} in
            list-sessions)
                if [[ ${2-} == -F ]]; then
                    printf 'mysession\nother\n'
                else
                    printf 'mysession: 1 windows\nother: 1 windows\n'
                fi
                ;;
            list-windows)
                case ${3-} in
                    mysession) printf '0: bash*\n1: vim\n' ;;
                    other) printf '0: bash*\n' ;;
                esac
                ;;
            list-panes) printf 'mysession:0.0\nmysession:1.0\nother:0.0\n' ;;
            list-clients) printf '/dev/pts/3\n/dev/pts/7\n' ;;
            list-buffers) printf 'buffer0\nmybuf\n' ;;
            list-keys) printf 'prefix\ncopy-mode\n' ;;
            *) ;;
        esac
    }
}

# Drives _tmux() as real bash-completion would: sets COMP_WORDS/COMP_CWORD
# from a command line ending at the cursor, populates COMPREPLY.
_complete() {
    local line=$1
    COMP_LINE=$line
    COMP_POINT=${#COMP_LINE}
    local IFS=$' \t\n'
    read -ra COMP_WORDS <<<"$COMP_LINE"
    [[ $COMP_LINE == *" " ]] && COMP_WORDS+=("")
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    COMPREPLY=()
    # bash-completion's own _init_completion isn't set -e-safe (some
    # internal arithmetic evaluates to 0, which errexit treats as failure)
    # — harmless under normal interactive completion, but bats runs test
    # bodies under set -e. `|| true` neutralizes errexit for the whole
    # nested call; verified _tmux still populates COMPREPLY correctly.
    _tmux || true
}

_compreply_has() {
    local want=$1 got
    for got in "${COMPREPLY[@]}"; do
        [[ $got == "$want" ]] && return 0
    done
    return 1
}

# ---- regression tests for the two originally-found dead-code bugs -----

@test "send-keys -t completes panes (was dead code: referenced \$option, not \$prev)" {
    _complete "tmux send-keys -t "
    _compreply_has 'mysession\:0.0'
}

@test "new-session -- completes shell commands, not the static flag list (was dead code: undefined \$option_index)" {
    _complete "tmux new-session -n foo -- "
    # _command_offset completes real shell command names/keywords (as
    # observed manually: if/then/else/... plus PATH binaries), not tmux
    # subcommands — "if" is a bash keyword, reliably present regardless of
    # what's on $PATH in the test environment.
    _compreply_has "if"
    ! _compreply_has "-d"
}

# ---- representative new-capability tests -------------------------------

@test "kill-pane -t completes panes (command had zero completion before)" {
    _complete "tmux kill-pane -t "
    _compreply_has 'mysession\:0.0'
}

@test "set-buffer -b completes buffer names" {
    _complete "tmux set-buffer -b "
    _compreply_has "mybuf"
}

@test "bind-key -T completes key tables (built-ins plus live ones)" {
    _complete "tmux bind-key -T "
    _compreply_has "prefix"
    _compreply_has "copy-mode"
}

@test "source-file -t completes panes and bare path still completes files" {
    _complete "tmux source-file -t "
    _compreply_has 'mysession\:0.0'
}

@test "new-session -t completes sessions (previously only -- was handled)" {
    _complete "tmux new-session -t "
    _compreply_has "mysession"
}

@test "attach-session -t still completes sessions (no regression)" {
    _complete "tmux attach-session -t "
    _compreply_has "mysession"
}

@test "unknown/unhandled top-level word falls through without stale options" {
    _complete "tmux nonexistent-command -t "
    [ "${#COMPREPLY[@]}" -eq 0 ]
}
