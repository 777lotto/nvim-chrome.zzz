# Shared plugin panes

Chrome's pane API attaches presentation to existing plugin windows independently
of editor-wide surface ownership. Navigation lists, plaintext logs, and Markdown
documents share defaults without requiring a Bufferline or Lualine migration.
Plugins retain their buffers, layouts, content, actions, and scrolling behavior.

Foundation schema v1 remains unchanged. Chrome publishes its own structural
adapters and highlight groups through the existing registration contract.
Styling discovers these registrations directly from Foundation.

## Public API

```lua
local panes = require("ux_chrome.panes")

-- Optional early registration: expose settings before opening a window.
panes.register({
  id = "example.plugin.conversation",
  label = "Example conversation",
  role = "log",
})

panes.attach({
  id = "example.plugin.conversation",
  role = "log",
  content = "markdown",
  window = win,
  buffer = buf, -- optional; defaults to the window's current buffer
})

local state = panes.inspect(win)
panes.detach(win)
```

`require("ux_chrome").attach()` and `.detach()` are equivalent convenience
entry points. Neither initializes Chrome's editor-wide surfaces. Invalid
descriptors raise an error; successful attachment returns the inspection.
Repeated attachment to the same pane/window is idempotent.

IDs are permanent dotted lowercase identifiers. The same pane ID can have
multiple windows; its presentation overrides apply to all instances. Distinct
pane IDs can display the same buffer with different window preferences.
Role is immutable after registration. Supported roles are `navigation`, `log`,
`context`, and `input`. Supported content types are `list`, `plaintext`,
`markdown`, `diff`, and `code`; only Markdown requests additional rendering.

Content type belongs to the buffer. Replace the scratch buffer when changing
from Markdown to a diff or another content type. This gives parsers and
decoration providers their normal buffer teardown boundary and prevents stale
Markdown decorations. A window changing buffers releases its prior pane
attachment; the plugin attaches the replacement explicitly.

## Editable properties

| Scope | Foundation property ID | Values |
| --- | --- | --- |
| Shared role wrapping | `ux.chrome.panes/log/wrap/value` | boolean |
| Shared role selection | `ux.chrome.panes/navigation/cursorline/value` | boolean |
| Shared role gutter | `ux.chrome.panes/context/gutter/value` | `none`, `numbers`, `relative` |
| One pane wrapping | `ux.chrome.pane.example.plugin.conversation/presentation/wrap/value` | `inherit`, `on`, `off` |
| One pane selection | `ux.chrome.pane.example.plugin.conversation/presentation/cursorline/value` | `inherit`, `on`, `off` |
| One pane gutter | `ux.chrome.pane.example.plugin.conversation/presentation/gutter/value` | `inherit`, `none`, `numbers`, `relative` |

Every role exposes all three settings. Navigation defaults to unwrapped rows
with a cursor line. Log, context, and input default to wrapped prose without a
cursor line. Gutters default to hidden. Wrapping includes line breaking,
continuation indentation (`shift:2,min:20`), and zero horizontal scroll margin.
Shared `UXChromePaneNormal`, `UXChromePaneInactive`, and `UXChromePaneSelection`
groups initially link to native theme groups and are editable in Foundation.
Unrelated window highlight mappings are preserved.

Resolution is shared role defaults plus a pane's explicit override, with
Foundation's declared/saved/session precedence inside each scope. Foundation
reports the per-pane declaration as `inherit`; `panes.inspect(win).effective`
reports the final window values. Colors use ordinary Foundation highlight
inspection. Window and buffer IDs never appear in saved profiles.

Settings remain registered after the last window closes so edits apply on
reopen. Transactions preview live windows, restore failed applications, and
support undo/revert. New panes inherit the current role values. Registration
does not require opening Styling. Saved profiles apply when Foundation loads
them; distributions must enable `load_active` for automatic startup selection.

## Markdown and lifecycle

Markdown buffers use Neovim's Markdown Tree-sitter parser and, when available,
the public `render-markdown.render({buf, win, config})` API. Text, cursor, mode,
and viewport changes are coalesced over 16 ms before requesting another render.
Chrome disables the backend's debounce for attached Markdown buffers through
that public per-buffer config, preventing a final streamed update from being
dropped by a second scheduler. Missing renderer support falls back to
Tree-sitter; missing parsers leave readable text and an inspection reason.
Chrome registers a Markdown parser association for the declared plugin filetype,
preserves that filetype, and never repeats renderer `setup()` or
accesses its private mutable configuration. The backend retains ownership of
its decorations and window options; this initial API does not expose a
transactional Markdown enable toggle or renderer-specific layout settings.
Those require a backend contract with reliable getters and restoration.

Chrome owns only the enumerated pane window options. Detaching restores their
opening values if no later external edit replaced Chrome's last value. Closing
windows discards their handles. Switching buffers releases the old attachment.
`panes.teardown()` detaches all windows and unregisters the pane catalog;
`chrome.teardown()` includes this operation. Editor-wide Chrome treatment
yields an explicitly attached pane rather than overwriting it on refresh.

## Shared output layout

The [bottom drawer](drawer.md) builds on these presentation roles to provide a
standard output location, per-tab window lifecycle, source switching, retention,
and follow/filter controls. Existing plugin layouts continue to use `attach()`;
plugins that want the shared output location register a drawer provider.

## Adoption and roadmap

The first consumers are Agent Manager's navigation, conversation, activity,
approval, and input panes; GitPanel's navigation and context panes; and MCP
Buff's navigation and Markdown context panes. Each keeps its native fallback
when this optional API is absent. Domain content and row construction remain
plugin-owned in this first increment.

The [shared navigation components](components.md) provide row/header/empty-state
helpers with Foundation settings and cached live redraw. Next, extend layout
policies with minimum widths and collapsible panes, keeping focus and
application actions explicit.

Chrome's editor bars remain a planned part of the architecture. Its Bufferline
and Lualine replacements can consume these same pane identities and roles to
show navigation, active context, and cached application status consistently.
Adopt them surface by surface with restoration tests; pane adoption does not
force or preclude that migration.

## Verification

The regular Foundation integration gate also runs `tests/panes.lua`; Styling's
integration gate verifies generic discovery and live preview/revert. The optional
real-backend check uses an installed renderer and parser runtime without loading
the user's configuration:

```sh
UX_FOUNDATION_ROOT=/path/to/nvim-foundation \
UX_MARKDOWN_ROOT=/path/to/render-markdown.nvim \
UX_PARSER_ROOT=/path/to/parser-runtime \
UX_CHROME_TEST_FILE=tests/markdown_backend.lua \
  nvim --headless -u tests/minimal_init.lua -l scripts/run-test.lua
```
