# UX-chrome.nvim

UX Chrome is the original editor-chrome component for the UX Neovim ecosystem.
It renders buffer tabs and native tab pages, statusline, path breadcrumbs,
statuscolumn and folds, split/window treatment, and a lightweight scrollbar.
Its deterministic renderers perform no Git, GitHub, network, LSP, or other
domain I/O.

Chrome registers directly with UX Foundation schema version 1. UX Foundation is
required; UX Styling is an optional editor for the registered properties and is
never required at runtime.

## Requirements

- Neovim 0.12.2; older and newer compatibility is not currently claimed
- [UX-foundation.nvim](https://github.com/777lotto/UX-foundation.nvim) at the
  schema-v1 contract
- a font containing the configured separator glyphs, or ASCII replacements

## Installation

The production/default branch is `bet`; `bluff` is persistent integration.

With lazy.nvim:

```lua
{
  "777lotto/UX-foundation.nvim",
  branch = "bet",
  lazy = false,
},
{
  "777lotto/UX-chrome.nvim",
  branch = "bet",
  dependencies = { "777lotto/UX-foundation.nvim" },
  opts = {},
}
```

Installing the plugin does not authorize migration of an existing live
configuration. See [Ownership and migration](#ownership-and-migration) before
running it alongside Bufferline, Lualine, or custom native option expressions.

## Setup

The default ownership policy is `auto` for every surface:

```lua
require("ux_chrome").setup({
  ownership = {
    tabline = "auto",
    statusline = "auto",
    winbar = "auto",
    statuscolumn = "auto",
    windows = "auto",
    scrollbar = "auto",
  },
})
```

Surface IDs are `tabline`, `statusline`, `winbar`, `statuscolumn`, `windows`,
and `scrollbar`. Ownership values mean:

| Value | Behavior |
| --- | --- |
| `auto` | Acquire an available native surface while preserving an existing external expression. |
| `ux` | Explicitly select UX Chrome as the surface owner. |
| `external` | Register and preview Chrome's declarations without taking the physical surface. |

`takeover` is accepted as an alias for `ux`; `off` is accepted as an alias for
`external`. Profiles contain presentation values, not this behavioral ownership
choice.

Declared defaults preserve the Macchiato grammar used by the current editor:
slanted ``/`` buffer separators, `●` modification marker, powerline ``/``
status sections, mode-specific blue/green/mauve/red/peach accents, a
relative-number-aware gutter that honors native number settings, path
breadcrumbs, and restrained inactive-window colors. Every
structural value is typed in the schema-v1 manifest.

Calling `setup()` validates configuration, establishes the runtime, and
registers the manifest once. Repeated setup is supported. `reset()` returns
Chrome's editable presentation values to their declared defaults and refreshes
the active surfaces; it is not a promise to reconstruct arbitrary pre-Chrome
external configuration. Use `teardown()` for exact restoration of the physical
state captured when Chrome acquired its surfaces.

## Ownership and migration

During M3, Bufferline and Lualine remain the active owners in the current
configuration. An isolated coexistence setup uses:

```lua
require("ux_chrome").setup({
  ownership = {
    tabline = "external",
    statusline = "external",
    winbar = "auto",
    statuscolumn = "auto",
    windows = "auto",
    scrollbar = "auto",
  },
})
```

Do not add this migration to the live `nvim-config` during M3. Chrome uses only
`UXChrome*` highlight groups and one `ux_chrome` adapter with component-scoped
structural keys, so its
manifest can coexist with the M2 `ux.chrome.bufferline` and
`ux.chrome.lualine` compatibility registrations without duplicate Foundation
ownership.

The later M4 switch must disable the third-party implementation and its Styling
adapter before selecting `ux` ownership. The exact forward and rollback
sequence is in [docs/ownership-switch.md](docs/ownership-switch.md).

## Commands

| Command | Purpose |
| --- | --- |
| `:UXChromeEnable[!] [surface]` | Enable all surfaces or one surface; bang requests explicit UX ownership. |
| `:UXChromeDisable [surface]` | Disable all surfaces or one surface. |
| `:UXChromeToggle[!] [surface]` | Toggle all surfaces or one surface; bang requests explicit UX ownership when enabling. |
| `:UXChromeRefresh` | Atomically reconcile and redraw owned surfaces. |
| `:UXChromeReset` | Reset Chrome presentation values to declared defaults. |
| `:UXChromeDebug` | Show a defensive runtime/ownership snapshot. |
| `:UXChromeHealth` | Run the UX Chrome health checks. |
| `:UXChromeBufferNext` / `:UXChromeBufferPrev` | Select the next or previous displayed buffer. |
| `:UXChromeBufferFirst` / `:UXChromeBufferLast` | Select the first or last displayed buffer. |
| `:UXChromeBufferClose` | Close the current displayed buffer through the safe buffer action. |
| `:UXChromeBufferMoveLeft` / `:UXChromeBufferMoveRight` | Move the current buffer in Chrome's presentation order. |

Buffer commands do not create default mappings. Configuration owns keybinding
policy.

## Lua API

```lua
local chrome = require("ux_chrome")

chrome.setup(opts)
chrome.refresh()
chrome.reset()
chrome.teardown()
chrome.enable(surface?, force?)
chrome.disable(surface?)
chrome.toggle(surface?, force?)
chrome.state()
chrome.debug()
chrome.manifest()
chrome.fixtures()

chrome.tabline()
chrome.statusline()
chrome.winbar()
chrome.statuscolumn()
chrome.foldtext()

chrome.select_buffer(which)
chrome.move_buffer(delta)
chrome.close_buffer()
chrome.health()
```

The first group manages lifecycle and returns defensive state where applicable.
`manifest()` and `fixtures()` return callback-free defensive data. The rendering
entry points are installed into native option expressions; they read bounded
current Neovim state and remain free of blocking work and external I/O.

`refresh()` atomically reconciles physical ownership and redraws active surfaces.
`enable()`, `disable()`, and `toggle()` accept an optional surface ID; omitting it
applies to all configured surfaces. Passing `true` as the optional `force`
argument selects explicit `ux` ownership when enabling. The buffer actions back
the documented commands, and `health()` returns the defensive health report.
`teardown()` removes Chrome
lifecycle hooks, closes scrollbar resources, unregisters from Foundation, and
restores every acquired global and window-local option exactly.

## Components and fixtures

The manifest's stable plugin ID is `ux.chrome`. Components cover buffer tabs,
statusline, winbar, gutter/folds, window treatment, and scrollbar presentation.
Every highlight group begins with `UXChrome`; Chrome does not claim
`BufferLine*` or `lualine_*` groups.

Fixtures are callback-free schema-v1 data. Wide, medium, and narrow cases cover
active, visible, inactive, selected, modified, overflow, native tabs, all modes,
breadcrumbs, line/fold states, and scrollbar geometry. See
[docs/fixtures.md](docs/fixtures.md).

## Health and debugging

Run `:checkhealth ux_chrome` or `:UXChromeHealth` to inspect Neovim and Foundation
availability, schema version, registration, surface ownership, and restoration
capability. `:UXChromeDebug` and `require("ux_chrome").debug()` expose a
defensive snapshot without returning executable callbacks.

## Development

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

CI pins Neovim 0.12.2 on Linux and macOS, the promoted Foundation schema-v1
commit, and the production Styling integration commit. These gates are required
before release; this Unreleased work does not itself claim they have passed.

Run `:help ux-chrome` for the in-editor reference.

## License

UX Chrome is available under the [MIT License](LICENSE).
