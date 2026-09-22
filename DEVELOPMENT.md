# Development

## Running the tests

Tests use [bats-core](https://github.com/bats-core/bats-core).

```sh
# install (pick one)
brew install bats-core
sudo apt install bats

# run everything
bats test/
```

- `test/generate.bats` is hermetic: no tmux binary or network needed, it's
  driven entirely from the captured fixtures in `test/fixtures/`.
- `test/completion.bats` tests the real `completions/tmux` already in your
  working tree — it doesn't build anything itself. Run `./build.sh` first
  if that file doesn't exist yet. To test a specific version instead of
  whatever's currently promoted: `./build.sh --promote 3.4 && bats
  test/completion.bats`.
