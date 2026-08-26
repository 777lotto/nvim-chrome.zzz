local h = require("tests.helpers")

local function collect_ids(value, result, seen)
  result = result or {}
  seen = seen or {}
  if type(value) ~= "table" or seen[value] then return result end
  seen[value] = true
  if type(value.id) == "string" then result[value.id] = value end
  for _, item in pairs(value) do collect_ids(item, result, seen) end
  return result
end

local function contains_scalar(value, wanted, seen)
  if value == wanted then return true end
  if type(value) ~= "table" then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true
  for key, item in pairs(value) do
    if contains_scalar(key, wanted, seen) or contains_scalar(item, wanted, seen) then return true end
  end
  return false
end

h.test("ownership configuration normalizes aliases without mutating defaults", function()
  local config = require("ux_chrome.config")
  local defaults = require("ux_chrome.defaults")
  local before = vim.deepcopy(defaults.ownership)
  local normalized = config.normalize({
    ownership = {
      tabline = "takeover",
      statusline = "off",
      winbar = true,
      statuscolumn = false,
      splits = "external",
    },
  })
  h.equal(normalized.ownership.tabline, "ux")
  h.equal(normalized.ownership.statusline, "external")
  h.equal(normalized.ownership.winbar, "ux")
  h.equal(normalized.ownership.statuscolumn, "external")
  h.equal(normalized.ownership.windows, "external")
  h.equal(defaults.ownership, before, "config normalization mutated declared defaults")
  h.equal(config.normalize({}).ownership, before)
end)

h.test("configuration rejects malformed and unknown ownership", function()
  local config = require("ux_chrome.config")
  for _, invalid in ipairs({
    false,
    { foundation = false },
    { ownership = false },
    { ownership = { tabline = "sometimes" } },
    { ownership = { unknown_surface = "ux" } },
  }) do
    h.truthy(not pcall(config.normalize, invalid),
      "configuration accepted invalid input " .. vim.inspect(invalid))
  end
end)

h.test("declared targets are unique and UX-owned", function()
  local defaults = require("ux_chrome.defaults")
  local groups, keys = {}, {}
  for _, style in ipairs(defaults.highlights) do
    h.truthy(type(style.group) == "string" and vim.startswith(style.group, "UXChrome"),
      "Chrome declared a non-UX highlight target: " .. tostring(style.group))
    local folded = style.group:lower()
    h.truthy(not groups[folded], "duplicate case-insensitive highlight target " .. style.group)
    groups[folded] = true
    for _, third_party in ipairs({
      "BufferLine", "lualine", "NvimTree", "Oil", "Telescope", "Trouble", "ToggleTerm",
    }) do
      h.truthy(not style.group:find(third_party, 1, true),
        "Chrome claimed a third-party group: " .. style.group)
    end
  end
  for _, spec in ipairs(defaults.structural) do
    h.truthy(type(spec.key) == "string" and spec.key ~= "", "structural key is missing")
    h.truthy(not keys[spec.key], "duplicate structural key " .. spec.key)
    keys[spec.key] = true
    if vim.tbl_contains({
      "gutter.fold_open", "gutter.fold_closed", "gutter.fold_separator",
      "windows.split_vertical", "windows.split_horizontal",
    }, spec.key) then
      h.equal(spec.type.min_length, 1, spec.key .. " must be exactly one character")
      h.equal(spec.type.max_length, 1, spec.key .. " must be exactly one character")
      h.equal(spec.type.min_cells, 1, spec.key .. " must occupy exactly one cell")
      h.equal(spec.type.max_cells, 1, spec.key .. " must occupy exactly one cell")
    end
  end
  h.truthy(next(groups) ~= nil and next(keys) ~= nil, "Chrome declarations are empty")
end)

h.test("public facade exposes the complete documented API", function()
  local chrome = require("ux_chrome")
  for _, name in ipairs({
    "setup", "refresh", "reset", "teardown", "enable", "disable", "toggle", "state", "debug",
    "manifest", "fixtures", "tabline", "statusline", "winbar", "statuscolumn", "foldtext",
    "select_buffer", "move_buffer", "close_buffer", "health",
  }) do
    h.equal(type(chrome[name]), "function", "missing public ux_chrome." .. name .. "()")
  end
end)

h.test("manifest is deterministic callback-free schema-v1 data", function()
  local chrome = require("ux_chrome")
  local manifest = chrome.manifest()
  h.equal(manifest, chrome.manifest(), "manifest generation is not deterministic")
  h.assert_json(manifest, "ux.chrome.manifest")
  h.equal(manifest.schema_version, 1)
  h.equal(manifest.plugin.id, "ux.chrome")
  h.truthy(type(manifest.plugin.label) == "string" and manifest.plugin.label ~= "")
  h.truthy(type(manifest.plugin.version) == "string" and manifest.plugin.version ~= "")

  local component_ids = {}
  local highlight_owners, structural_owners = {}, {}
  for _, component in ipairs(manifest.components or {}) do
    h.truthy(not component_ids[component.id], "duplicate component ID " .. tostring(component.id))
    component_ids[component.id] = true
    h.truthy(type(component.preview) == "table"
        and type(component.preview.fixture_id) == "string"
        and component.preview.fixture_id ~= "",
      "component omitted its deterministic fixture: " .. tostring(component.id))
    h.truthy(type(component.states) == "table" and #component.states > 0,
      "component omitted states: " .. tostring(component.id))
    local state_ids = {}
    for _, state in ipairs(component.states) do
      h.truthy(not state_ids[state.id], "duplicate state ID " .. component.id .. "/" .. state.id)
      state_ids[state.id] = true
      local target = h.truthy(state.target, "state omitted target")
      h.equal(target.management, "managed",
        component.id .. "/" .. state.id .. " must be suite-managed")
      if target.kind == "highlight" then
        h.truthy(vim.startswith(target.group, "UXChrome"),
          "manifest claimed a non-UX highlight " .. tostring(target.group))
        local folded = target.group:lower()
        h.truthy(not highlight_owners[folded], "duplicate manifest highlight " .. target.group)
        highlight_owners[folded] = true
      elseif target.kind == "structural" then
        local key = tostring(target.adapter_id) .. "\0" .. tostring(target.key)
        h.truthy(not structural_owners[key], "duplicate manifest structural target " .. key)
        structural_owners[key] = true
      else
        error("unsupported target kind " .. tostring(target.kind))
      end
      for _, property in ipairs(state.properties or {}) do
        h.truthy(type(property.id) == "string" and type(property.type) == "table",
          "property omitted identity/type")
        h.equal(property.declared.source, "literal")
        h.equal(property.reset, "declared")
        h.equal(property.persist, true)
        h.truthy(type(property.apply) == "table" and type(property.apply.mode) == "string")
      end
    end
  end
  for _, component_id in ipairs({
    "buffer_tabs", "statusline", "winbar", "gutter", "window_treatment", "scrollbar",
  }) do
    h.truthy(component_ids[component_id], "manifest omitted component " .. component_id)
  end
end)

h.test("fixtures are deterministic callback-free and cover required presentation cases", function()
  local chrome = require("ux_chrome")
  local fixtures = chrome.fixtures()
  h.equal(fixtures, chrome.fixtures(), "fixture generation is not deterministic")
  h.assert_json(fixtures, "ux.chrome.fixtures")
  local fixture_ids = collect_ids(fixtures)
  for _, component in ipairs(chrome.manifest().components) do
    h.truthy(fixture_ids[component.preview.fixture_id],
      "no exported fixture matches " .. component.preview.fixture_id)
  end
  for _, state in ipairs({ "active", "inactive", "visible", "modified", "overflow" }) do
    h.truthy(contains_scalar(fixtures, state), "fixtures omitted representative state " .. state)
  end
  for _, layout in ipairs({ "wide", "medium", "narrow" }) do
    h.truthy(contains_scalar(fixtures, layout), "fixtures omitted layout " .. layout)
  end
end)

h.finish()
