local h = require("tests.helpers")

local foundation_root = h.dependency_root("UX_FOUNDATION_ROOT", "UX-foundation.nvim")
local styling_root = h.dependency_root("UX_STYLING_ROOT", "UX-styling.nvim")
h.truthy(vim.fn.isdirectory(foundation_root) == 1,
  "UX Foundation checkout not found; set UX_FOUNDATION_ROOT for integration tests")
h.truthy(vim.fn.isdirectory(styling_root) == 1,
  "UX Styling checkout not found; set UX_STYLING_ROOT for integration tests")
vim.opt.runtimepath:prepend(foundation_root)
vim.opt.runtimepath:prepend(styling_root)

local foundation = require("ux_foundation")
local chrome = require("ux_chrome")
local styling = require("ux_styling")
local preview = require("ux_styling.render.preview")
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

local function tree_root(tree, plugin_id)
  for _, root in ipairs((tree or {}).roots or {}) do
    if root.id == plugin_id then return root end
  end
end

local function has_value(items, wanted)
  for _, item in ipairs(items or {}) do
    if item == wanted then return true end
  end
  return false
end

local function cleanup()
  pcall(styling.close)
  pcall(styling._reset_for_tests)
  pcall(chrome._reset_for_tests)
  pcall(foundation._reset_for_tests)
end

h.test("Styling discovers Chrome as a distinct category with a generic preview", function()
  local ok, err = xpcall(function()
    cleanup()
    local foundation_opts = {
      core = false,
      lifecycle = false,
      load_active = false,
      storage_dir = vim.fs.joinpath(vim.g.ux_chrome_test_root, "styling", "profiles"),
    }
    foundation.setup(foundation_opts)
    h.truthy(chrome.setup({ foundation = foundation_opts, ownership = all_external() }))
    h.truthy(h.find_registration(foundation, "ux.chrome"),
      "Chrome did not register before Styling was opened")

    styling.setup({ foundation = foundation_opts, raw_browser = false })
    local workspace = h.truthy(styling.open(), "Styling workspace failed to open")
    workspace:render()

    local chrome_root = h.truthy(tree_root(workspace.tree, "ux.chrome"),
      "Styling omitted direct ux.chrome registration")
    local bufferline_root = h.truthy(tree_root(workspace.tree, "ux.chrome.bufferline"),
      "Styling omitted frozen M2 Bufferline category")
    local lualine_root = h.truthy(tree_root(workspace.tree, "ux.chrome.lualine"),
      "Styling omitted frozen M2 Lualine category")
    h.equal(chrome_root.depth, 0)
    h.equal(bufferline_root.depth, 0)
    h.equal(lualine_root.depth, 0)
    h.equal(chrome_root.parent_key, nil)
    h.equal(bufferline_root.parent_key, nil)
    h.equal(lualine_root.parent_key, nil)
    h.truthy(chrome_root ~= bufferline_root and chrome_root ~= lualine_root,
      "Styling merged original Chrome into an M2 adapter category")

    local fixture = preview.plugin_fixture(chrome_root, {
      inspect = function(property_id) return foundation.inspect(property_id) end,
      max_lines = 8,
    })
    -- The generic preview spans every component, so it declares its own
    -- derived ID. It previously borrowed the FIRST component's declared
    -- fixture_id, which mislabelled a whole-plugin preview as the buffer-tabs
    -- one; this test asserted that mislabel as correct.
    h.equal(fixture.id, "ux.chrome.preview.v1",
      "generic preview did not declare its own plugin-derived fixture ID")
    h.truthy(fixture.id ~= "ux.chrome.buffer_tabs.v1",
      "generic preview borrowed a component's declared fixture ID")
    h.equal(fixture.label, "Chrome · adapter preview")
    local rendered = preview.render(fixture, { width = 240 })
    local saw_group, saw_property = false, false
    for _, span in ipairs(rendered.spans) do
      if span.hl_group == "UXChromeTabActive" then saw_group = true end
      if type(span.property_id) == "string" and vim.startswith(span.property_id, "ux.chrome/") then
        saw_property = true
      end
    end
    h.truthy(saw_group, "generic preview did not render Chrome's real managed groups")
    h.truthy(saw_property, "generic preview did not retain Chrome property IDs")
    h.contains(table.concat(rendered.lines, "\n"), "Buffer Tabs and Native Tabline",
      "generic preview did not render Chrome's component source")

    h.equal(chrome_root.children[1].source.preview.fixture_id, "ux.chrome.buffer_tabs.v1",
      "Styling model lost the component's schema-v1 preview source")

    local raw_names = workspace.bridge:raw_highlights("uxchrome")
    h.truthy(not has_value(raw_names, "UXChromeTabActive"),
      "Styling duplicated a directly registered Chrome highlight in raw browsing")

    local foreground_id = "ux.chrome/buffer_tabs/active/foreground"
    local structural_id = "ux.chrome/buffer_tabs/setting_modified_icon/value"
    local opening_highlight = api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true })
    local opening_icon = chrome.state().values["buffer_tabs.modified_icon"]
    h.truthy(workspace.transaction:stage(
      foreground_id, { kind = "rgb", value = "#345678" }))
    h.truthy(workspace.transaction:stage(structural_id, "S"))
    workspace.dirty = true
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }).fg, 0x345678)
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], "S")
    h.truthy(styling.close(), "Styling close failed to revert its transaction")
    h.equal(api.nvim_get_hl(0, { name = "UXChromeTabActive", link = true }), opening_highlight,
      "Styling close did not restore Chrome's exact physical highlight")
    h.equal(chrome.state().values["buffer_tabs.modified_icon"], opening_icon,
      "Styling close did not restore Chrome's exact structural state")
  end, debug.traceback)
  cleanup()
  if not ok then error(err) end
end)

h.finish()
