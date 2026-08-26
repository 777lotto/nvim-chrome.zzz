local default_values = require("ux_chrome.defaults")
local util = require("ux_chrome.util")

local M = {}

local COMPONENTS = {
  { id = "buffer_tabs", label = "Buffer Tabs and Native Tabline" },
  { id = "statusline", label = "Statusline" },
  { id = "winbar", label = "Winbar and Breadcrumbs" },
  { id = "gutter", label = "Statuscolumn, Line Numbers, Signs, and Folds" },
  { id = "window_treatment", label = "Window Treatment and Split Separators" },
  { id = "scrollbar", label = "Scrollbar and Minimap Presentation" },
}

local BOOLEAN_FIELDS = {
  { id = "bold", label = "Bold", field = "bold" },
  { id = "italic", label = "Italic", field = "italic" },
  { id = "underline", label = "Underline", field = "underline" },
  { id = "undercurl", label = "Undercurl", field = "undercurl" },
  { id = "underdouble", label = "Double Underline", field = "underdouble" },
  { id = "underdotted", label = "Dotted Underline", field = "underdotted" },
  { id = "underdashed", label = "Dashed Underline", field = "underdashed" },
  { id = "strikethrough", label = "Strikethrough", field = "strikethrough" },
  { id = "reverse", label = "Reverse", field = "reverse" },
  { id = "standout", label = "Standout", field = "standout" },
  { id = "nocombine", label = "No Combine", field = "nocombine" },
  { id = "overline", label = "Overline", field = "overline" },
}

local function copy(value)
  return util.deepcopy(value)
end

local function fixture_id(component_id)
  return "ux.chrome." .. component_id .. ".v1"
end

local function assert_color(value, path)
  value = value or { kind = "unset" }
  if type(value) ~= "table" then
    error(path .. " must be a tagged color")
  end
  if value.kind == "unset" then
    return { kind = "unset" }, { kind = "unset" }
  end
  if value.kind == "rgb" then
    if type(value.value) ~= "string" or not value.value:match("^#%x%x%x%x%x%x$") then
      error(path .. " must contain a #RRGGBB value")
    end
    local normalized = { kind = "rgb", value = value.value:upper() }
    return normalized, copy(normalized)
  end
  if value.kind == "token" then
    if type(value.id) ~= "string" or value.id == "" then
      error(path .. " token requires an ID")
    end
    if type(value.fallback) ~= "string" or not value.fallback:match("^#%x%x%x%x%x%x$") then
      error(path .. " token requires a concrete #RRGGBB fallback")
    end
    return {
      kind = "token",
      id = value.id,
    }, {
      kind = "rgb",
      value = value.fallback:upper(),
    }
  end
  error(path .. " uses an unsupported color kind")
end

local function assert_link(value, path)
  value = value or { kind = "unset" }
  if type(value) == "string" and value ~= "" then
    return { kind = "group", value = value }
  end
  if type(value) ~= "table" then
    error(path .. " must be a tagged highlight link")
  end
  if value.kind == "unset" then return { kind = "unset" } end
  if value.kind == "group" and type(value.value) == "string" and value.value ~= "" then
    return { kind = "group", value = value.value }
  end
  error(path .. " uses an unsupported highlight-link value")
end

local function property(id, label, field, type_spec, value, fallback)
  return {
    id = id,
    label = label,
    field = field,
    type = copy(type_spec),
    declared = { source = "literal", value = copy(value) },
    semantic_fallback = copy(fallback),
    reset = "declared",
    persist = true,
    apply = { mode = "immediate" },
  }
end

local function highlight_properties(style)
  local properties = {}
  local link = assert_link(style.link, style.group .. ".link")
  properties[#properties + 1] = property(
    "link",
    "Link",
    "link",
    { kind = "highlight_link", allow_unset = true },
    link,
    link
  )

  for _, field in ipairs({
    { id = "foreground", label = "Foreground", field = "fg", value = style.fg },
    { id = "background", label = "Background", field = "bg", value = style.bg },
    { id = "special", label = "Special", field = "sp", value = style.sp },
  }) do
    local declared, fallback = assert_color(field.value, style.group .. "." .. field.field)
    properties[#properties + 1] = property(
      field.id,
      field.label,
      field.field,
      { kind = "color", allow_unset = true },
      declared,
      fallback
    )
  end

  local attributes = style.attrs or {}
  if type(attributes) ~= "table" then error(style.group .. ".attrs must be a table") end
  for _, field in ipairs(BOOLEAN_FIELDS) do
    local enabled = attributes[field.field] == true
    properties[#properties + 1] = property(
      field.id,
      field.label,
      field.field,
      { kind = "boolean" },
      enabled,
      enabled
    )
  end

  local blend = style.blend
  if blend == nil then blend = attributes.blend end
  if blend == nil then blend = 0 end
  properties[#properties + 1] = property(
    "blend",
    "Blend",
    "blend",
    { kind = "integer", min = 0, max = 100 },
    blend,
    blend
  )
  return properties
end

local function highlight_state(style)
  if type(style.id) ~= "string" or style.id == "" then error("highlight style requires an ID") end
  if type(style.group) ~= "string" or not style.group:match("^UXChrome") then
    error("Chrome highlight claims must use the UXChrome namespace")
  end
  return {
    id = style.id,
    label = style.label or style.id,
    target = {
      kind = "highlight",
      group = style.group,
      management = "managed",
    },
    properties = highlight_properties(style),
  }
end

local function structural_state(spec)
  if type(spec.id) ~= "string" or spec.id == "" then error("structural style requires an ID") end
  if type(spec.key) ~= "string" or spec.key == "" then error("structural style requires a key") end
  return {
    id = "setting_" .. spec.id,
    label = spec.label or spec.id,
    target = {
      kind = "structural",
      adapter_id = "ux_chrome",
      key = spec.key,
      management = "managed",
    },
    properties = {
      {
        id = "value",
        label = "Value",
        field = "value",
        type = copy(spec.type),
        declared = { source = "literal", value = copy(spec.default) },
        semantic_fallback = copy(spec.default),
        reset = "declared",
        persist = true,
        apply = { mode = "rerender" },
      },
    },
  }
end

function M.build(values)
  values = values or default_values
  if type(values) ~= "table" then error("ux_chrome.manifest.build() expects a defaults table") end
  if type(values.highlights) ~= "table" then error("Chrome defaults.highlights must be a list") end
  if type(values.structural) ~= "table" then error("Chrome defaults.structural must be a list") end

  local components = {}
  local by_id = {}
  local state_ids = {}
  for _, descriptor in ipairs(COMPONENTS) do
    local component = {
      id = descriptor.id,
      label = descriptor.label,
      preview = { fixture_id = fixture_id(descriptor.id) },
      states = {},
    }
    components[#components + 1] = component
    by_id[descriptor.id] = component
    state_ids[descriptor.id] = {}
  end

  local function append(component_id, state)
    local component = by_id[component_id]
    if not component then error("unknown Chrome component: " .. tostring(component_id)) end
    if state_ids[component_id][state.id] then
      error(("duplicate state ID %s/%s"):format(component_id, state.id))
    end
    state_ids[component_id][state.id] = true
    component.states[#component.states + 1] = state
  end

  for _, style in ipairs(values.highlights) do
    if type(style) ~= "table" then error("Chrome highlight styles must be tables") end
    append(style.component, highlight_state(style))
  end
  for _, spec in ipairs(values.structural) do
    if type(spec) ~= "table" then error("Chrome structural styles must be tables") end
    append(spec.component, structural_state(spec))
  end
  for _, component in ipairs(components) do
    if #component.states == 0 then error("Chrome component has no states: " .. component.id) end
  end

  return {
    schema_version = 1,
    plugin = {
      id = "ux.chrome",
      label = "Chrome",
      version = values.version or "0.1.0",
    },
    components = components,
  }
end

M.manifest = M.build

return M
