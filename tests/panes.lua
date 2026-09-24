local h = require("tests.helpers")
vim.opt.runtimepath:prepend(h.dependency_root("UX_FOUNDATION_ROOT", "UX-foundation.nvim"))
local foundation = require("ux_foundation")
local panes = require("ux_chrome.panes")
local api = vim.api
foundation.setup({ load_active = false })

local function window()
  local buf = api.nvim_create_buf(false, true)
  return api.nvim_open_win(buf, false, { relative = "editor", row = 1, col = 1, width = 40, height = 8 }), buf
end
local function attach(id, role, content)
  local win, buf = window()
  panes.attach({ id = id, role = role, content = content, window = win, buffer = buf })
  return win, buf
end
local role_wrap = "ux.chrome.panes/log/wrap/value"
local function override(id) return "ux.chrome.pane." .. id .. "/presentation/wrap/value" end

h.test("shared colors keep native links until edited and restore them on revert", function()
  local win = attach("test.colors", "context", "plaintext")
  local tx = assert(foundation.begin_transaction())
  assert(tx:stage("ux.chrome.panes/appearance/normal/foreground", { kind = "rgb", value = "#123456" }))
  h.equal(api.nvim_get_hl(0, { name = "UXChromePaneNormal", link = false }).fg, 0x123456)
  assert(tx:revert()); assert(tx:commit())
  h.equal(api.nvim_get_hl(0, { name = "UXChromePaneNormal", link = true }).link, "Normal")
  assert(panes.teardown()); api.nvim_win_close(win, true)
end)

h.test("shared role edits, per-pane exceptions, undo and reopen", function()
  local first = attach("test.first", "log", "plaintext")
  local second = attach("test.second", "log", "plaintext")
  local nav = attach("test.nav", "navigation", "list")
  h.equal(vim.wo[first].wrap, true)
  h.equal(vim.wo[nav].wrap, false)
  local tx = assert(foundation.begin_transaction())
  assert(tx:stage(role_wrap, false))
  h.equal(vim.wo[first].wrap, false)
  h.equal(vim.wo[second].wrap, false)
  assert(tx:stage(override("test.second"), "on"))
  h.equal(vim.wo[second].wrap, true)
  assert(tx:undo())
  h.equal(vim.wo[second].wrap, false)
  assert(tx:redo())
  assert(tx:commit())
  api.nvim_win_close(first, true)
  first = attach("test.first", "log", "plaintext")
  h.equal(vim.wo[first].wrap, false)
  local late = attach("test.late", "log", "plaintext")
  h.equal(vim.wo[late].wrap, false)
  assert(panes.teardown())
  for _, win in ipairs({ first, second, nav, late }) do api.nvim_win_close(win, true) end
end)

h.test("saved settings survive restart without Styling and preserve stable identities", function()
  foundation._reset_for_tests()
  foundation.setup({ load_active = false })
  local win = attach("test.saved", "log", "plaintext")
  local tx = assert(foundation.begin_transaction())
  assert(tx:stage(role_wrap, false))
  assert(tx:stage(override("test.saved"), "on"))
  assert(tx:save())
  assert(panes.teardown())
  api.nvim_win_close(win, true)
  foundation._reset_for_tests()
  foundation.setup({ load_active = true })
  win = attach("test.saved", "log", "plaintext")
  local other = attach("test.other", "log", "plaintext")
  h.equal(vim.wo[win].wrap, true)
  h.equal(vim.wo[other].wrap, false)
  h.equal(package.loaded.ux_styling, nil)
  assert(panes.teardown())
  api.nvim_win_close(win, true); api.nvim_win_close(other, true)
end)

h.test("revert restores live options and detaching preserves later external edits", function()
  foundation._reset_for_tests(); foundation.setup({ load_active = false })
  local win, buf = window()
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = "Normal:Error,FloatBorder:WarningMsg"
  panes.attach({ id = "test.restore", role = "log", window = win, buffer = buf })
  local tx = assert(foundation.begin_transaction())
  assert(tx:stage(role_wrap, false))
  local late = attach("test.later", "log", "plaintext")
  h.equal(vim.wo[late].wrap, false)
  assert(tx:revert()); assert(tx:commit())
  h.equal(vim.wo[win].wrap, true)
  h.equal(vim.wo[late].wrap, true)
  vim.wo[win].cursorline = true
  assert(panes.detach(win))
  h.equal(vim.wo[win].wrap, false)
  h.equal(vim.wo[win].winhighlight, "Normal:Error,FloatBorder:WarningMsg")
  h.equal(vim.wo[win].cursorline, true)
  panes.attach({ id = "test.restore", role = "log", window = win, buffer = buf })
  vim.wo[win].winhighlight = vim.wo[win].winhighlight .. ",Search:Error"
  assert(panes.detach(win))
  h.contains(vim.wo[win].winhighlight, "Normal:Error")
  h.contains(vim.wo[win].winhighlight, "Search:Error")
  h.truthy(not vim.wo[win].winhighlight:find("UXChromePane", 1, true))
  assert(panes.teardown())
  api.nvim_win_close(win, true); api.nvim_win_close(late, true)
end)

h.test("shared buffer gets independent window preferences and buffer replacement releases ownership", function()
  local win, buf = attach("test.buffer_one", "navigation", "list")
  local second = api.nvim_open_win(buf, false, { relative = "editor", row = 2, col = 2, width = 30, height = 5 })
  panes.attach({ id = "test.buffer_two", role = "log", content = "list", window = second, buffer = buf })
  h.equal(vim.wo[win].wrap, false)
  h.equal(vim.wo[second].wrap, true)
  api.nvim_win_set_buf(win, api.nvim_create_buf(false, true))
  h.equal(panes.owns(win), false)
  -- Other views of the old buffer must remain managed.
  h.equal(panes.owns(second), true)
  assert(panes.teardown())
  api.nvim_win_close(win, true); api.nvim_win_close(second, true)
end)

h.test("Markdown uses public backend API and never rewrites its global configuration", function()
  local rendered = {}
  package.loaded["render-markdown"] = {
    render = function(ctx) rendered[#rendered + 1] = ctx end,
    setup = function() error("must not reconfigure backend") end,
  }
  local win, buf = attach("test.markdown", "context", "markdown")
  h.equal(rendered[1].buf, buf)
  h.equal(rendered[1].win, win)
  h.equal(panes.inspect(win).markdown.backend, "render-markdown")
  api.nvim_buf_set_lines(buf, 0, -1, false, { "# Updated Markdown" })
  h.truthy(vim.wait(1000, function() return #rendered > 1 end), "streamed content did not render")
  assert(panes.teardown())
  package.loaded["render-markdown"] = nil
  api.nvim_win_close(win, true)
end)

h.test("failed physical application rolls back every pane and transaction history", function()
  foundation._reset_for_tests(); foundation.setup({ load_active = false })
  local first = attach("test.failure_one", "log", "plaintext")
  local second = attach("test.failure_two", "log", "plaintext")
  local tx = assert(foundation.begin_transaction())
  local original = api.nvim_set_option_value
  local injected = false
  api.nvim_set_option_value = function(name, value, opts)
    if not injected and name == "wrap" and opts.win == second and value == false then
      injected = true; error("synthetic option failure")
    end
    return original(name, value, opts)
  end
  local ok = tx:stage(role_wrap, false)
  api.nvim_set_option_value = original
  h.equal(ok, false)
  h.equal(vim.wo[first].wrap, true)
  h.equal(vim.wo[second].wrap, true)
  h.equal(tx:status().undo, 0)
  assert(tx:commit()); assert(panes.teardown())
  api.nvim_win_close(first, true); api.nvim_win_close(second, true)
end)

h.test("pane acquisition releases prior Chrome window treatment and leaves editor bars available", function()
  foundation._reset_for_tests(); foundation.setup({ load_active = false })
  local chrome = require("ux_chrome")
  local win = api.nvim_get_current_win()
  local original = vim.wo[win].winhighlight
  chrome.setup({ ownership = { windows = "ux", statuscolumn = "ux", tabline = "ux", statusline = "ux" } })
  panes.attach({ id = "test.editor", role = "navigation", content = "list", window = win })
  assert(chrome.refresh())
  h.contains(vim.wo[win].winhighlight, "UXChromePaneNormal")
  h.truthy(chrome.state().surfaces.tabline.active)
  assert(panes.detach(win))
  h.equal(vim.wo[win].winhighlight, original)
  assert(chrome.teardown())
end)

h.finish()
