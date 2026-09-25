local M = {}

M.version = "0.1.0-dev"

M.ownership = {
  tabline = "auto",
  statusline = "auto",
  winbar = "auto",
  statuscolumn = "auto",
  windows = "auto",
  scrollbar = "auto",
}

local function glyph(default, max_cells)
  return { kind = "glyph", max_cells = max_cells or 4 }, default
end

local function fillchar(default)
  return {
    kind = "glyph",
    min_length = 1,
    max_length = 1,
    min_cells = 1,
    max_cells = 1,
  }, default
end

local function boolean(default)
  return { kind = "boolean" }, default
end

local function integer(default, minimum, maximum)
  return { kind = "integer", min = minimum, max = maximum }, default
end

local function enum(default, values)
  local options = {}
  for _, value in ipairs(values) do
    options[#options + 1] = { id = value[1], label = value[2] }
  end
  return { kind = "enum", options = options }, default
end

local function structural(component, id, label, key, type_spec, default)
  return {
    component = component,
    id = id,
    label = label,
    key = key,
    type = type_spec,
    default = default,
  }
end

local structural_specs = {}
local function add(component, id, label, key, type_spec, default)
  structural_specs[#structural_specs + 1] = structural(component, id, label, key, type_spec, default)
end

do
  local spec, value = enum("slant", {
    { "slant", "Slant" },
    { "slope", "Slope" },
    { "thin", "Thin" },
    { "block", "Block" },
    { "custom", "Custom glyphs" },
  })
  add("buffer_tabs", "separator_style", "Separator Style", "buffer_tabs.separator_style", spec, value)
  spec, value = glyph("")
  add("buffer_tabs", "separator_left", "Custom Left Separator", "buffer_tabs.separator_left", spec, value)
  spec, value = glyph("")
  add("buffer_tabs", "separator_right", "Custom Right Separator", "buffer_tabs.separator_right", spec, value)
  spec, value = glyph("●", 2)
  add("buffer_tabs", "modified_icon", "Modified Icon", "buffer_tabs.modified_icon", spec, value)
  spec, value = glyph("×", 2)
  add("buffer_tabs", "close_icon", "Close Icon", "buffer_tabs.close_icon", spec, value)
  spec, value = glyph("")
  add("buffer_tabs", "left_trunc_marker", "Left Overflow Marker", "buffer_tabs.left_trunc_marker", spec, value)
  spec, value = glyph("")
  add("buffer_tabs", "right_trunc_marker", "Right Overflow Marker", "buffer_tabs.right_trunc_marker", spec, value)
  spec, value = integer(18, 4, 80)
  add("buffer_tabs", "max_name_length", "Maximum Buffer Name", "buffer_tabs.max_name_length", spec, value)
  spec, value = boolean(true)
  add("buffer_tabs", "show_close", "Show Active Close Icon", "buffer_tabs.show_close", spec, value)
  spec, value = boolean(true)
  add("buffer_tabs", "show_tabpages", "Show Native Tab Pages", "buffer_tabs.show_tabpages", spec, value)
  spec, value = boolean(true)
  add("buffer_tabs", "always_show", "Always Show Tabline", "buffer_tabs.always_show", spec, value)

  spec, value = glyph("")
  add("statusline", "section_separator_left", "Left Section Separator", "statusline.section_separator_left", spec, value)
  spec, value = glyph("")
  add("statusline", "section_separator_right", "Right Section Separator", "statusline.section_separator_right", spec, value)
  spec, value = glyph("│", 2)
  add("statusline", "component_separator", "Component Separator", "statusline.component_separator", spec, value)
  for _, item in ipairs({
    { "show_mode", "Show Mode", "statusline.show_mode" },
    { "show_drawer", "Show Output Drawer", "statusline.show_drawer" },
    { "show_encoding", "Show Encoding", "statusline.show_encoding" },
    { "show_filetype", "Show Filetype", "statusline.show_filetype" },
    { "show_ruler", "Show Ruler", "statusline.show_ruler" },
    { "show_progress", "Show Progress", "statusline.show_progress" },
  }) do
    spec, value = boolean(true)
    add("statusline", item[1], item[2], item[3], spec, value)
  end
  spec, value = enum("window", { { "window", "Per window" }, { "global", "Global" } })
  add("statusline", "placement", "Statusline Placement", "statusline.placement", spec, value)

  spec, value = glyph(" › ", 4)
  add("winbar", "separator", "Breadcrumb Separator", "winbar.separator", spec, value)
  spec, value = integer(4, 1, 20)
  add("winbar", "max_depth", "Maximum Breadcrumb Depth", "winbar.max_depth", spec, value)

  spec, value = glyph("│", 2)
  add("gutter", "separator", "Gutter Separator", "gutter.separator", spec, value)
  spec, value = fillchar("")
  add("gutter", "fold_open", "Open Fold Glyph", "gutter.fold_open", spec, value)
  spec, value = fillchar("")
  add("gutter", "fold_closed", "Closed Fold Glyph", "gutter.fold_closed", spec, value)
  spec, value = fillchar(" ")
  add("gutter", "fold_separator", "Fold Continuation Glyph", "gutter.fold_separator", spec, value)

  spec, value = fillchar("│")
  add("window_treatment", "split_vertical", "Vertical Split Glyph", "windows.split_vertical", spec, value)
  spec, value = fillchar("─")
  add("window_treatment", "split_horizontal", "Horizontal Split Glyph", "windows.split_horizontal", spec, value)
  spec, value = enum("dim", { { "dim", "Dim inactive windows" }, { "inherit", "Inherit core canvas" } })
  add("window_treatment", "inactive_style", "Inactive Window Treatment", "windows.inactive_style", spec, value)

  spec, value = boolean(true)
  add("scrollbar", "enabled", "Show Scrollbar", "scrollbar.enabled", spec, value)
  spec, value = glyph("▐", 1)
  add("scrollbar", "thumb_glyph", "Scrollbar Thumb", "scrollbar.thumb_glyph", spec, value)
  spec, value = glyph(" ", 1)
  add("scrollbar", "track_glyph", "Scrollbar Track", "scrollbar.track_glyph", spec, value)
  spec, value = integer(40, 1, 1000000)
  add("scrollbar", "min_lines", "Minimum Buffer Lines", "scrollbar.min_lines", spec, value)
  spec, value = enum("proportional", { { "proportional", "Proportional" }, { "single", "Single cell" } })
  add("scrollbar", "thumb_size", "Scrollbar Thumb Size", "scrollbar.thumb_size", spec, value)
  spec, value = boolean(false)
  add("scrollbar", "show_inactive", "Show Inactive Scrollbars", "scrollbar.show_inactive", spec, value)
end

M.structural = structural_specs
M.structural_defaults = {}
for _, spec in ipairs(structural_specs) do M.structural_defaults[spec.key] = spec.default end

local palette = {
  base = "#24273A",
  mantle = "#1E2030",
  crust = "#181926",
  surface0 = "#363A4F",
  text = "#CAD3F5",
  overlay0 = "#6E738D",
  blue = "#8AADF4",
  lavender = "#B7BDF8",
  sky = "#91D7E3",
  teal = "#8BD5CA",
  green = "#A6DA95",
  yellow = "#EED49F",
  red = "#ED8796",
  mauve = "#C6A0F6",
  peach = "#F5A97F",
}

local function token(name)
  return {
    kind = "token",
    id = "ux.foundation.palette." .. name,
    fallback = palette[name],
  }
end

local function style(component, id, label, group, fg, bg, attrs)
  return {
    component = component,
    id = id,
    label = label,
    group = group,
    fg = fg,
    bg = bg,
    attrs = attrs or {},
  }
end

M.highlights = {
  style("buffer_tabs", "fill", "Fill", "UXChromeTabFill", token("overlay0"), token("crust")),
  style("buffer_tabs", "active", "Active Selected", "UXChromeTabActive", token("text"), token("base"), { bold = true, italic = true }),
  style("buffer_tabs", "active_modified", "Active Modified", "UXChromeTabActiveModified", token("green"), token("base"), { bold = true, italic = true }),
  style("buffer_tabs", "visible", "Visible", "UXChromeTabVisible", token("text"), token("surface0")),
  style("buffer_tabs", "visible_modified", "Visible Modified", "UXChromeTabVisibleModified", token("yellow"), token("surface0")),
  style("buffer_tabs", "inactive", "Inactive", "UXChromeTabInactive", token("overlay0"), token("mantle")),
  style("buffer_tabs", "inactive_modified", "Inactive Modified", "UXChromeTabInactiveModified", token("yellow"), token("mantle")),
  style("buffer_tabs", "separator_active", "Active Separator", "UXChromeTabSeparatorActive", token("base"), token("crust")),
  style("buffer_tabs", "separator_visible", "Visible Separator", "UXChromeTabSeparatorVisible", token("surface0"), token("crust")),
  style("buffer_tabs", "separator_inactive", "Inactive Separator", "UXChromeTabSeparatorInactive", token("mantle"), token("crust")),
  style("buffer_tabs", "overflow", "Overflow", "UXChromeTabOverflow", token("yellow"), token("crust"), { bold = true }),
  style("buffer_tabs", "native_tab_active", "Active Native Tab", "UXChromeNativeTabActive", token("base"), token("lavender"), { bold = true }),
  style("buffer_tabs", "native_tab_inactive", "Inactive Native Tab", "UXChromeNativeTabInactive", token("lavender"), token("surface0")),

  style("statusline", "mode_normal", "Normal Mode", "UXChromeStatusModeNormal", token("base"), token("blue"), { bold = true }),
  style("statusline", "mode_insert", "Insert Mode", "UXChromeStatusModeInsert", token("base"), token("green"), { bold = true }),
  style("statusline", "mode_visual", "Visual Mode", "UXChromeStatusModeVisual", token("base"), token("mauve"), { bold = true }),
  style("statusline", "mode_replace", "Replace Mode", "UXChromeStatusModeReplace", token("base"), token("red"), { bold = true }),
  style("statusline", "mode_command", "Command Mode", "UXChromeStatusModeCommand", token("base"), token("peach"), { bold = true }),
  style("statusline", "mode_terminal", "Terminal Mode", "UXChromeStatusModeTerminal", token("base"), token("green"), { bold = true }),
  style("statusline", "separator_normal", "Normal Separator", "UXChromeStatusSeparatorNormal", token("blue"), token("surface0")),
  style("statusline", "separator_insert", "Insert Separator", "UXChromeStatusSeparatorInsert", token("green"), token("surface0")),
  style("statusline", "separator_visual", "Visual Separator", "UXChromeStatusSeparatorVisual", token("mauve"), token("surface0")),
  style("statusline", "separator_replace", "Replace Separator", "UXChromeStatusSeparatorReplace", token("red"), token("surface0")),
  style("statusline", "separator_command", "Command Separator", "UXChromeStatusSeparatorCommand", token("peach"), token("surface0")),
  style("statusline", "separator_terminal", "Terminal Separator", "UXChromeStatusSeparatorTerminal", token("green"), token("surface0")),
  style("statusline", "primary", "Primary", "UXChromeStatusPrimary", token("text"), token("surface0")),
  style("statusline", "body", "Body", "UXChromeStatusBody", token("text"), token("base")),
  style("statusline", "inactive", "Inactive", "UXChromeStatusInactive", token("overlay0"), token("mantle")),
  style("statusline", "modified", "Modified", "UXChromeStatusModified", token("yellow"), token("surface0"), { bold = true }),
  style("statusline", "readonly", "Read-only", "UXChromeStatusReadonly", token("red"), token("surface0"), { bold = true }),
  style("statusline", "info", "Information", "UXChromeStatusInfo", token("lavender"), token("base")),
  style("statusline", "progress", "Progress", "UXChromeStatusProgress", token("sky"), token("base"), { bold = true }),

  style("winbar", "active", "Active", "UXChromeWinbarActive", token("text"), token("base")),
  style("winbar", "inactive", "Inactive", "UXChromeWinbarInactive", token("overlay0"), token("mantle")),
  style("winbar", "separator", "Breadcrumb Separator", "UXChromeWinbarSeparator", token("overlay0"), token("base")),
  style("winbar", "current", "Current Breadcrumb", "UXChromeWinbarCurrent", token("blue"), token("base"), { bold = true }),
  style("winbar", "modified", "Modified", "UXChromeWinbarModified", token("yellow"), token("base"), { bold = true }),

  style("gutter", "line_number", "Line Number", "UXChromeLineNumber", token("overlay0"), token("base")),
  style("gutter", "line_number_current", "Current Line Number", "UXChromeLineNumberCurrent", token("lavender"), token("base"), { bold = true }),
  style("gutter", "sign", "Sign Column", "UXChromeGutterSign", token("text"), token("base")),
  style("gutter", "fold", "Fold Column", "UXChromeGutterFold", token("overlay0"), token("base")),
  style("gutter", "separator", "Gutter Separator", "UXChromeGutterSeparator", token("surface0"), token("base")),
  style("gutter", "folded", "Fold Text", "UXChromeFolded", token("overlay0"), token("mantle"), { italic = true }),

  style("window_treatment", "active", "Active Window", "UXChromeWindowActive", token("text"), token("base")),
  style("window_treatment", "inactive", "Inactive Window", "UXChromeWindowInactive", token("overlay0"), token("mantle")),
  style("window_treatment", "split_active", "Active Split", "UXChromeSplitActive", token("blue"), token("base")),
  style("window_treatment", "split_inactive", "Inactive Split", "UXChromeSplitInactive", token("surface0"), token("mantle")),

  style("scrollbar", "track", "Scrollbar Track", "UXChromeScrollbarTrack", token("surface0"), { kind = "unset" }),
  style("scrollbar", "thumb", "Scrollbar Thumb", "UXChromeScrollbarThumb", token("blue"), { kind = "unset" }, { bold = true }),
  style("scrollbar", "marker", "Minimap Marker", "UXChromeScrollbarMarker", token("lavender"), { kind = "unset" }),
}

return M
