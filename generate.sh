#!/usr/bin/env bash
#
# generate.sh — Stage A: parse a tmux binary's own usage output into
# intermediate, data-only bash (plain associative arrays, no logic), for one
# specific tmux binary/version. build.sh runs this per entry in versions.txt
# and feeds the result into Stage B (rendering) to produce completions/tmux-*.
#
# Never touches anything that reflects live tmux server state (no
# list-sessions/list-clients/list-windows/...) — only `tmux -h` and
# `tmux list-commands`, both of which just describe the binary itself.
#
# The usage-string parsing approach (the bracket-stripping in
# _tmux_gen_parse_usage) is adapted from bash-completion's
# completions-core/tmux.bash (_comp_cmd_tmux__parse_usage), (c) its authors,
# licensed GPL-2.0-or-later OR ISC. See DEVELOPMENT.md.
#
# Usage: generate.sh <tmux-binary> <output-dir>
# Writes <output-dir>/tmux-<version>.bash

set -euo pipefail
shopt -s extglob

# Parse one usage string (the part after the command/alias, or after
# "usage: tmux " for the top-level one) into:
#   $1 (nameref, assoc array)  flag char -> value-type ("" = boolean flag)
#   $2 (nameref, indexed array) positional arg-type tokens, in order, with
#      surrounding brackets stripped (an unresolvable arg list is left empty)
#   $3 the usage string itself
_tmux_gen_parse_usage() {
    local -n __options=$1
    local -n __args=$2
    local usage=$3

    __options=()
    __args=()

    # tmux's usage strings sometimes butt two bracket groups together with
    # no space, e.g. "[-O order][-t target-session]" — split them so the
    # word-based tokenizer below sees two separate tokens.
    usage=${usage//][/] [}

    local -a words
    read -ra words <<<"$usage"

    local i j w
    for ((i = 0; i < ${#words[@]}; i++)); do
        w=${words[i]}
        case $w in
            "[-"*"]")
                # One or more boolean options: [-abc] or [-a|-b|-c]
                for ((j = 2; j < ${#w} - 1; j++)); do
                    local c=${w:j:1}
                    [[ $c == - || $c == '|' ]] && continue
                    __options[$c]=""
                done
                ;;
            "[-"*)
                # One option that takes a value, e.g. [-t target-session]
                if [[ ${words[i + 1]:-} != *"]" ]]; then
                    echo "generate.sh: can't parse option '${words[*]:i:2}' in '$usage'" >&2
                    return 1
                fi
                local flag=${w#"["}
                flag=${flag#-}
                local value=${words[i + 1]}
                value=${value%"]"}
                __options[$flag]=$value
                # NOT `((i++))`: post-increment evaluates to the OLD value,
                # so when i is 0 the arithmetic result is 0 -> nonzero exit
                # status -> aborts this function under `set -e`.
                (( i += 1 ))
                ;;
            -*)
                echo "generate.sh: can't parse option '$w' in '$usage'" >&2
                return 1
                ;;
            *)
                # Start of positional args: keep the rest, stripping the
                # brackets each token happens to carry (nesting collapses
                # cleanly since extglob strips 1-or-more leading/trailing
                # '[' / ']' per token).
                local -a rest=("${words[@]:i}")
                local tok stripped
                for tok in "${rest[@]}"; do
                    stripped=${tok##+(\[)}
                    stripped=${stripped%%+(\])}
                    __args+=("$stripped")
                done
                break
                ;;
        esac
    done
}

# Strip the boilerplate around `tmux -h`'s output, leaving just the flags
# part (what _tmux_gen_parse_usage expects). Handles both:
#  - pre-3.6: "tmux: unknown option -- h\nusage: tmux [-2CD...] ...\n"
#  - 3.6+:    "usage: tmux [-2CDh...] ...\n"
_tmux_gen_strip_help_prefix() {
    local raw=$1
    raw=${raw#$'tmux: unknown option -- h\n'}
    raw=${raw#"usage: tmux "}
    printf '%s' "$raw"
}

# Parse `tmux list-commands -F '<name>~<alias>~<usage>'` lines from stdin.
# Uses a literal '~', not a tab and not a control byte:
#  - tab is "IFS whitespace" to bash's `read`, which collapses consecutive
#    delimiters and silently swallows empty fields (every alias-less
#    command's usage text would shift into the alias field).
#  - a raw control byte (e.g. \x1f) gets vis-encoded by tmux's own format
#    engine into a literal 4-character "\037" before it ever reaches us, so
#    it doesn't survive as a single delimiter character either.
# '~' is plain, printable, never collapsed, and never appears in real usage
# text (which is only letters/digits/hyphens/spaces/brackets/pipes).
# into:
#   $1 (nameref, assoc array) command name or alias -> canonical command name
#   $2 (nameref, assoc array) "<canonical-name>:<flag>" -> value-type
#   $3 (nameref, assoc array) canonical name -> space-joined positional
#      arg-type tokens (verbatim, including a trailing "..." marker)
#
# Skips (with a stderr warning) any command whose usage line fails to parse,
# so one irregular command (e.g. display-menu's repeating positional args)
# doesn't abort the whole run.
_tmux_gen_parse_commands() {
    local -n __canonical=$1
    local -n __cmd_options=$2
    local -n __cmd_args=$3

    __canonical=()
    __cmd_options=()
    __cmd_args=()

    local name alias usage
    while IFS='~' read -r name alias usage; do
        [[ -z $name ]] && continue

        __canonical[$name]=$name
        [[ -n $alias ]] && __canonical[$alias]=$name

        local -A opts=()
        local -a args=()
        if ! _tmux_gen_parse_usage opts args "$usage"; then
            echo "generate.sh: skipping '$name': usage didn't parse" >&2
            continue
        fi

        local flag
        for flag in "${!opts[@]}"; do
            __cmd_options["$name:$flag"]=${opts[$flag]}
        done

        [[ ${#args[@]} -gt 0 ]] && __cmd_args[$name]="${args[*]}"
    done
}

# Emit the parsed data as plain, re-sourceable bash (declare -p output),
# data only, no functions/logic. Takes variable *names* (not namerefs) and
# relies on bash's dynamic scoping to see the caller's locals directly.
_tmux_gen_emit() {
    local version=$1 global_options_var=$2 canonical_var=$3 cmd_options_var=$4 cmd_args_var=$5

    printf '_tmux_gen_version=%q\n' "$version"
    declare -p "$global_options_var" | sed "s/^declare -A $global_options_var=/declare -gA _tmux_gen_global_options=/"
    declare -p "$canonical_var" | sed "s/^declare -A $canonical_var=/declare -gA _tmux_gen_command_canonical=/"
    declare -p "$cmd_options_var" | sed "s/^declare -A $cmd_options_var=/declare -gA _tmux_gen_command_options=/"
    declare -p "$cmd_args_var" | sed "s/^declare -A $cmd_args_var=/declare -gA _tmux_gen_command_args=/"
}

_tmux_gen_main() {
    local tmux_bin=$1
    local outdir=$2

    local version
    version=$("$tmux_bin" -V)
    version=${version#tmux }

    local help_raw
    help_raw=$("$tmux_bin" -h 2>&1) || true
    local help_flags
    help_flags=$(_tmux_gen_strip_help_prefix "$help_raw")

    local -A global_options
    local -a global_args
    _tmux_gen_parse_usage global_options global_args "$help_flags"

    local -A canonical cmd_options cmd_args
    _tmux_gen_parse_commands canonical cmd_options cmd_args < <(
        "$tmux_bin" list-commands -F '#{command_list_name}~#{command_list_alias}~#{command_list_usage}'
    )

    mkdir -p "$outdir"
    _tmux_gen_emit "$version" global_options canonical cmd_options cmd_args \
        >"$outdir/tmux-$version.bash"
    echo "generate.sh: wrote $outdir/tmux-$version.bash" >&2
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    if [[ $# -ne 2 ]]; then
        echo "usage: generate.sh <tmux-binary> <output-dir>" >&2
        exit 2
    fi
    _tmux_gen_main "$1" "$2"
fi
