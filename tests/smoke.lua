local h = require("tests.helpers")

local calls = { setup = 0, register = 0, refresh = 0, reset = 0, unregister = 0 }
local active_registration
local fake_foundation = { contract_version = 1 }

function fake_foundation.setup()
  calls.setup = calls.setup + 1
  return fake_foundation
end

function fake_foundation.register(manifest, implementation)
  calls.register = calls.register + 1
  h.equal(manifest.plugin.id, "ux.chrome")
  h.truthy(type(implementation.adapters) == "table"
      and type(implementation.adapters.ux_chrome) == "table",
    "setup omitted the Chrome structural adapter")
  active_registration = {
    handle = { plugin_id = "ux.chrome", serial = calls.register },
    manifest = vim.deepcopy(manifest),
    implementation = implementation,
  }
  return active_registration.handle
end

function fake_foundation.refresh(handle)
  calls.refresh = calls.refresh + 1
  h.equal(handle, active_registration and active_registration.handle)
  return true
end

function fake_foundation.unregister(handle)
  calls.unregister = calls.unregister + 1
  h.equal(handle, active_registration and active_registration.handle)
  active_registration = nil
  return true
end

function fake_foundation.registrations()
  if not active_registration then return {} end
  return { {
    manifest = vim.deepcopy(active_registration.manifest),
    availability = {},
  } }
end

function fake_foundation.state()
  return {
    contract_version = 1,
    registrations = active_registration and { "ux.chrome" } or {},
  }
end

function fake_foundation.begin_transaction()
  local transaction = {}
  function transaction:reset(scope)
    calls.reset = calls.reset + 1
    h.equal(scope, { plugin_id = "ux.chrome" })
    return true
  end
  function transaction:revert() return true end
  function transaction:commit() return true end
  return transaction
end

package.loaded.ux_foundation = fake_foundation

local function set_external_options()
  vim.api.nvim_set_option_value("tabline", "%!v:lua.ExternalChromeTabline()", { scope = "global" })
  vim.api.nvim_set_option_value("statusline", " external-status %% ", { scope = "global" })
  vim.api.nvim_set_option_value("winbar", " external-winbar ", { scope = "global" })
  vim.o.showtabline = 1
  vim.o.laststatus = 3
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value("statuscolumn", "%#LineNr# %l ", { win = win })
  vim.api.nvim_set_option_value("foldtext", "foldtext()", { win = win })
  vim.api.nvim_set_option_value("winhighlight", "Normal:Normal,CursorLine:Visual", { win = win })
end

local function all_external()
  return {
    tabline = "external",
    statusline = "external",
    winbar = "external",
    statuscolumn = "external",
    windows = "external",
    scrollbar = "external",
  }
end

local function lifecycle_count()
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "UXChromeLifecycle" })
  return ok and #autocmds or 0
end

h.test("plugin bootstrap registers the documented commands", function()
  vim.cmd("runtime plugin/ux-chrome.lua")
  for _, command in ipairs({
    "UXChromeEnable", "UXChromeDisable", "UXChromeToggle", "UXChromeRefresh", "UXChromeReset",
    "UXChromeDebug", "UXChromeHealth", "UXChromeBufferNext", "UXChromeBufferPrev",
    "UXChromeBufferFirst", "UXChromeBufferLast", "UXChromeBufferClose",
    "UXChromeBufferMoveLeft", "UXChromeBufferMoveRight",
  }) do
    h.equal(vim.fn.exists(":" .. command), 2, "missing command :" .. command)
  end
end)

h.test("auto ownership defers preexisting tabline and statusline byte-for-byte", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  set_external_options()
  local before = h.snapshot_options()
  h.truthy(chrome.setup({
    ownership = vim.tbl_extend("force", all_external(), {
      tabline = "auto",
      statusline = "auto",
    }),
  }))
  h.equal(vim.o.tabline, before.tabline)
  h.equal(vim.api.nvim_get_option_value("statusline", { scope = "global" }), before.statusline)
  local state = chrome.state()
  h.equal(state.ownership.tabline, "auto")
  h.equal(state.ownership.statusline, "auto")
  h.equal(state.surfaces.tabline.active, false)
  h.equal(state.surfaces.statusline.active, false)
  h.truthy(chrome.teardown())
  h.assert_options(before, "auto ownership changed preexisting external options")
end)

h.test("auto ownership yields to a late external tabline without clobbering it", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  vim.api.nvim_set_option_value("tabline", "", { scope = "global" })
  vim.o.showtabline = 1
  local ownership = all_external()
  ownership.tabline = "auto"
  h.truthy(chrome.setup({ ownership = ownership }))
  h.equal(vim.o.tabline, "%!v:lua.require'ux_chrome'.tabline()",
    "auto ownership did not acquire an empty tabline")

  local previous_late_renderer = _G.LateExternalChromeTabline
  _G.LateExternalChromeTabline = function() return "late" end
  local late_external = "%!v:lua.LateExternalChromeTabline()"
  vim.api.nvim_set_option_value("tabline", late_external, { scope = "global" })
  h.truthy(chrome.refresh())
  h.equal(vim.o.tabline, late_external,
    "Chrome clobbered a late external tabline during ownership reconciliation")
  h.equal(vim.o.showtabline, 1,
    "Chrome left its companion showtabline value behind after yielding ownership")
  h.equal(chrome.state().surfaces.tabline.active, false)
  h.truthy(chrome.teardown())
  h.equal(vim.o.tabline, late_external,
    "Chrome teardown clobbered a tabline after yielding ownership")
  h.equal(vim.o.showtabline, 1,
    "Chrome teardown drifted showtabline after yielding ownership")
  _G.LateExternalChromeTabline = previous_late_renderer
end)

h.test("auto ownership restores untouched window companions after a late takeover", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  local win = vim.api.nvim_get_current_win()
  local opening_statuscolumn = ""
  local opening_foldtext = "foldtext()"
  vim.api.nvim_set_option_value("statuscolumn", opening_statuscolumn, { win = win })
  vim.api.nvim_set_option_value("foldtext", opening_foldtext, { win = win })
  local ownership = all_external()
  ownership.statuscolumn = "auto"
  h.truthy(chrome.setup({ ownership = ownership }))
  h.truthy(vim.api.nvim_get_option_value("foldtext", { win = win }) ~= opening_foldtext,
    "auto ownership did not acquire the statuscolumn companion option")

  local late_statuscolumn = "%#LineNr# late:%l "
  vim.api.nvim_set_option_value("statuscolumn", late_statuscolumn, { win = win })
  h.truthy(chrome.refresh())
  h.equal(vim.api.nvim_get_option_value("statuscolumn", { win = win }), late_statuscolumn,
    "Chrome clobbered a late external statuscolumn")
  h.equal(vim.api.nvim_get_option_value("foldtext", { win = win }), opening_foldtext,
    "Chrome left its foldtext companion behind after yielding ownership")
  h.truthy(chrome.teardown())
  h.equal(vim.api.nvim_get_option_value("statuscolumn", { win = win }), late_statuscolumn)
  h.equal(vim.api.nvim_get_option_value("foldtext", { win = win }), opening_foldtext)
end)

h.test("window ownership preserves inherited global-local option state", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  local win = vim.api.nvim_get_current_win()
  local opening_global = vim.api.nvim_get_option_value("fillchars", { scope = "global" })
  local opening_local = vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" })
  local ok, err = xpcall(function()
    vim.api.nvim_set_option_value("fillchars", "vert:X", { scope = "global" })
    vim.api.nvim_set_option_value("fillchars", "", { win = win, scope = "local" })

    local ownership = all_external()
    ownership.windows = "auto"
    h.truthy(chrome.setup({ ownership = ownership }))
    h.equal(chrome.state().surfaces.windows.active, false,
      "auto ownership ignored inherited external fillchars")
    h.equal(vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" }), "")
    h.truthy(chrome.teardown())

    ownership.windows = "ux"
    h.truthy(chrome.setup({ ownership = ownership }))
    h.truthy(vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" }) ~= "",
      "explicit ownership did not establish local window treatment")
    h.truthy(chrome.teardown())
    h.equal(vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" }), "",
      "teardown replaced an inherited local option with an explicit effective value")
    h.equal(vim.api.nvim_get_option_value("fillchars", { win = win }), "vert:X")
  end, debug.traceback)
  pcall(chrome.teardown)
  vim.api.nvim_set_option_value("fillchars", opening_global, { scope = "global" })
  vim.api.nvim_set_option_value("fillchars", opening_local, { win = win, scope = "local" })
  if not ok then error(err) end
end)

h.test("statusline ownership preserves and explicitly replaces local owners", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  local win = vim.api.nvim_get_current_win()
  local opening_global = vim.api.nvim_get_option_value("statusline", { scope = "global" })
  local opening_local = vim.api.nvim_get_option_value("statusline", { win = win, scope = "local" })
  local opening_laststatus = vim.o.laststatus
  local ok, err = xpcall(function()
    vim.api.nvim_set_option_value("statusline", "", { scope = "global" })
    vim.api.nvim_set_option_value("statusline", " local-status-owner ", { win = win, scope = "local" })
    vim.o.laststatus = 2
    local configured_global = vim.api.nvim_get_option_value("statusline", { scope = "global" })
    local ownership = all_external()
    ownership.statusline = "auto"
    h.truthy(chrome.setup({ ownership = ownership }))
    h.equal(vim.api.nvim_get_option_value("statusline", { win = win }), " local-status-owner ",
      "auto ownership displaced a local statusline owner")
    h.equal(vim.api.nvim_get_option_value("statusline", { win = win, scope = "local" }),
      " local-status-owner ")
    h.truthy(chrome.teardown())

    ownership.statusline = "ux"
    h.truthy(chrome.setup({ ownership = ownership }))
    h.equal(vim.api.nvim_get_option_value("statusline", { win = win, scope = "local" }),
      "%!v:lua.require'ux_chrome'.statusline()",
      "explicit ownership did not replace a local statusline owner")
    h.truthy(chrome.teardown())
    h.equal(vim.api.nvim_get_option_value("statusline", { win = win, scope = "local" }),
      " local-status-owner ", "teardown did not restore the local statusline owner")
    h.equal(vim.api.nvim_get_option_value("statusline", { scope = "global" }), configured_global)
    h.equal(vim.o.laststatus, 2)
  end, debug.traceback)
  pcall(chrome.teardown)
  vim.api.nvim_set_option_value("statusline", opening_global, { scope = "global" })
  vim.api.nvim_set_option_value("statusline", opening_local, { win = win, scope = "local" })
  vim.o.laststatus = opening_laststatus
  if not ok then error(err) end
end)

h.test("late mapped-option takeover restores only Chrome-owned entries", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  local win = vim.api.nvim_get_current_win()
  local opening_global = vim.api.nvim_get_option_value("fillchars", { scope = "global" })
  local opening_local = vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" })
  local opening_global_winhighlight = vim.api.nvim_get_option_value("winhighlight", { scope = "global" })
  local opening_local_winhighlight = vim.api.nvim_get_option_value(
    "winhighlight", { win = win, scope = "local" })
  local ok, err = xpcall(function()
    vim.api.nvim_set_option_value("fillchars", "", { scope = "global" })
    vim.api.nvim_set_option_value("fillchars", "", { win = win, scope = "local" })
    vim.api.nvim_set_option_value("winhighlight", "", { scope = "global" })
    vim.api.nvim_set_option_value("winhighlight", "", { win = win, scope = "local" })
    local ownership = all_external()
    ownership.windows = "auto"
    h.truthy(chrome.setup({ ownership = ownership }))
    local applied = vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" })
    h.contains(applied, "horiz:")
    local external = applied:gsub("vert:[^,]+", "vert:X", 1)
    h.truthy(external ~= applied, "fixture did not replace the vertical split entry")
    vim.api.nvim_set_option_value("fillchars", external, { win = win, scope = "local" })
    h.truthy(chrome.refresh())
    local yielded = vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" })
    h.equal(yielded, "vert:X",
      "yielding a mapped option left unrelated Chrome fillchars entries behind")
    h.truthy(chrome.teardown())
    h.equal(vim.api.nvim_get_option_value("fillchars", { win = win, scope = "local" }), "vert:X")
  end, debug.traceback)
  pcall(chrome.teardown)
  vim.api.nvim_set_option_value("fillchars", opening_global, { scope = "global" })
  vim.api.nvim_set_option_value("fillchars", opening_local, { win = win, scope = "local" })
  vim.api.nvim_set_option_value("winhighlight", opening_global_winhighlight, { scope = "global" })
  vim.api.nvim_set_option_value("winhighlight", opening_local_winhighlight, { win = win, scope = "local" })
  if not ok then error(err) end
end)

h.test("real scrollbar viewport transport renders and tears down", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  local opening_buffer = vim.api.nvim_get_current_buf()
  local scratch = vim.api.nvim_create_buf(true, false)
  local ok, err = xpcall(function()
    local lines = {}
    for index = 1, 120 do lines[index] = "scrollbar line " .. index end
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(scratch)
    local ownership = all_external()
    ownership.scrollbar = "ux"
    h.truthy(chrome.setup({ ownership = ownership }))
    local rails = chrome.state().scrollbars
    h.equal(#rails, 1, "real Neovim viewport did not create a scrollbar rail")
    h.truthy(chrome.refresh())
    h.truthy(chrome.teardown())
    for _, rail in ipairs(rails) do
      h.truthy(not vim.api.nvim_win_is_valid(rail.win), "teardown left a scrollbar float open")
    end
  end, debug.traceback)
  pcall(chrome.teardown)
  if vim.api.nvim_buf_is_valid(opening_buffer) then vim.api.nvim_set_current_buf(opening_buffer) end
  if vim.api.nvim_buf_is_valid(scratch) then pcall(vim.api.nvim_buf_delete, scratch, { force = true }) end
  if not ok then error(err) end
end)

h.test("failed acquisition and public refresh restore exact options", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  set_external_options()
  local before = h.snapshot_options()
  h.truthy(chrome.setup({ ownership = all_external() }))
  local controller = chrome._controller_for_tests()
  local real_api = controller.api
  local fail_once = true
  controller.api = setmetatable({
    nvim_set_option_value = function(name, value, opts)
      if fail_once and name == "tabline" then
        fail_once = false
        error("synthetic tabline option failure")
      end
      return real_api.nvim_set_option_value(name, value, opts)
    end,
  }, { __index = real_api })
  local enabled, enable_error = chrome.enable("tabline", true)
  controller.api = real_api
  h.equal(enabled, false, "synthetic option failure unexpectedly acquired the tabline")
  h.contains(tostring(enable_error), "synthetic tabline option failure")
  h.equal(chrome.state().ownership.tabline, "external")
  h.assert_options(before, "failed option acquisition did not restore exact options")

  h.truthy(chrome.enable("tabline", true))
  vim.api.nvim_set_option_value("tabline", " late-refresh ", { scope = "global" })
  vim.api.nvim_set_option_value("showtabline", 1, { scope = "global" })
  local before_refresh = h.snapshot_options()
  fail_once = true
  controller.api = setmetatable({
    nvim_set_option_value = function(name, value, opts)
      if fail_once and name == "tabline" then
        fail_once = false
        error("synthetic refresh option failure")
      end
      return real_api.nvim_set_option_value(name, value, opts)
    end,
  }, { __index = real_api })
  local refreshed, refresh_error = chrome.refresh()
  controller.api = real_api
  h.equal(refreshed, false, "synthetic public refresh failure unexpectedly succeeded")
  h.contains(tostring(refresh_error), "synthetic refresh option failure")
  h.assert_options(before_refresh, "failed public refresh did not restore exact opening options")
  h.truthy(chrome.refresh(), "refresh did not recover after a transient option failure")
  h.equal(chrome.state().last_error, nil, "successful refresh retained a stale health error")
  h.truthy(chrome.teardown())
  h.assert_options(before, "teardown drifted after rollback tests")
end)

h.test("explicit UX ownership is idempotent and teardown restores exact options", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  set_external_options()
  local before = h.snapshot_options()
  local ownership = all_external()
  for _, surface in ipairs({ "tabline", "statusline", "winbar", "statuscolumn", "windows" }) do
    ownership[surface] = "takeover"
  end

  local registrations_before = calls.register
  local unregisters_before = calls.unregister
  h.truthy(chrome.setup({ ownership = ownership }))
  h.equal(vim.o.tabline, "%!v:lua.require'ux_chrome'.tabline()")
  h.equal(vim.api.nvim_get_option_value("statusline", { scope = "global" }),
    "%!v:lua.require'ux_chrome'.statusline()")
  h.equal(vim.api.nvim_get_option_value("winbar", { scope = "global" }),
    "%!v:lua.require'ux_chrome'.winbar()")
  local win = vim.api.nvim_get_current_win()
  h.contains(vim.api.nvim_get_option_value("statuscolumn", { win = win }), "ux_chrome'.statuscolumn")
  h.equal(vim.api.nvim_get_option_value("foldtext", { win = win }),
    "v:lua.require'ux_chrome'.foldtext()")
  h.contains(vim.api.nvim_get_option_value("winhighlight", { win = win }),
    "Normal:UXChromeWindowActive")
  h.equal(calls.register, registrations_before + 1,
    "explicit setup did not register exactly once after prior teardown")

  local initial_lifecycle_count = lifecycle_count()
  h.truthy(initial_lifecycle_count > 0, "setup omitted lifecycle hooks")
  h.truthy(chrome.setup({ ownership = ownership }))
  h.equal(calls.register, registrations_before + 1,
    "repeated setup duplicated the Foundation registration")
  h.equal(lifecycle_count(), initial_lifecycle_count,
    "repeated setup duplicated lifecycle hooks")
  h.truthy(chrome.refresh())
  h.truthy(chrome.reset())
  h.truthy(chrome.reset())
  h.equal(calls.reset, 2, "reset did not delegate to a Foundation plugin-scoped reset")
  h.equal(calls.unregister, unregisters_before,
    "reset unexpectedly tore down the Chrome registration")
  h.assert_json(chrome.state(), "ux.chrome.state")
  h.assert_json(chrome.debug(), "ux.chrome.debug")

  h.truthy(chrome.disable("tabline"))
  h.equal(vim.o.tabline, before.tabline, "disable did not release the tabline")
  h.truthy(chrome.enable("tabline", true))
  h.equal(vim.o.tabline, "%!v:lua.require'ux_chrome'.tabline()")
  h.truthy(chrome.toggle("tabline"))
  h.equal(vim.o.tabline, before.tabline)
  h.truthy(chrome.toggle("tabline", true))
  h.equal(vim.o.tabline, "%!v:lua.require'ux_chrome'.tabline()")

  vim.cmd("belowright split")
  local late_window = vim.api.nvim_get_current_win()
  local late_statuscolumn = "%#LineNr# late:%l "
  local late_winhighlight = "Normal:ErrorMsg,CursorLine:WarningMsg"
  vim.api.nvim_set_option_value("statuscolumn", late_statuscolumn, { win = late_window })
  vim.api.nvim_set_option_value("winhighlight", late_winhighlight, { win = late_window })
  h.truthy(chrome.refresh())
  h.truthy(vim.api.nvim_get_option_value("statuscolumn", { win = late_window })
      ~= late_statuscolumn, "Chrome did not acquire a window created after setup")
  h.truthy(vim.api.nvim_get_option_value("winhighlight", { win = late_window })
      ~= late_winhighlight, "Chrome did not apply treatment to a window created after setup")

  h.truthy(chrome.teardown())
  h.equal(vim.api.nvim_get_option_value("statuscolumn", { win = late_window }), late_statuscolumn,
    "teardown did not restore a late window's original statuscolumn")
  h.equal(vim.api.nvim_get_option_value("winhighlight", { win = late_window }), late_winhighlight,
    "teardown did not restore a late window's original winhighlight")
  vim.api.nvim_win_close(late_window, true)
  h.assert_options(before, "teardown did not restore exact global/window options")
  h.equal(lifecycle_count(), 0)
  h.equal(calls.unregister, calls.register,
    "teardown did not unregister each completed runtime")
  h.truthy(chrome.teardown(), "repeated teardown was not idempotent")
  h.assert_options(before, "repeated teardown drifted restored options")
end)

h.test("high-frequency editing events redraw without reconciling ownership", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  set_external_options()
  local before = h.snapshot_options()
  h.truthy(chrome.setup({
    ownership = {
      tabline = "ux", statusline = "ux", winbar = "ux",
      statuscolumn = "ux", windows = "ux", scrollbar = "external",
    },
  }))
  local controller = chrome._controller_for_tests()
  vim.wait(200, function() return not controller.scheduled end)
  local applied = h.snapshot_options()

  local reconciles, redraws = 0, 0
  local real_refresh, real_redraw = controller.refresh, controller.redraw
  controller.refresh = function(self, reason)
    reconciles = reconciles + 1
    return real_refresh(self, reason)
  end
  controller.redraw = function(self, reason, tabline)
    redraws = redraws + 1
    return real_redraw(self, reason, tabline)
  end

  for _ = 1, 25 do
    for _, event in ipairs({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "WinScrolled" }) do
      vim.api.nvim_exec_autocmds(event, { modeline = false })
    end
    vim.wait(1)
  end
  vim.wait(200, function() return not controller.scheduled end)

  controller.refresh, controller.redraw = real_refresh, real_redraw

  h.equal(reconciles, 0, "editing events reconciled surface ownership")
  h.truthy(redraws > 0, "editing events never reached the cheap redraw path")
  h.assert_options(applied, "the redraw path wrote a managed editor option")

  h.truthy(chrome.teardown())
  h.assert_options(before, "teardown drifted after redraw-only events")
end)

h.test("window topology changes still reconcile ownership", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  set_external_options()
  local before = h.snapshot_options()
  h.truthy(chrome.setup({
    ownership = {
      tabline = "ux", statusline = "ux", winbar = "ux",
      statuscolumn = "ux", windows = "ux", scrollbar = "external",
    },
  }))
  local controller = chrome._controller_for_tests()
  vim.wait(200, function() return not controller.scheduled end)

  local reconciles = 0
  local real_refresh = controller.refresh
  controller.refresh = function(self, reason)
    reconciles = reconciles + 1
    return real_refresh(self, reason)
  end

  vim.cmd("belowright split")
  local late_window = vim.api.nvim_get_current_win()
  vim.wait(200, function() return not controller.scheduled end)
  controller.refresh = real_refresh

  h.truthy(reconciles > 0, "a new window did not reconcile ownership")
  h.contains(vim.api.nvim_get_option_value("statuscolumn", { win = late_window }),
    "ux_chrome'.statuscolumn", "the reconciled window did not receive Chrome's statuscolumn")

  vim.api.nvim_win_close(late_window, true)
  h.truthy(chrome.teardown())
  h.assert_options(before, "teardown drifted after a window topology change")
end)

h.test("managed option maps append new keys in deterministic sorted order", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  local function map_keys(value)
    local result = {}
    for item in tostring(value or ""):gmatch("[^,]+") do
      local key = item:match("^([^:]+):")
      if key then result[#result + 1] = key end
    end
    return result
  end
  local win = vim.api.nvim_get_current_win()
  local opening = {}
  for _, name in ipairs({ "fillchars", "winhighlight" }) do
    opening[name] = h.set(map_keys(vim.api.nvim_get_option_value(name, { win = win })))
  end
  local before = h.snapshot_options()
  h.truthy(chrome.setup({
    ownership = {
      tabline = "external", statusline = "external", winbar = "external",
      statuscolumn = "external", windows = "ux", scrollbar = "external",
    },
  }))

  for _, name in ipairs({ "fillchars", "winhighlight" }) do
    local added = {}
    for _, key in ipairs(map_keys(vim.api.nvim_get_option_value(name, { win = win }))) do
      if not opening[name][key] then added[#added + 1] = key end
    end
    h.truthy(#added > 0, "Chrome added no " .. name .. " entries to compare")
    local sorted = vim.deepcopy(added)
    table.sort(sorted)
    h.equal(added, sorted, name .. " appended new keys in nondeterministic order")
  end

  h.truthy(chrome.teardown())
  h.assert_options(before, "teardown drifted after a deterministic map write")
end)

h.test("the cached buffer order follows buffer creation and deletion", function()
  local chrome = require("ux_chrome")
  chrome.teardown()
  local before = h.snapshot_options()
  h.truthy(chrome.setup({
    ownership = {
      tabline = "ux", statusline = "external", winbar = "external",
      statuscolumn = "external", windows = "external", scrollbar = "external",
    },
  }))
  local controller = chrome._controller_for_tests()
  vim.wait(200, function() return not controller.scheduled end)

  local created = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(created, "uxprobe.lua")
  vim.wait(200, function() return not controller.scheduled end)
  h.contains(chrome.tabline(), "uxprobe",
    "a newly listed buffer never reached the cached tabline order")

  vim.api.nvim_buf_delete(created, { force = true })
  vim.wait(200, function() return not controller.scheduled end)
  h.truthy(not chrome.tabline():find("uxprobe", 1, true),
    "a deleted buffer stayed in the cached tabline order")

  h.truthy(chrome.teardown())
  h.assert_options(before, "teardown drifted after buffer order changes")
end)

h.finish()
