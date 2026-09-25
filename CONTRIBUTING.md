# Contributing

Issues and pull requests should describe the Chrome presentation problem before
the proposed implementation. Visible changes need a deterministic fixture in
addition to any manual screenshot.

## Branch model

- `bluff` is the default and only long-lived branch.
- Short-lived branches start from and return to `bluff`.
- CI publishes unsigned version tags and Releases from tested `bluff` commits.
  See [automatic releases](docs/releases.md); human-created tags may still be signed.

Preserve the repository's configured commit and tag signing behavior for human
work. Brokered `zemrip-ai` commits use the expected unsigned agent identity.
On that plane, pushes are limited to `agent/**`; workflow changes require an
operator-approved one-use ticket, and settings and secrets remain operator-owned.

## Local checks

`mise run verify` runs the complete gate. Set `UX_FOUNDATION_ROOT` and
`UX_STYLING_ROOT` to read-only dependency checkouts; by default the verifier
looks for sibling `UX-foundation.nvim` and `UX-styling.nvim` directories.
Foundation integration includes the drawer lifecycle and attached-UI mouse tests.

Run `bash scripts/test-release-tested.sh` to check release selection and retry
behavior against local fixtures.

Run from the repository root with Neovim 0.12.2:

```sh
nvim --headless --clean -l scripts/check-lua.lua .
UX_CHROME_TEST_FILE=tests/unit.lua nvim --headless -u tests/minimal_init.lua -l scripts/run-test.lua
UX_CHROME_TEST_FILE=tests/render.lua nvim --headless -u tests/minimal_init.lua -l scripts/run-test.lua
UX_CHROME_TEST_FILE=tests/smoke.lua nvim --headless -u tests/minimal_init.lua -l scripts/run-test.lua
UX_FOUNDATION_ROOT=../UX-foundation.nvim UX_CHROME_TEST_FILE=tests/foundation_integration.lua \
  nvim --headless -u tests/minimal_init.lua -l scripts/run-test.lua
UX_FOUNDATION_ROOT=../UX-foundation.nvim UX_STYLING_ROOT=../UX-styling.nvim \
  UX_CHROME_TEST_FILE=tests/styling_integration.lua \
  nvim --headless -u tests/minimal_init.lua -l scripts/run-test.lua
nvim --headless -u tests/minimal_init.lua -c "helptags doc" -c quit
git diff --check
git diff --exit-code -- doc/tags
```

Tests must isolate XDG config, data, state, and cache directories. They must not
load or mutate the user's live Neovim configuration. Do not copy third-party
implementation source or edit installed plugin files.

The Foundation schema-v1 contract is frozen. A shared contract change requires
a concrete failing fixture, compatibility analysis, Foundation tests, Styling
integration, and a migration decision.
