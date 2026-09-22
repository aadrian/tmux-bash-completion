# TODO

Remaining work from the tmux 3.4/3.7c rewrite. See `DEVELOPMENT.md` for
how the pieces fit together first.

## 1. CI workflow

Add `.github/workflows/ci.yml` + `.actrc` (for local validation via
[`act`](https://github.com/nektos/act) before relying on hosted runners).

Jobs:
- **lint**: shellcheck over `core.bash`, `generate.sh`, `build.sh`.
- **build** (matrix over `versions.txt`): compile that tmux version from
  source (cache the binary by version — see `build.sh`'s
  `_build_ensure_tmux_binary`), run `./build.sh <version>`, then
  `git diff --exit-code -- completions/` to catch a stale committed
  artifact. Upload the freshly built files as a workflow artifact
  regardless of diff result.
- **test**: install bats-core, run `bats test/`.

Nice-to-have once the above works: only *block* CI on a **structural**
diff (a new/removed command, or a new flag value-type `generate.sh`
doesn't have a completer for — check `_tmux_gen_completer_call_for_type`
in `generate.sh` returns non-empty for every new type introduced) vs. just
warn on a **cosmetic** diff (new flags on an already-handled command,
which the generator already handles correctly with zero manual work).
This needs a small diff-classifier, not built yet — start simple
(block on any diff) and refine later.

## 2. Automated diffability regression test

`PLAN-INITIAL.md` section 6 wanted a `diff -u`-based bats test asserting
the old-baseline output (`completions/tmux-3.4`) stays close in shape to
the pre-rewrite hand-written file, scoped to the commands both handle.
This was verified by hand several times during the rewrite (and caught
real issues — see commit history around `316f313`) but never turned into
a repeatable test. Add to `test/generate.bats` or a new
`test/diffability.bats`.

## 3. Wire shellcheck into something committed

Ran manually throughout development, everything it found got fixed, but
there's no committed lint step — a regression wouldn't be caught by
`bats test/` alone. Either a `test/lint.bats` that shells out to
`shellcheck`, or fold into CI's lint job (item 1) — CI is probably the
right home, skip the bats version if so.
