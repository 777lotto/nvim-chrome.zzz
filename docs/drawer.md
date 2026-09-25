# Shared bottom drawer

Chrome provides one full-width output drawer per Neovim tab. It opens above the
statusline as a native split. Drag its upper divider to resize it. The selected
source and height survive closing and reopening within the session. Each tab
has its own filter, follow state, scroll position, buffer, and unread counts.
Provider output is shared across tabs.

Click **Logs** in Chrome's statusline, or run `:UXChromeDrawerToggle`. The item
shows unread retained lines and `!N` for unread error lines. It yields space to
the ruler and progress indicator in narrow windows. External statuslines can
use `require("ux_chrome.drawer").status()` for the same counts. Foundation exposes
`ux.chrome/statusline/setting_show_drawer/value` to show or hide the status item. Drawer commands
work independently of editor-wide Chrome ownership.

The built-in **Messages** source snapshots Neovim's `:messages` history when
opened or explicitly refreshed. It does not intercept `vim.notify`, poll, or
replace command-line handling. Clear empties the drawer's snapshot; refreshing
Messages reads Neovim's history again. Other plugins register their own sources;
this release does not automatically capture Agent Manager, GitPanel, or MCP Buff
output.

## Controls

| Command | Action |
| --- | --- |
| `:UXChromeDrawerOpen[!] [provider.id]` | Open a source, or the remembered source. `!` preserves editor focus. |
| `:UXChromeDrawerToggle` | Open or close the current tab's drawer. |
| `:UXChromeDrawerClose` | Close and return focus to the originating window when available. |
| `:UXChromeDrawerSource` | Select a registered source. |
| `:UXChromeDrawerFollow` | Toggle following new output. |
| `:UXChromeDrawerFilter [text]` | Set a case-insensitive literal filter; no argument resets it. |
| `:UXChromeDrawerRefresh` | Request a fresh snapshot from the selected provider. |
| `:UXChromeDrawerClear` | Clear the selected source across all tabs. |

Inside the drawer, `s` selects a source, `f` toggles follow, `F` edits the filter,
`r` refreshes, `C` clears, and `q` closes. Normal `/` search, selection, copying,
and mouse scrolling remain available. Chrome installs no global keybindings;
the distribution can map `:UXChromeDrawerToggle` to its preferred key.

Background output never opens the drawer or takes focus. Following keeps the
cursor at the end. Moving the cursor or scrolling away pauses following; press
`f` to resume. Retention preserves the currently read line while it remains in
history. An active, unfiltered, following view acknowledges its source's output.
Inactive tabs and filtered or paused views keep their unread counts. Counts
cover retained lines, so evicted history no longer contributes.

## Provider API

Register once during plugin setup, then publish cached output from callbacks:

```lua
local drawer = require("ux_chrome.drawer")
local id = drawer.register({
  id = "example.build.output",
  label = "Build output",
  limit = 5000,
})

drawer.append(id, "Verification started")
drawer.append(id, { text = "Verification failed", level = "error" })
drawer.append(id, { "first line", "second line" })
drawer.open(id, { focus = false })
```

IDs are permanent dotted lowercase identifiers. Duplicate registrations raise an
error, so plugins should register once and `unregister(id)` on teardown. Labels
are plain single-line text. The retention limit defaults to 5,000 lines and must
be between 1 and 50,000. Levels are `debug`, `info` (default), `warn`, and `error`.
Warning and error lines use Neovim's `DiagnosticWarn` and `DiagnosticError`
highlights. Multiline entries split into lines; control characters are sanitized.

`append(id, entries)` adds output; `replace(id, entries)` replaces its snapshot.
Both accept a string, one `{text, level}` entry, or a list of these. Validation is
atomic and updates coalesce through Neovim's scheduler. Providers retain control
of what is collected and when it is published; no provider callbacks run inside
statusline rendering.

Snapshot providers can supply optional callbacks:

```lua
drawer.register({
  id = "example.tasks.output",
  label = "Tasks",
  refresh = function()
    return cached_task_lines -- strings or {text, level} entries
  end,
  clear = function()
    cached_task_lines = {}
  end,
})
```

`refresh()` runs only on explicit open or refresh and may return a replacement
snapshot, or nil when the provider will publish asynchronously. `clear()` runs
before the drawer clears retained entries. Callback errors propagate without
clearing the last valid output. Callbacks should return quickly; schedule domain
work in the owning plugin. Opening without an ID selects the remembered source,
or the first registered ID in sorted order.

Additional APIs:

```lua
drawer.close()
drawer.toggle()
drawer.choose()
drawer.follow(true)       -- false pauses; no argument toggles
drawer.filter("error")    -- empty string resets
drawer.refresh(id)        -- no ID uses the selected provider
drawer.clear()
drawer.providers()        -- defensive {id, label, count} list
drawer.status(tabpage)    -- cached {unread, errors, open}; defaults to current tab
drawer.inspect(tabpage)   -- defensive session state
drawer.unregister(id)
drawer.teardown()
```

Chrome owns the disposable output buffers and window lifecycle. Each selected
provider reuses the shared pane API with its provider ID and the `log` role, so
Foundation and Styling can edit wrapping, gutters, selection, and pane colors.
Removing a provider falls back to another source or an empty view. Tab closure
removes its buffer. Replacing the drawer buffer releases its window treatment.
`chrome.teardown()` closes drawers before unregistering shared presentation.

## Verification

`tests/drawer.lua` exercises retention, follow, filtering, focus, tab isolation,
provider errors, removal, commands, and teardown. `tests/drawer_mouse.lua` attaches
an isolated UI and verifies native divider dragging, remembered height, and the
statusline click target. Both run through the Foundation integration gate.
