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

local SCENARIOS = {
  buffer_tabs = {
    active = "active",
    inactive = "inactive",
    selected = "active",
    modified = "active_modified",
    overflow = "overflow",
  },
  statusline = {
    active = "mode_normal",
    inactive = "inactive",
    selected = "primary",
    modified = "modified",
    overflow = "progress",
  },
  winbar = {
    active = "active",
    inactive = "inactive",
    selected = "current",
    modified = "modified",
    overflow = "separator",
  },
  gutter = {
    active = "line_number_current",
    inactive = "line_number",
    selected = "sign",
    modified = "folded",
    overflow = "separator",
  },
  window_treatment = {
    active = "active",
    inactive = "inactive",
    selected = "split_active",
    modified = "split_inactive",
    overflow = "split_inactive",
  },
  scrollbar = {
    active = "thumb",
    inactive = "track",
    selected = "marker",
    modified = "marker",
    overflow = "marker",
  },
}

local CASE_ORDER = { "active", "inactive", "selected", "modified", "overflow" }

local function copy(value)
  return util.deepcopy(value)
end

local function fixture_id(component_id)
  return "ux.chrome." .. component_id .. ".v1"
end

local function property_id(component_id, state_id)
  return table.concat({ "ux.chrome", component_id, state_id, "foreground" }, "/")
end

local function index_defaults(values)
  local highlights = {}
  local structural = {}
  for _, component in ipairs(COMPONENTS) do
    highlights[component.id] = {}
    structural[component.id] = {}
  end
  for _, style in ipairs(values.highlights or {}) do
    if not highlights[style.component] then
      error("unknown Chrome fixture component: " .. tostring(style.component))
    end
    highlights[style.component][style.id] = style
  end
  for _, spec in ipairs(values.structural or {}) do
    if not structural[spec.component] then
      error("unknown Chrome fixture component: " .. tostring(spec.component))
    end
    structural[spec.component][#structural[spec.component] + 1] = spec
  end
  return highlights, structural
end

local function scenario(component_id, case_id, state_id, highlights)
  local style = highlights[component_id][state_id]
  if not style then
    error(("fixture scenario %s/%s names missing state %s"):format(component_id, case_id, state_id))
  end
  return {
    id = case_id,
    state_id = state_id,
    text = (" %s "):format(case_id:gsub("_", " ")),
    group = style.group,
    property_id = property_id(component_id, state_id),
  }
end

local function build_fixture(component, highlights, structural)
  local scenarios = {}
  local lines = {}
  for _, case_id in ipairs(CASE_ORDER) do
    local item = scenario(component.id, case_id, SCENARIOS[component.id][case_id], highlights)
    scenarios[#scenarios + 1] = item
    lines[#lines + 1] = {
      segments = {
        {
          text = item.text,
          state = item.id,
          hl_group = item.group,
          property_id = item.property_id,
        },
      },
    }
  end

  local highlight_states = {}
  for state_id, style in pairs(highlights[component.id]) do
    highlight_states[#highlight_states + 1] = {
      state_id = state_id,
      group = style.group,
      property_id = property_id(component.id, state_id),
    }
  end
  table.sort(highlight_states, function(left, right) return left.state_id < right.state_id end)

  local structural_states = {}
  for _, spec in ipairs(structural[component.id]) do
    structural_states[#structural_states + 1] = {
      state_id = "setting_" .. spec.id,
      key = spec.key,
      default = copy(spec.default),
      property_id = table.concat({ "ux.chrome", component.id, "setting_" .. spec.id, "value" }, "/"),
    }
  end
  table.sort(structural_states, function(left, right) return left.key < right.key end)

  return {
    id = fixture_id(component.id),
    schema_version = 1,
    plugin_id = "ux.chrome",
    component_id = component.id,
    label = component.label .. " · deterministic preview",
    adapter_id = "ux_chrome",
    editor = {
      lines = 24,
      termguicolors = true,
      layouts = {
        { id = "wide", columns = 100 },
        { id = "medium", columns = 72 },
        { id = "narrow", columns = 40 },
      },
    },
    scenarios = scenarios,
    lines = lines,
    expected = {
      cases = copy(CASE_ORDER),
      highlight_states = highlight_states,
      structural_states = structural_states,
      captures = { "rendered_lines", "highlight_spans", "structural_values" },
      normalize = { "buffer_ids", "window_ids", "absolute_paths" },
    },
    rollback = {
      required = true,
      snapshot = "exact_physical_state",
      apply_failure = "restore_last_valid_state",
      rerender_failure = "restore_last_valid_state",
      close_without_save = "restore_transaction_opening_state",
      history_on_failure = "unchanged",
      restore_order = { "adapter", "highlights" },
    },
  }
end

function M.all(values)
  values = values or default_values
  if type(values) ~= "table" then error("ux_chrome.fixtures.all() expects a defaults table") end
  local highlights, structural = index_defaults(values)
  local result = {}
  for _, component in ipairs(COMPONENTS) do
    result[#result + 1] = build_fixture(component, highlights, structural)
  end
  return result
end

function M.for_component(component_id, values)
  if type(component_id) ~= "string" then
    error("ux_chrome.fixtures.for_component() expects a component ID")
  end
  for _, fixture in ipairs(M.all(values)) do
    if fixture.component_id == component_id then return copy(fixture) end
  end
  return nil
end

function M.get(id, values)
  if type(id) ~= "string" then error("ux_chrome.fixtures.get() expects a fixture ID") end
  for _, fixture in ipairs(M.all(values)) do
    if fixture.id == id then return copy(fixture) end
  end
  return nil
end

function M.ids()
  local result = {}
  for _, component in ipairs(COMPONENTS) do result[#result + 1] = fixture_id(component.id) end
  return result
end

M.build = M.all
M.fixtures = M.all

return M
