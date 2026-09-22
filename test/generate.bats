#!/usr/bin/env bats
#
# Unit tests for generate.sh's parsing/rendering functions. Hermetic: uses
# the captured fixtures in test/fixtures/, never invokes a real tmux binary.

setup() {
    # shellcheck source=../generate.sh
    source "${BATS_TEST_DIRNAME}/../generate.sh"
    fixtures="${BATS_TEST_DIRNAME}/fixtures"
}

# ---- _tmux_gen_parse_usage --------------------------------------------

@test "parse_usage: empty usage (kill-server) yields no options, no args" {
    local -A opts
    local -a args
    _tmux_gen_parse_usage opts args ""
    [ "${#opts[@]}" -eq 0 ]
    [ "${#args[@]}" -eq 0 ]
}

@test "parse_usage: grouped booleans + value-taking flags (attach-session)" {
    local -A opts
    local -a args
    _tmux_gen_parse_usage opts args \
        "[-dErx] [-c working-directory] [-f flags] [-t target-session]"
    [ "${opts[d]+set}" = set ]
    [ "${opts[E]+set}" = set ]
    [ "${opts[r]+set}" = set ]
    [ "${opts[x]+set}" = set ]
    [ "${opts[c]}" = "working-directory" ]
    [ "${opts[f]}" = "flags" ]
    [ "${opts[t]}" = "target-session" ]
    [ "${#args[@]}" -eq 0 ]
}

@test "parse_usage: adjacent bracket groups with no space between them" {
    local -A opts
    local -a args
    _tmux_gen_parse_usage opts args \
        "[-F format] [-f filter] [-O order][-t target-session]"
    [ "${opts[F]}" = "format" ]
    [ "${opts[f]}" = "filter" ]
    [ "${opts[O]}" = "order" ]
    [ "${opts[t]}" = "target-session" ]
}

@test "parse_usage: value-taking flag is the very first token (i starts at 0)" {
    # Regression: ((i++)) post-increment evaluates to the OLD value, so
    # when a value-taking flag is the first (and only) token, the old code
    # silently aborted under set -e without any error message.
    local -A opts
    local -a args
    _tmux_gen_parse_usage opts args "[-T prompt-type]"
    [ "${opts[T]}" = "prompt-type" ]
}

@test "parse_usage: new-style ellipsis nested-command args (tmux 3.7c bind-key)" {
    local -A opts
    local -a args
    _tmux_gen_parse_usage opts args \
        "[-nr] [-T key-table] [-N note] key [command [argument ...]]"
    [ "${args[*]}" = "key command argument ..." ]
}

@test "parse_usage: old-style nested-command args (tmux 3.4 bind-key)" {
    local -A opts
    local -a args
    _tmux_gen_parse_usage opts args \
        "[-nr] [-T key-table] [-N note] key [command [arguments]]"
    [ "${args[*]}" = "key command arguments" ]
}

@test "parse_usage: bare positional path (source-file)" {
    local -A opts
    local -a args
    _tmux_gen_parse_usage opts args "[-Fnqv] [-t target-pane] path ..."
    [ "${opts[t]}" = "target-pane" ]
    [ "${args[*]}" = "path ..." ]
}

# ---- _tmux_gen_strip_help_prefix --------------------------------------

@test "strip_help_prefix: tmux 3.7c clean -h output" {
    local raw
    raw=$(cat "$fixtures/tmux-3.7c/-h.txt")
    result=$(_tmux_gen_strip_help_prefix "$raw")
    [[ $result == "[-2CDhlNuVv]"* ]]
}

@test "strip_help_prefix: tmux 3.4 error-prefixed -h output" {
    local raw
    raw=$(cat "$fixtures/tmux-3.4/-h.txt")
    result=$(_tmux_gen_strip_help_prefix "$raw")
    [[ $result == "[-2CDlNuVv]"* ]]
    [[ $result != *"unknown option"* ]]
}

# ---- _tmux_gen_parse_commands (full fixture) ---------------------------

@test "parse_commands (3.7c fixture): alias resolves to canonical name" {
    local -A canonical cmd_options cmd_args
    _tmux_gen_parse_commands canonical cmd_options cmd_args \
        <"$fixtures/tmux-3.7c/list-commands.txt"
    [ "${canonical[attach]}" = "attach-session" ]
    [ "${canonical[attach-session]}" = "attach-session" ]
}

@test "parse_commands (3.7c fixture): flag value-types land correctly" {
    local -A canonical cmd_options cmd_args
    _tmux_gen_parse_commands canonical cmd_options cmd_args \
        <"$fixtures/tmux-3.7c/list-commands.txt"
    [ "${cmd_options[attach-session:t]}" = "target-session" ]
    [ "${cmd_options[send-keys:t]}" = "target-pane" ]
    [ "${cmd_options[kill-session:t]}" = "target-session" ]
    # kill-session has -a/-C/-g booleans the original hand-written script
    # never covered (it lumped kill-session in with has-session's -t-only
    # arm) — pin that the generator gets this right.
    [ "${cmd_options[kill-session:a]+set}" = set ]
    [ "${cmd_options[kill-session:C]+set}" = set ]
    [ "${cmd_options[kill-session:g]+set}" = set ]
}

@test "parse_commands (3.7c fixture): no garbage keys from alias-less commands" {
    local -A canonical cmd_options cmd_args
    _tmux_gen_parse_commands canonical cmd_options cmd_args \
        <"$fixtures/tmux-3.7c/list-commands.txt"
    local bad=0 k
    for k in "${!canonical[@]}"; do
        [[ $k == "["* ]] && bad=1
    done
    [ "$bad" -eq 0 ]
}

@test "parse_commands: bind-key args differ between 3.4 and 3.7c fixtures" {
    local -A canonical37 cmd_options37 cmd_args37
    _tmux_gen_parse_commands canonical37 cmd_options37 cmd_args37 \
        <"$fixtures/tmux-3.7c/list-commands.txt"
    local -A canonical34 cmd_options34 cmd_args34
    _tmux_gen_parse_commands canonical34 cmd_options34 cmd_args34 \
        <"$fixtures/tmux-3.4/list-commands.txt"

    [ "${cmd_args37[bind-key]}" = "key command argument ..." ]
    [ "${cmd_args34[bind-key]}" = "key command arguments" ]
}

# ---- _tmux_gen_completer_call_for_type ---------------------------------

@test "completer_call_for_type: target-* types map to the right completer" {
    [[ $(_tmux_gen_completer_call_for_type target-session) == *_tmux_complete_session* ]]
    [[ $(_tmux_gen_completer_call_for_type target-pane) == *_tmux_complete_pane* ]]
    [[ $(_tmux_gen_completer_call_for_type src-pane) == *_tmux_complete_pane* ]]
    [[ $(_tmux_gen_completer_call_for_type dst-pane) == *_tmux_complete_pane* ]]
    [[ $(_tmux_gen_completer_call_for_type target-window) == *_tmux_complete_window* ]]
    [[ $(_tmux_gen_completer_call_for_type target-client) == *_tmux_complete_client* ]]
}

@test "completer_call_for_type: socket-path is not shadowed by the *-path wildcard" {
    # Regression: *-path (generic file/path arm) also matches the literal
    # string "socket-path" in a bash case statement; the specific arm has
    # to be checked first.
    result=$(_tmux_gen_completer_call_for_type socket-path)
    [[ $result == *_tmux_complete_socket_path* ]]
    [[ $result != *_filedir* ]]
}

@test "completer_call_for_type: generic *-directory / *-file wildcards" {
    [[ $(_tmux_gen_completer_call_for_type start-directory) == "_filedir -d" ]]
    [[ $(_tmux_gen_completer_call_for_type working-directory) == "_filedir -d" ]]
    [[ $(_tmux_gen_completer_call_for_type path) == "_filedir" ]]
}

@test "completer_call_for_type: free-text types (new names) have no completer" {
    [ -z "$(_tmux_gen_completer_call_for_type window-name)" ]
    [ -z "$(_tmux_gen_completer_call_for_type session-name)" ]
    [ -z "$(_tmux_gen_completer_call_for_type style)" ]
}

# ---- _tmux_gen_render ---------------------------------------------------

@test "render: kill-server gets a no-op arm" {
    local -A canonical cmd_options cmd_args
    _tmux_gen_parse_commands canonical cmd_options cmd_args \
        <"$fixtures/tmux-3.7c/list-commands.txt"
    result=$(_tmux_gen_render canonical cmd_options cmd_args)
    [[ $result == *$'kill-server)\n            ;;'* ]]
}

@test "render: canonical name comes first in the pattern head, not alphabetical" {
    # Regression: sorting all member words purely alphabetically put
    # "attach" before "attach-session" (needless diff noise vs. the
    # original file's "attach-session|attach" convention).
    local -A canonical cmd_options cmd_args
    _tmux_gen_parse_commands canonical cmd_options cmd_args \
        <"$fixtures/tmux-3.7c/list-commands.txt"
    result=$(_tmux_gen_render canonical cmd_options cmd_args)
    [[ $result == *"attach-session|attach)"* ]]
    [[ $result != *"attach|attach-session)"* ]]
}

@test "render: source-file gets both -t completion and a file-path fallback" {
    local -A canonical cmd_options cmd_args
    _tmux_gen_parse_commands canonical cmd_options cmd_args \
        <"$fixtures/tmux-3.7c/list-commands.txt"
    result=$(_tmux_gen_render canonical cmd_options cmd_args)
    [[ $result == *"source-file|source)"*"_tmux_complete_pane"*"_filedir"* ]]
}

@test "render output is valid bash inside a case statement" {
    local -A canonical cmd_options cmd_args
    _tmux_gen_parse_commands canonical cmd_options cmd_args \
        <"$fixtures/tmux-3.7c/list-commands.txt"
    result=$(_tmux_gen_render canonical cmd_options cmd_args)
    printf 'case $1 in\n%s\nesac\n' "$result" >"$BATS_TEST_TMPDIR/rendered.bash"
    run bash -n "$BATS_TEST_TMPDIR/rendered.bash"
    [ "$status" -eq 0 ]
}
