# Shared navigation components

Chrome supplies single-line rows, section headers, and empty-state presentation.
Plugins supply text, tree connectors, counts, semantic status colors, action
targets, and selection. Chrome never inserts rows or implements application
actions. This API is independent of editor-bar ownership and does not require
opening Styling. Foundation schema v1 is unchanged.

```lua
local components = require("ux_chrome.components")
local function redraw()
  local context = components.context({
    id = "example.navigation", -- permanent dotted component identity
    window = win,
    width = vim.api.nvim_win_get_width(win),
    redraw = redraw, -- synchronous rendering from cached application state
  })
  local header, header_style = context:format({
    kind = "header", text = "Sessions", prefix = "▾", count = 2,
  })
  local row, row_style = context:format({ text = "Example session", prefix = "●" })
  local empty, empty_style = context:format({ kind = "empty", text = "(none)" })
  -- Write lines and highlights; retain your own row-to-action mapping.
end
```

`format` returns text and `{start, finish, group}`. Offsets are zero-based UTF-8
byte offsets delimiting the content after the prefix; `finish` is exclusive.
Use the group across the entire line or add application-specific spans. The
optional `highlight` selects a semantic plugin group. The default groups are
`UXChromeComponentRow`, `UXChromeComponentHeader`, and `UXChromeComponentEmpty`,
initially linked to Normal, Title, and Comment. Foundation exposes their links,
foregrounds, and backgrounds under `ux.chrome.components.appearance`.

Formatting resolves padding plus `depth * indent`. Header depth defaults to 0;
row and empty-state depth default to 1. Explicit depth is a nonnegative integer
up to 100. A supplied prefix receives one separating space. Count spacing uses
`gap`. Control characters are replaced with spaces. Truncation uses display
cells and keeps combining marks with their base character. Content supplied by
the plugin remains authoritative; truncation never alters its action target.

| Setting | Shared default | Values |
| --- | --- | --- |
| `padding` | 1 | 0–8 cells |
| `indent` | 2 | 0–8 cells per depth |
| `gap` | 2 | 0–8 cells before a count |
| `truncation` | `ellipsis` | `ellipsis`, `clip`, `none` |

Shared property IDs are `ux.chrome.components/navigation/<setting>/value`.
Component overrides are
`ux.chrome.component.<id>/navigation/<setting>/value`. Numeric overrides use
`-1` to inherit; truncation uses `inherit`. Foundation supplies declared,
saved-profile, and session precedence within each scope. Registrations remain
after windows close; `register(id)` exposes settings before first render.
`inspect(id)` returns resolved settings. Each context captures settings for
that render; create a new context on redraw.

Contexts can be used without a window for deterministic rendering. Supplying
both `window` and `redraw` subscribes the window to live property edits and
resize events. Redraw must be synchronous, idempotent, and use cached content;
it must not fetch, schedule an asynchronous application update, move focus, or
change row identity. Foundation rollback invokes it again with restored values
if a callback fails. Chrome preserves the window view and cursor around it.
An application callback that always fails cannot be repaired by presentation
rollback; its error is surfaced by Foundation.

The buffer must belong to the application. Since these helpers produce buffer
text, multiple windows showing one buffer share that text and cannot have
different width-specific layouts. Use separate scratch buffers for independent
layouts. Switching buffers or closing windows releases callbacks; explicit
`detach(win)` also releases one. `components.teardown()` unregisters settings,
and `chrome.teardown()` includes it. Components own no application buffers or
window options, so teardown leaves the last rendered text for the application
to replace.

Adoption is incremental: Git uses the helpers for section headers, file rows,
and empty states; MCP uses them for navigation headings, ticket rows, and empty
ticket categories. Native fallbacks remain when the optional module is absent.
Other application-specific rows can migrate as common patterns emerge.

Next: minimum widths and collapsible-pane layout policies, then editor bars
using the same pane identities. Renderer-specific transactional Markdown
options still require reliable backend snapshot and restoration support.
