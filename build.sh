#!/usr/bin/env bash
#
# build.sh — produce completions/tmux-<version> (and, for the newest
# version in versions.txt, the unversioned completions/tmux) from
# core.bash plus generate.sh's output, for every version listed in
# versions.txt.
#
# build/ is scratch space only (downloaded tmux sources, compiled tmux
# binaries, generate.sh's intermediate output) — reproducible from source,
# safe to delete, never committed. Only completions/tmux-* is committed.
#
# Usage:
#   build.sh                        # rebuild every version, promote the newest
#   build.sh <version>...            # rebuild just the given version(s)
#   build.sh --promote <version>     # also (re)build <version> and make it
#                                     # the unversioned completions/tmux,
#                                     # instead of the newest
#   build.sh --promote <version> <version>...   # both together

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_dir="$root/build"
tmux_src_dir="$build_dir/tmux-src"
tmux_bin_dir="$build_dir/tmux-bin"
generated_dir="$build_dir/generated"

# Read versions.txt into $1 (nameref, indexed array), skipping blank lines
# and #-comments.
_build_read_versions() {
    local -n __out=$1
    __out=()
    local line
    while IFS= read -r line; do
        line=${line%%#*}
        line=${line//[[:space:]]/}
        [[ -n $line ]] && __out+=("$line")
    done <"$root/versions.txt"
}

# Ensure build/tmux-bin/<version>/bin/tmux exists and reports the right
# version, building it from the official release tarball if not.
_build_ensure_tmux_binary() {
    local version=$1
    local prefix="$tmux_bin_dir/$version"
    local bin="$prefix/bin/tmux"

    if [[ -x $bin ]]; then
        local have
        have=$("$bin" -V 2>/dev/null || true)
        [[ $have == "tmux $version" ]] && { printf '%s' "$bin"; return 0; }
        echo "build.sh: $bin reports '$have', not 'tmux $version' — rebuilding" >&2
        rm -rf "$prefix"
    fi

    echo "build.sh: building tmux $version from source (this takes a minute)..." >&2
    local src="$tmux_src_dir/$version"
    mkdir -p "$src"
    if [[ ! -f "$src/tmux-$version.tar.gz" ]]; then
        curl -fSsL -o "$src/tmux-$version.tar.gz" \
            "https://github.com/tmux/tmux/releases/download/$version/tmux-$version.tar.gz"
    fi
    if [[ ! -d "$src/tmux-$version" ]]; then
        tar xzf "$src/tmux-$version.tar.gz" -C "$src"
    fi

    (
        cd "$src/tmux-$version"
        ./configure --prefix="$prefix" >configure.log 2>&1
        make -j"$(nproc 2>/dev/null || echo 2)" >build.log 2>&1
        make install >install.log 2>&1
    )

    printf '%s' "$bin"
}

# Splice core.bash + the generated dispatcher for one version into
# completions/tmux-<version>, adding a single header line noting the
# version (no other change to core.bash's header — see DEVELOPMENT.md on
# why: this keeps the file diffable against the original hand-written
# completions/tmux). The generated dispatcher goes in right before
# _tmux_dispatch_new_session (which calls it) — not appended after
# core.bash's own "# END tmux completion" footer, so the file still reads
# top-to-bottom sensibly instead of having "END" in the middle.
_build_assemble() {
    local version=$1
    local case_file="$generated_dir/tmux-$version.case.bash"
    local out="$root/completions/tmux-$version"
    local core="$root/core.bash"

    local anchor='# new-session is the one command that needs hand-written completion beyond'
    local split_line
    split_line=$(grep -n -F "$anchor" "$core" | head -1 | cut -d: -f1)
    if [[ -z $split_line ]]; then
        echo "build.sh: can't find splice anchor in core.bash" >&2
        return 1
    fi

    {
        sed -n '1p' "$core"
        printf '# Built for tmux %s.\n' "$version"
        sed -n "2,$((split_line - 1))p" "$core"
        cat "$case_file"
        echo
        sed -n "${split_line},\$p" "$core"
    } >"$out"
    echo "build.sh: wrote completions/tmux-$version" >&2
}

_build_one() {
    local version=$1
    local bin
    bin=$(_build_ensure_tmux_binary "$version")
    mkdir -p "$generated_dir"
    "$root/generate.sh" "$bin" "$generated_dir"
    _build_assemble "$version"
}

_build_main() {
    local promote=""
    local -a requested=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --promote)
                promote=$2
                shift 2
                ;;
            --promote=*)
                promote=${1#--promote=}
                shift
                ;;
            *)
                requested+=("$1")
                shift
                ;;
        esac
    done

    local -a all_versions
    _build_read_versions all_versions

    local -a versions
    if [[ ${#requested[@]} -gt 0 ]]; then
        versions=("${requested[@]}")
    else
        versions=("${all_versions[@]}")
    fi

    # Default: promote the newest version to the unversioned completions/tmux
    # (the file bash-completion autoloads), same as always. --promote picks
    # a different one instead — e.g. `./build.sh --promote 3.4` to diff the
    # old-baseline output against the original hand-written file before
    # jumping straight to the current tmux's output.
    [[ -z $promote ]] && promote=${all_versions[-1]}

    # Whatever we're promoting has to actually get (re)built this run.
    if [[ " ${versions[*]} " != *" $promote "* ]]; then
        versions+=("$promote")
    fi

    local v
    for v in "${versions[@]}"; do
        _build_one "$v"
    done

    cp "$root/completions/tmux-$promote" "$root/completions/tmux"
    echo "build.sh: wrote completions/tmux (= tmux-$promote)" >&2
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    _build_main "$@"
fi
