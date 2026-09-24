local h = require("tests.helpers")

local foundation_root = h.dependency_root("UX_FOUNDATION_ROOT", "UX-foundation.nvim")
h.truthy(vim.fn.isdirectory(foundation_root) == 1,
  "UX Foundation checkout not found; set UX_FOUNDATION_ROOT for integration tests")
vim.opt.runtimepath:prepend(foundation_root)

local searchers = package.searchers or package.loaders
local function reject_styling(name)
  if name == "ux_styling" or name:match("^ux_styling%.") then
    error("UX Chrome loaded Styling at component runtime: " .. name)
  end
end
table.insert(searchers, 1, reject_styling)

local foundation = require("ux_foundation")
local chrome = require("ux_chrome")
local api = vim.api

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

local function remove_searcher()
  for index, candidate in ipairs(searchers) do
    if candidate == reject_styling then
      table.remove(searchers, index)
      return
    end
  end
end

local function cleanup()
  pcall(chrome._reset_for_tests)
  pcall(foundation._reset_for_tests)
  remove_searcher()
end

h.test("direct Foundation registration works without a profile or Styling", function()
  local ok, err = xpcall(function()
    chrome._reset_for_tests()
    foundation._reset_for_tests()
    local foundation_opts = {
      core = false,
      lifecycle = true,
      load_active = false,
      storage_dir = vim.fs.joinpath(vim.g.ux_chrome_test_root, "foundation", "profiles"),
    }
    foundation.setup(foundation_opts)
    local opening_profile = foundation.current_profile()
    h.equal(opening_profile.id, "default", "integration unexpectedly loaded a saved profile")
    h.equal(opening_profile.overrides, {}, "default no-profile state contains overrides")
    h.truthy(chrome.setup({ foundation = foundation_opts, ownership = all_external() }))

    local registration = h.truthy(h.find_registration(foundation, "ux.chrome"),
      "Foundation omitted the direct ux.chrome registration")
    h.equal(registration.manifest.schema_version, 1)
    h.equal(registration.manifest.plugin, chrome.manifest().plugin,
      "Foundation changed Chrome's published plugin identity")
    h.equal(registration.manifest.components, chrome.manifest().components,
      "Foundation changed Chrome's published component catalog")
    h.equal(registration.manifest.tokens, {},
      "Foundation's schema normalization added unexpected token claims")
    h.assert_json(registration.manifest, "foundation.ux.chrome.manifest")
    for _, component in ipairs(registration.manifest.components) do
      h.equal(registration.availability[component.id].available, true,
        "Chrome component unavailable in Foundation: " .. component.id)
    end
    h.equal(h.module_keys("ux_styling"), {},
      "Chrome loaded Styling while registering with Foundation")

    local foreground_id = "ux.chrome/buffer_tabs/active/foreground"
    local structural_id = "ux.chrome/buffer_tabs/setting_modified_icon/value"
    local inspected = h.truthy(foundation.inspect(foreground_id))
    h.equal(inspected.resolved, { kind = "rgb", value = "#CAD3F5" })
    h.equal(inspected.provenance.layer, "declared",
      "no-profile integration unexpectedly used saved provenance")
    h.equal(inspected.availability.available, true)
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }).fg, 0xCAD3F5)
    h.equal(foundation.inspect(structural_id).resolved, "●")

    local replay_tx = h.truthy(foundation.begin_transaction())
    h.truthy(replay_tx:stage(foreground_id, { kind = "rgb", value = "#A1B2C3" }))
    h.truthy(replay_tx:commit())
    local colorscheme_generation = foundation.state().generation
    api.nvim_set_hl(0, "UXChromeTabActive", { fg = "#010203" })
    api.nvim_exec_autocmds("ColorScheme", { pattern = "ux-chrome-one", modeline = false })
    api.nvim_exec_autocmds("ColorScheme", { pattern = "ux-chrome-two", modeline = false })
    h.truthy(vim.wait(1000, function()
      return foundation.state().generation > colorscheme_generation
    end), "Foundation did not replay Chrome after ColorScheme")
    h.equal(foundation.state().generation, colorscheme_generation + 1,
      "back-to-back ColorScheme events were not coalesced")
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }).fg, 0xA1B2C3,
      "ColorScheme replay did not restore Chrome's active session value")

    local opening_highlight = api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true })
    local opening_icon = chrome.state().values["buffer_tabs.modified_icon"]
    local tx = h.truthy(foundation.begin_transaction())
    h.truthy(tx:stage(foreground_id, { kind = "rgb", value = "#123456" }))
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }).fg, 0x123456)
    h.truthy(tx:stage(structural_id, "M"))
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], "M")
    h.equal(tx:status().undo, 2)

    h.truthy(tx:undo())
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], opening_icon)
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }).fg, 0x123456)
    h.truthy(tx:undo())
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }), opening_highlight)
    h.truthy(tx:redo())
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }).fg, 0x123456)
    h.truthy(tx:redo())
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], "M")
    h.truthy(tx:reset(structural_id))
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], opening_icon)
    h.truthy(tx:undo())
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], "M")
    h.truthy(tx:revert())
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }), opening_highlight)
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], opening_icon)
    h.truthy(tx:commit())

    local separator_id = "ux.chrome/gutter/setting_separator/value"
    local win = api.nvim_get_current_win()
    local external_statuscolumn = api.nvim_get_option_value("statuscolumn", { win = win })
    h.truthy(chrome.enable("statuscolumn", true))
    local owned_statuscolumn = api.nvim_get_option_value("statuscolumn", { win = win })
    h.truthy(owned_statuscolumn ~= external_statuscolumn,
      "explicit statuscolumn ownership did not acquire the local option")

    local physical_tx = h.truthy(foundation.begin_transaction())
    h.truthy(physical_tx:stage(separator_id, "!"))
    local staged_statuscolumn = api.nvim_get_option_value("statuscolumn", { win = win })
    h.truthy(staged_statuscolumn ~= owned_statuscolumn,
      "staging the gutter separator did not update the owned physical option")
    h.contains(staged_statuscolumn, "!")
    h.truthy(physical_tx:revert())
    h.equal(api.nvim_get_option_value("statuscolumn", { win = win }), owned_statuscolumn,
      "transaction revert did not byte-exactly restore the owned statuscolumn")
    h.truthy(physical_tx:commit())

    local placement_id = "ux.chrome/statusline/setting_placement/value"
    local placement_tx = h.truthy(foundation.begin_transaction())
    h.truthy(placement_tx:stage(placement_id, "global"))
    h.equal(chrome._controller_for_tests():_statusline_context().width, vim.o.columns,
      "global statusline used a split width instead of the editor width")
    h.truthy(placement_tx:revert())
    h.truthy(placement_tx:commit())

    local split_id = "ux.chrome/window_treatment/setting_split_vertical/value"
    local before_invalid_fillchars = api.nvim_get_option_value("fillchars", { win = win, scope = "local" })
    local validation_tx = h.truthy(foundation.begin_transaction())
    local valid, validation_error = validation_tx:stage(split_id, "ab")
    h.equal(valid, false, "Foundation accepted a multi-cell fillchars value")
    h.error_code(validation_error, "invalid_value")
    h.equal(api.nvim_get_option_value("fillchars", { win = win, scope = "local" }),
      before_invalid_fillchars, "invalid fillchars staging changed the physical option")
    h.truthy(validation_tx:commit())

    local failure_tx = h.truthy(foundation.begin_transaction())
    h.truthy(failure_tx:stage(separator_id, "V"))
    local last_valid_options = h.snapshot_options()
    local last_valid_highlight = api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true })
    local last_valid_state = chrome.state().values
    local last_valid_history = failure_tx:status()

    if type(chrome._inject_failure_for_tests) == "function" then
      chrome._inject_failure_for_tests("apply", "synthetic Chrome apply failure")
      local applied, apply_error = failure_tx:stage(separator_id, "A")
      h.equal(applied, false, "injected adapter apply failure unexpectedly succeeded")
      h.error_code(apply_error, "apply_failed")
      h.equal(chrome.state().values, last_valid_state,
        "failed apply changed Chrome's last valid structural state")
      h.equal(failure_tx:status(), last_valid_history,
        "failed apply changed transaction history")
      h.assert_options(last_valid_options, "failed apply changed physical editor options")
      h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }),
        last_valid_highlight, "failed apply changed physical highlights")

      chrome._inject_failure_for_tests("rerender", "synthetic Chrome rerender failure")
      local rerendered, rerender_error = failure_tx:stage(separator_id, "R")
      h.equal(rerendered, false, "injected adapter rerender failure unexpectedly succeeded")
      h.error_code(rerender_error, "apply_failed")
      h.equal(chrome.state().values, last_valid_state,
        "failed rerender did not restore Chrome's last valid structural state")
      h.equal(failure_tx:status(), last_valid_history,
        "failed rerender changed transaction history")
      h.assert_options(last_valid_options, "failed rerender changed physical editor options")
      h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }),
        last_valid_highlight, "failed rerender changed physical highlights")
    end

    h.truthy(failure_tx:revert())
    h.truthy(failure_tx:commit())
    h.equal(api.nvim_get_option_value("statuscolumn", { win = win }), owned_statuscolumn,
      "failure transaction revert did not restore the opening statuscolumn")
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], opening_icon)
    h.truthy(chrome.disable("statuscolumn"))
    h.equal(api.nvim_get_option_value("statuscolumn", { win = win }), external_statuscolumn,
      "releasing statuscolumn ownership did not restore the external option byte-for-byte")
    h.equal(h.module_keys("ux_styling"), {},
      "Chrome loaded Styling during Foundation transactions")
  end, debug.traceback)
  cleanup()
  if not ok then error(err) end
end)

h.finish()

-- The shared panes use the same frozen schema and run on both CI platforms.
dofile("tests/panes.lua")
