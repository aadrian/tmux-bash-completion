#!/usr/bin/env bash

# Copy of https://github.com/Bash-it/bash-it/blob/master/completion/available/tmux.completion.bash
# and https://github.com/przepompownia/bash-it/blob/master/completion/available/tmux.completion.bash
# slightly refactored

# tmux completion
# See: http://www.debian-administration.org/articles/317 for how to write more.
# Usage: Put "source bash_completion_tmux.sh" into your .bashrc
# Based upon the example at http://paste-it.appspot.com/Pj4mLycDE

function _tmux_complete_client() {
    local IFS=$'\n'
    local cur="${1}" && shift
    mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "$(tmux "$@" list-clients -F '#{client_tty}' 2> /dev/null)" -- "${cur}")
    options=""
    return 0
}

function _tmux_complete_session() {
    local IFS=$'\n'
    local cur="${1}" && shift
    mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "$(tmux "$@" list-sessions -F '#{session_name}' 2> /dev/null)" -- "${cur}")
    options=""
    return 0
}

function _tmux_complete_window() {
    local IFS=$'\n'
    local cur="${1}" && shift
    local session_name="$(echo "${cur}" | sed 's/\\//g' | cut -d ':' -f 1)"
    local sessions

    sessions="$(tmux "$@" list-sessions 2> /dev/null | sed -re 's/([^:]+:).*$/\1/')"
    if [[ -n "${session_name}" ]]; then
        sessions="${sessions}
        $(tmux "$@" list-windows -t "${session_name}" 2> /dev/null | sed -re 's/^([^:]+):.*$/'"${session_name}"':\1/')"
    fi
    cur="$(echo "${cur}" | sed -e 's/:/\\\\:/')"
    sessions="$(echo "${sessions}" | sed -e 's/:/\\\\:/')"
    mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "${sessions}" -- "${cur}")
    options=""
    return 0
}

function _tmux_complete_pane() {
    local IFS=$'\n'
    local cur="${1}" && shift
    local panes
    panes="$(tmux "$@" list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' 2> /dev/null)"
    cur="$(echo "${cur}" | sed -e 's/:/\\\\:/')"
    panes="$(echo "${panes}" | sed -e 's/:/\\\\:/')"
    mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "${panes}" -- "${cur}")
    options=""
    return 0
}

function _tmux_complete_buffer_name() {
    local IFS=$'\n'
    local cur="${1}" && shift
    mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "$(tmux "$@" list-buffers -F '#{buffer_name}' 2> /dev/null)" -- "${cur}")
    options=""
    return 0
}

function _tmux_complete_key_table() {
    local IFS=$'\n'
    local cur="${1}" && shift
    # tmux has no "list key tables" command; offer the built-in tables plus
    # whatever tables currently have bindings (covers custom -T tables from
    # the user's config).
    local tables
    tables="$(
        {
            printf '%s\n' prefix root copy-mode copy-mode-vi
            tmux "$@" list-keys -F '#{key_table}' 2> /dev/null
        } | sort -u
    )"
    mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "${tables}" -- "${cur}")
    options=""
    return 0
}

function _tmux_complete_socket_name() {
    local IFS=$'\n'
    local cur="${1}" && shift
    mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "$(find "${TMUX_TMPDIR:-/tmp}/tmux-$UID" -type s -printf '%P\n')" -- "${cur}")
    options=""
    return 0
}
function _tmux_complete_socket_path() {
    local IFS=$'\n'
    local cur="${1}" && shift
    mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "$(find "${TMUX_TMPDIR:-/tmp}/tmux-$UID" -type s -printf '%p\n')" -- "${cur}")
    options=""
    return 0
}

__tmux_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref cur prev words cword
}

# new-session is the one command that needs hand-written completion beyond
# flag values: its trailing [shell-command [argument ...]] means that once
# `--` appears, everything after it is a nested command line, not a tmux
# flag. _tmux_dispatch_command (generated) doesn't attempt general
# positional/nested-command completion, so this wraps it.
_tmux_dispatch_new_session() {
    local i dashdash_index=-1
    for ((i = index; i < cword; i++)); do
        if [[ ${words[i]} == -- ]]; then
            dashdash_index=i
            break
        fi
    done
    if [[ $dashdash_index -ge 0 ]]; then
        _command_offset $((dashdash_index + 1))
    else
        _tmux_dispatch_command new-session
    fi
}

_tmux() {
    local cur prev words cword;
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion
    else
        __tmux_init_completion
    fi

    local index=1
    # Check tmux options that will change completion for:
    # - available sessions
    # - available windows
    # - ...
    local argv=( "${words[@]:1}" )
    local OPTIND OPTARG OPTERR=0 flag tmux_args=()
    while getopts "L:S:" flag "${argv[@]}"; do
        case "$flag" in
            L) tmux_args+=(-L "$OPTARG") ;;
            S) tmux_args+=(-S "$OPTARG") ;;
            *) ;;
        esac
    done
    # Completed -- have a space after
    if [[ ${#words[@]} -gt $OPTIND ]]; then
        local tmux_argc=${#tmux_args[@]}
        (( index+=tmux_argc ))
        (( cword-=tmux_argc ))
    fi

    local options=""
    if [[ $cword -eq 1 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$(tmux start\; list-commands | cut -d' ' -f1)" -- "$cur")
        return 0
    else
        case ${words[index]} in
            -L) _tmux_complete_socket_name "${cur}" ;;
            -S) _tmux_complete_socket_path "${cur}" ;;
            new-session|new) _tmux_dispatch_new_session ;;
            *) _tmux_dispatch_command "${words[index]}" ;;
        esac # case ${cmd}
    fi # command specified

    if [[ -n "${options}" ]]; then
        mapfile -t -O "${#COMPREPLY[@]}" COMPREPLY < <(compgen -W "${options}" -- "${cur}")
    fi

    return 0
}
# http://linux.die.net/man/1/bash
complete -F _tmux tmux

# END tmux completion
