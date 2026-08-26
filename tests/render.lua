local h = require("tests.helpers")
local common = require("ux_chrome.render.common")
local foldtext = require("ux_chrome.render.foldtext")
local statuscolumn = require("ux_chrome.render.statuscolumn")
local statusline = require("ux_chrome.render.statusline")
local tabline = require("ux_chrome.render.tabline")
local winbar = require("ux_chrome.render.winbar")
local Scrollbar = require("ux_chrome.scrollbar")

local buffers = {
  { id = 1, name = "/work/one.lua" },
  { id = 2, name = "/work/two.lua", visible = true, modified = true },
  { id = 3, name = "/work/selected.lua", active = true, modified = true },
  { id = 4, name = "/work/four.lua", visible = true },
  { id = 5, name = "/work/five.lua", modified = true },
  { id = 6, name = "/work/six.lua" },
  { id = 7, name = "/work/seven.lua" },
}
local tabs = {
  { id = 1, label = "one", active = true },
  { id = 2, label = "two" },
}

local function segment_states(rendered)
  return h.set(rendered.segments, "state")
end

h.test("common renderer escapes status syntax and measures display cells", function()
  local result = common.result({
    common.segment("UXChromeFixture", " 50% 界 ", "fixture"),
    common.control("%="),
  })
  h.contains(result.text, "50%%")
  h.contains(result.text, "%#UXChromeFixture#")
  h.equal(result.width, vim.fn.strdisplaywidth(" 50% 界 "))
end)

h.test("tabline covers active visible inactive modified and native-tab states", function()
  local rendered = tabline.render({ buffers = buffers, tabs = tabs, columns = 180 })
  h.equal(rendered, tabline.render({ buffers = buffers, tabs = tabs, columns = 180 }),
    "wide tabline render is not deterministic")
  local states = segment_states(rendered)
  for _, state in ipairs({
    "active_modified", "visible_modified", "visible", "inactive", "inactive_modified",
    "native_tab_active", "native_tab_inactive", "fill",
  }) do
    h.truthy(states[state], "wide tabline omitted " .. state)
  end
  h.equal(rendered.hidden_left, 0)
  h.equal(rendered.hidden_right, 0)
  h.truthy(rendered.width <= 180, "wide tabline exceeded its available cells")
end)

h.test("tabline remains deterministic at medium and narrow widths", function()
  local medium = tabline.render({ buffers = buffers, tabs = tabs, columns = 100 })
  h.equal(medium, tabline.render({ buffers = buffers, tabs = tabs, columns = 100 }))
  h.truthy(medium.range.first <= 3 and medium.range.last >= 3,
    "medium tabline dropped the active buffer")
  h.truthy(medium.width <= 100, "medium tabline exceeded its available cells")

  local narrow = tabline.render({ buffers = buffers, tabs = tabs, columns = 38 })
  h.equal(narrow, tabline.render({ buffers = buffers, tabs = tabs, columns = 38 }))
  h.truthy(narrow.range.first <= 3 and narrow.range.last >= 3,
    "narrow tabline dropped the active buffer")
  h.truthy(narrow.hidden_left + narrow.hidden_right > 0,
    "narrow tabline did not expose overflow")
  h.truthy(segment_states(narrow).overflow, "narrow tabline omitted its overflow state")
  h.truthy(narrow.width <= 38, "narrow tabline exceeded its available cells")

  for _, columns in ipairs({ 100, 72, 40, 12, 1 }) do
    local bounded = tabline.render({ buffers = buffers, tabs = tabs, columns = columns })
    h.equal(bounded, tabline.render({ buffers = buffers, tabs = tabs, columns = columns }))
    h.truthy(bounded.width <= columns,
      ("tabline exceeded the %d-cell fixture width"):format(columns))
  end
end)

h.test("tabline exposes a stable empty state", function()
  local rendered = tabline.render({ buffers = {}, tabs = {}, columns = 40 })
  h.truthy(segment_states(rendered).empty)
  h.contains(rendered.text, "[No buffers]")
  h.truthy(tabline.render({ buffers = {}, tabs = {}, columns = 12 }).width <= 12)
  h.truthy(tabline.render({ buffers = {}, tabs = {}, columns = 1 }).width <= 1)
end)

local status_context = {
  active = true,
  column = 9,
  encoding = "utf-8",
  fileformat = "unix",
  filetype = "lua",
  line = 25,
  mode = "n",
  modified = true,
  name = "/workspace/lua/ux_chrome/init.lua",
  readonly = true,
  total_lines = 100,
  width = 120,
}

h.test("statusline covers every public mode family", function()
  local modes = {
    n = "normal", noV = "normal", ["no\22"] = "normal", nt = "normal", ntT = "normal",
    i = "insert",
    v = "visual", vs = "visual", Vs = "visual", ["\22s"] = "visual",
    V = "visual",
    ["\22"] = "visual",
    R = "replace", Rx = "replace", Rvc = "replace", Rvx = "replace",
    c = "command", cr = "command", cvr = "command", ["!"] = "command",
    t = "terminal",
  }
  for mode, family in pairs(modes) do
    local context = vim.tbl_extend("force", status_context, { mode = mode })
    local rendered = statusline.render(context)
    h.equal(rendered.mode, family, "wrong statusline family for mode " .. vim.inspect(mode))
    h.truthy(segment_states(rendered)[family], "statusline omitted mode segment " .. family)
    h.equal(rendered, statusline.render(context), "statusline mode render is not deterministic")
  end
end)

h.test("statusline renders modified readonly progress and ruler states", function()
  local rendered = statusline.render(status_context)
  local states = segment_states(rendered)
  for _, state in ipairs({ "filename", "modified", "readonly", "progress", "ruler" }) do
    h.truthy(states[state], "statusline omitted " .. state)
  end
  h.contains(rendered.text, "25%%")
  h.contains(rendered.text, "25:9")
  local custom_separator = statusline.render(status_context, {
    ["statusline.section_separator_right"] = "R",
  })
  h.truthy(segment_states(custom_separator).right_section_separator)
  h.contains(custom_separator.text, "R")
  h.truthy(rendered.width <= status_context.width, "statusline exceeded its available cells")
end)

h.test("statusline narrow priority dropping preserves progress and ruler", function()
  local context = vim.tbl_extend("force", status_context, {
    name = "/workspace/a-very-long-file-name-that-must-truncate.lua",
    width = 28,
  })
  local rendered = statusline.render(context)
  local right_states = h.set(rendered.right_items, "state")
  h.equal(#rendered.right_items, 2, "narrow statusline retained low-priority metadata")
  h.truthy(right_states.progress and right_states.ruler,
    "narrow statusline dropped a high-priority position indicator")
  h.truthy(not right_states.encoding and not right_states.fileformat and not right_states.filetype,
    "narrow statusline retained low-priority metadata")
  h.truthy(rendered.width <= context.width, "narrow statusline exceeded its available cells")
  for _, width in ipairs({ 40, 12, 1 }) do
    local bounded = statusline.render(vim.tbl_extend("force", context, { width = width }))
    h.truthy(bounded.width <= width,
      ("statusline exceeded the %d-cell fixture width"):format(width))
  end
end)

h.test("inactive statusline is quiet and deterministic", function()
  local context = vim.tbl_extend("force", status_context, { active = false, width = 34 })
  local rendered = statusline.render(context)
  h.equal(rendered.mode, "inactive")
  h.truthy(not segment_states(rendered).normal, "inactive statusline retained an active mode")
  h.truthy(segment_states(rendered).inactive)
  h.truthy(segment_states(rendered).inactive_ruler)
  h.truthy(rendered.width <= context.width, "inactive statusline exceeded its available cells")
end)

h.test("winbar renders bounded active and inactive breadcrumbs", function()
  local active = winbar.render({
    active = true,
    modified = true,
    name = "/one/two/three/four/five/file.lua",
    width = 80,
  }, { ["winbar.max_depth"] = 4 })
  local states = segment_states(active)
  h.equal(active.hidden, 2)
  h.truthy(states.overflow and states.parent and states.current and states.modified)
  h.truthy(active.width <= 80)
  h.equal(active, winbar.render({
    active = true,
    modified = true,
    name = "/one/two/three/four/five/file.lua",
    width = 80,
  }, { ["winbar.max_depth"] = 4 }))

  local inactive = winbar.render({ active = false, name = "/one/two/file.lua", width = 24 })
  for _, segment in ipairs(inactive.segments) do
    if segment.state == "current" then h.equal(segment.group, "UXChromeWinbarInactive") end
  end
  h.truthy(inactive.width <= 24)
  local pathological = winbar.render({
    active = true,
    modified = true,
    name = "/a-very-long-parent/a-second-very-long-parent/a-third-parent/file-name.lua",
    width = 12,
  })
  h.truthy(pathological.width <= 12, "pathological winbar exceeded twelve cells")
  h.truthy(winbar.render({ active = true, name = "/long-parent/file.lua", width = 1 }).width <= 1)
end)

h.test("statuscolumn distinguishes current relative absolute and virtual rows", function()
  h.equal(statuscolumn.number({ lnum = 8, relnum = 0, numberwidth = 4, relativenumber = true }),
    "%#UXChromeLineNumberCurrent#   8")
  h.equal(statuscolumn.number({ lnum = 8, relnum = 3, numberwidth = 4, relativenumber = true }),
    "%#UXChromeLineNumber#   3")
  h.equal(statuscolumn.number({ lnum = 8, relnum = 3, numberwidth = 4, number = true }),
    "%#UXChromeLineNumber#   8")
  h.equal(statuscolumn.number({ lnum = 8, relnum = 0, virtnum = 1 }), "")
  h.equal(statuscolumn.number({ lnum = 8, relnum = 0, virtnum = -1 }), "")
  h.equal(statuscolumn.number({ lnum = 8, number = false, relativenumber = false }), "")
  local expression = statuscolumn.expression({ ["gutter.separator"] = "%" })
  h.contains(expression, "%C")
  h.contains(expression, "%s")
  h.contains(expression, "ux_chrome'.statuscolumn")
  h.contains(expression, "%%")
end)

h.test("the statuscolumn expression renders as statusline syntax", function()
  -- Regression: %{...} prints its result literally, so the "%#Group#" prefix
  -- returned by the statuscolumn callback leaked into the gutter as text and the
  -- column rendered many cells too wide. Only %{%...%} is re-parsed as syntax.
  -- The callback is stubbed so this stays a pure renderer test with no runtime.
  local restore = package.loaded.ux_chrome
  package.loaded.ux_chrome = {
    statuscolumn = function()
      return statuscolumn.number({ lnum = 105, relnum = 5, numberwidth = 4, number = true })
    end,
  }

  -- The groups must exist or nvim_eval_statusline reports the StatusLine
  -- fallback for every span and the assertion below proves nothing.
  for _, group in ipairs({
    "UXChromeGutterFold", "UXChromeGutterSign",
    "UXChromeLineNumber", "UXChromeGutterSeparator",
  }) do
    vim.api.nvim_set_hl(0, group, { fg = "#8AADF4" })
  end

  local expression = statuscolumn.expression({ ["gutter.separator"] = "|" })
  -- maxwidth pins the %= alignment cell so the assertion is about parsing, not padding.
  local ok, rendered = pcall(vim.api.nvim_eval_statusline, expression,
    { highlights = true, maxwidth = 5 })
  package.loaded.ux_chrome = restore
  h.truthy(ok, "the statuscolumn expression failed to evaluate: " .. tostring(rendered))

  h.equal(rendered.str, " 105|", "the statuscolumn did not render its literal cells")
  h.equal(rendered.width, 5, "the statuscolumn rendered the wrong cell width")
  h.truthy(not rendered.str:find("%#", 1, true),
    "a highlight escape leaked into the rendered statuscolumn as text")
  local groups = {}
  for _, item in ipairs(rendered.highlights or {}) do groups[item.group] = true end
  h.truthy(groups.UXChromeLineNumber,
    "the line-number highlight was never applied through the statuscolumn")
  h.truthy(groups.UXChromeGutterSeparator,
    "the gutter separator highlight was never applied")
end)

h.test("foldtext is sanitized counted and cell bounded", function()
  local rendered = foldtext.render({
    text = "  function example()\nignored  ",
    start = 3,
    finish = 12,
    width = 60,
  })
  h.truthy(not rendered:find("\n", 1, true), "foldtext retained a newline")
  h.contains(rendered, "10 lines")
  h.truthy(vim.fn.strdisplaywidth(rendered) <= 60)
  h.truthy(vim.fn.strdisplaywidth(foldtext.render({
    text = "function with a deliberately long folded heading",
    start = 1,
    finish = 30,
    width = 28,
  })) <= 28, "narrow foldtext exceeded its available cells")
  h.contains(foldtext.render({ text = "", start = 1, finish = 1 }), "[empty fold]")
end)

h.test("scrollbar computes proportional geometry and tears rails down exactly", function()
  local valid_windows = { [10] = true }
  local valid_buffers = { [20] = true }
  local observed = { closes = {}, deletes = {}, extmarks = {}, line_writes = 0 }
  local next_buffer, next_window = 21, 30
  local api = {}
  function api.nvim_win_is_valid(win) return valid_windows[win] == true end
  function api.nvim_win_get_config() return { relative = "" } end
  function api.nvim_win_get_buf(win) return win == 10 and 20 or next_buffer end
  function api.nvim_buf_is_valid(buf) return valid_buffers[buf] == true end
  function api.nvim_get_option_value(name)
    if name == "buftype" then return "" end
    error("unexpected option read " .. tostring(name))
  end
  function api.nvim_buf_line_count(buf) h.equal(buf, 20); return 100 end
  function api.nvim_win_call(win) h.equal(win, 10); return { 11, 30 } end
  function api.nvim_win_get_height(win) h.equal(win, 10); return 20 end
  function api.nvim_win_get_width(win) h.equal(win, 10); return 80 end
  function api.nvim_win_get_cursor(win) h.equal(win, 10); return { 50, 0 } end
  function api.nvim_create_buf()
    valid_buffers[next_buffer] = true
    return next_buffer
  end
  function api.nvim_set_option_value() end
  function api.nvim_open_win(buf, enter, config)
    h.equal(buf, next_buffer)
    h.equal(enter, false)
    h.equal(config.height, 20)
    h.equal(config.col, 80)
    valid_windows[next_window] = true
    return next_window
  end
  function api.nvim_create_namespace() return 77 end
  function api.nvim_buf_set_lines(buf, first, last, strict, lines)
    h.equal(buf, next_buffer)
    h.equal({ first, last, strict }, { 0, -1, false })
    observed.line_writes = observed.line_writes + 1
    observed.lines = vim.deepcopy(lines)
  end
  function api.nvim_buf_clear_namespace() end
  function api.nvim_buf_set_extmark(buf, namespace, row, column, opts)
    observed.extmarks[#observed.extmarks + 1] = {
      buf = buf, namespace = namespace, row = row, column = column, opts = vim.deepcopy(opts),
    }
  end
  function api.nvim_win_set_config() end
  function api.nvim_win_close(win)
    observed.closes[#observed.closes + 1] = win
    valid_windows[win] = false
  end
  function api.nvim_buf_delete(buf)
    observed.deletes[#observed.deletes + 1] = buf
    valid_buffers[buf] = false
  end

  local values = {
    ["scrollbar.enabled"] = true,
    ["scrollbar.min_lines"] = 40,
    ["scrollbar.show_inactive"] = false,
    ["scrollbar.thumb_glyph"] = "T",
    ["scrollbar.thumb_size"] = "proportional",
    ["scrollbar.track_glyph"] = ".",
  }
  local scrollbar = Scrollbar.new(api)
  h.truthy(scrollbar:refresh({ 10 }, values, 10))
  h.equal(#scrollbar:state(), 1)
  h.equal(#observed.lines, 20)
  h.equal(observed.lines[1], ".")
  h.equal(observed.lines[3], "T")
  h.equal(observed.lines[6], "T")
  h.equal(observed.lines[7], ".")
  h.equal(#observed.extmarks, 5)
  h.equal(observed.extmarks[1].row, 2)
  h.equal(observed.extmarks[4].row, 5)
  h.equal(observed.extmarks[5].row, 9)
  h.equal(observed.extmarks[5].opts.line_hl_group, "UXChromeScrollbarMarker")

  h.truthy(scrollbar:refresh({ 10 }, values, 10))
  h.equal(observed.line_writes, 1, "unchanged scrollbar geometry redrew its rail")
  values["scrollbar.enabled"] = false
  h.truthy(scrollbar:refresh({ 10 }, values, 10))
  h.equal(scrollbar:state(), {})
  h.equal(observed.closes, { 30 })
  h.equal(observed.deletes, { 21 })
  scrollbar:stop()
end)

h.finish()
