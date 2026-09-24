-- Explicit plugin panes, independent of editor-wide Chrome surface ownership.
-- Stable descriptors survive window closure; window IDs never enter profiles.
local M = {}
local api = vim.api
local roles = { navigation = false, log = true, context = true, input = true }
local contents = { list = true, plaintext = true, markdown = true, diff = true, code = true }
local options = {
  "wrap", "linebreak", "breakindent", "number", "relativenumber", "signcolumn",
  "foldcolumn", "list", "cursorline", "winhighlight",
  "breakindentopt", "sidescrolloff",
}
local foundation, shared, group
local descriptors, windows = {}, {}
local serial = 0
local watched, pending = {}, {}
local markdown, queue_markdown

local function copy(value) return vim.deepcopy(value) end
local function fail(message) error("ux_chrome.panes: " .. message, 3) end
local function sorted(t) local keys = vim.tbl_keys(t); table.sort(keys); return keys end
local function enum(values)
  local result = { kind = "enum", options = {} }
  for _, value in ipairs(values) do result.options[#result.options + 1] = { id = value, label = value } end
  return result
end

local function capture(win)
  local result = {}
  for _, name in ipairs(options) do result[name] = api.nvim_get_option_value(name, { win = win, scope = "local" }) end
  return result
end

local function write(win, values)
  for _, name in ipairs(options) do
    if values[name] ~= nil then api.nvim_set_option_value(name, values[name], { win = win, scope = "local" }) end
  end
end

local function live(item)
  return api.nvim_win_is_valid(item.window) and api.nvim_win_get_buf(item.window) == item.buffer
end

local function effective(descriptor)
  local result = {}
  for _, key in ipairs({ "wrap", "cursorline", "gutter" }) do
    local value = descriptor.values[key]
    if value == "inherit" then value = shared.values[descriptor.role .. "." .. key] end
    if value == "on" then value = true elseif value == "off" then value = false end
    result[key] = value
  end
  return result
end

local function highlight_map(original)
  local entries = {}
  for entry in (original or ""):gmatch("[^,]+") do
    local name = entry:match("^([^:]+):")
    if name ~= "Normal" and name ~= "NormalNC" and name ~= "CursorLine" then entries[#entries + 1] = entry end
  end
  vim.list_extend(entries, {
    "Normal:UXChromePaneNormal", "NormalNC:UXChromePaneInactive", "CursorLine:UXChromePaneSelection",
  })
  return table.concat(entries, ",")
end

local function restore_highlights(current, applied, opening)
  local function entries(value)
    local result = {}
    for entry in (value or ""):gmatch("[^,]+") do
      local name, target = entry:match("^([^:]+):(.+)$")
      if name then result[name] = target end
    end
    return result
  end
  local active, previous = entries(applied), entries(opening)
  local managed = { Normal = true, NormalNC = true, CursorLine = true }
  local result = {}
  for entry in current:gmatch("[^,]+") do
    local name, target = entry:match("^([^:]+):(.+)$")
    if managed[name] and active[name] == target then
      if previous[name] then result[#result + 1] = name .. ":" .. previous[name] end
    else
      result[#result + 1] = entry
    end
  end
  return table.concat(result, ",")
end

local function render(item)
  if not live(item) then return end
  local values = effective(descriptors[item.id])
  local desired = {
    wrap = values.wrap, linebreak = values.wrap, breakindent = values.wrap,
    breakindentopt = "shift:2,min:20", sidescrolloff = values.wrap and 0 or item.opening.sidescrolloff,
    cursorline = values.cursorline, list = false,
    number = values.gutter ~= "none", relativenumber = values.gutter == "relative",
    signcolumn = "no", foldcolumn = "0",
    winhighlight = highlight_map(api.nvim_get_option_value("winhighlight", { win = item.window })),
  }
  write(item.window, desired)
  item.applied = desired
end

local function render_all()
  for _, win in ipairs(sorted(windows)) do render(windows[win]) end
end

local function physical_snapshot()
  local result = {}
  for win, item in pairs(windows) do
    if live(item) then result[win] = { serial = item.serial, values = capture(win) } end
  end
  return result
end

local function implementation(store)
  return { fixtures = store.fixtures, adapters = { [store.adapter] = {
    probe = function() return { available = true, capabilities = { reversible = true, batched_apply = true } } end,
    get = function(_, key) return store.values[key] end,
    snapshot = function() return { values = copy(store.values), physical = physical_snapshot() } end,
    apply = function(_, changes)
      for _, change in ipairs(changes) do store.values[change.key] = change.value end
      return true
    end,
    restore = function(_, snapshot)
      store.values = copy(snapshot.values)
      render_all()
      for win, saved in pairs(snapshot.physical) do
        local item = windows[win]
        if item and item.serial == saved.serial and live(item) then
          write(win, saved.values)
          item.applied = copy(saved.values)
        end
      end
      return true
    end,
    rerender = function() render_all(); return true end,
  } } }
end

local function setting(store, key, id, default, type_spec)
  store.values[key] = default
  return {
    id = id, label = id,
    target = { kind = "structural", adapter_id = store.adapter, key = key, management = "managed" },
    properties = { {
      id = "value", label = "Value", field = "value", type = type_spec,
      declared = { source = "literal", value = default }, semantic_fallback = default,
      reset = "declared", persist = true, apply = { mode = "rerender" },
    } },
  }
end

local function register(store, manifest)
  store.fixtures = {}
  for _, component in ipairs(manifest.components) do
    local id = manifest.plugin.id .. "." .. component.id .. ".v1"
    component.preview = { fixture_id = id }
    store.fixtures[id] = {
      id = id, label = component.label, schema_version = 1,
      plugin_id = manifest.plugin.id, component_id = component.id,
      lines = {
        { segments = { { text = "Navigation · selected item", hl_group = "UXChromePaneSelection" } } },
        { segments = { { text = "Context · a document or description", hl_group = "UXChromePaneNormal" } } },
        { segments = { { text = "Log · application output", hl_group = "UXChromePaneInactive" } } },
      },
    }
  end
  local handle, err = foundation.register(manifest, implementation(store))
  if not handle then fail(err.message) end
  store.handle = handle
end

local function initialize()
  if shared then return end
  foundation = require("ux_foundation")
  assert(foundation.contract_version == 1, "Chrome panes require Foundation schema v1")
  local store = { values = {}, adapter = "ux_chrome_panes" }
  local components = {}
  for _, role in ipairs(sorted(roles)) do
    components[#components + 1] = { id = role, label = role, states = {
      setting(store, role .. ".wrap", "wrap", roles[role], { kind = "boolean" }),
      setting(store, role .. ".cursorline", "cursorline", role == "navigation", { kind = "boolean" }),
      setting(store, role .. ".gutter", "gutter", "none", enum({ "none", "numbers", "relative" })),
    } }
  end
  local manifest = require("ux_foundation.builder").highlights({
    plugin = { id = "ux.chrome.panes", label = "Shared pane defaults", version = "0.1.0" },
    component = { id = "appearance", label = "Pane appearance" },
    groups = {
      { id = "normal", label = "Normal", group = "UXChromePaneNormal", link = "Normal" },
      { id = "inactive", label = "Inactive", group = "UXChromePaneInactive", link = "NormalNC" },
      { id = "selection", label = "Selection", group = "UXChromePaneSelection", link = "CursorLine" },
    },
  })
  -- Keep theme links as defaults while exposing explicit color overrides.
  -- Unset attributes do not compete with the link; Foundation journals the
  -- automatic unlink when a user supplies a foreground or background.
  for _, state in ipairs(manifest.components[1].states) do
    for _, color in ipairs({ { "foreground", "fg" }, { "background", "bg" } }) do
      local id, field = color[1], color[2]
      state.properties[#state.properties + 1] = {
        id = id, label = id, field = field, type = { kind = "color", allow_unset = true },
        declared = { source = "literal", value = { kind = "unset" } },
        semantic_fallback = { kind = "unset" }, reset = "declared", persist = true,
        apply = { mode = "immediate" },
      }
    end
  end
  vim.list_extend(manifest.components, components)
  shared = store
  local ok, err = pcall(register, store, manifest)
  if not ok then shared = nil; error(err) end
  group = api.nvim_create_augroup("UXChromePanes", { clear = true })
  api.nvim_create_autocmd("WinClosed", { group = group, callback = function(event)
    windows[tonumber(event.match)] = nil
  end })
  api.nvim_create_autocmd("BufWinLeave", { group = group, callback = function(event)
    local win = api.nvim_get_current_win()
    if windows[win] and windows[win].buffer == event.buf then M.detach(win) end
  end })
  api.nvim_create_autocmd("BufWinEnter", { group = group, callback = function()
    for _, win in ipairs(sorted(windows)) do
      if not live(windows[win]) then M.detach(win) end
    end
  end })
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged", "WinScrolled", "WinResized" }, {
    group = group,
    callback = function()
      for _, item in pairs(windows) do
        if item.content == "markdown" and live(item) then queue_markdown(item.buffer) end
      end
    end,
  })
end

--- Register stable presentation identity independently of live window instances.
function M.register(spec)
  if type(spec) ~= "table" or type(spec.id) ~= "string"
      or not spec.id:match("^[a-z][a-z0-9_]*%.[a-z0-9_.]+$")
      or spec.id:find("%.%.") or spec.id:sub(-1) == "." then fail("a stable dotted id is required") end
  for segment in spec.id:gmatch("[^.]+") do
    if not segment:match("^[a-z][a-z0-9_]*$") then fail("invalid id segment") end
  end
  if roles[spec.role] == nil then fail("unknown pane role") end
  initialize()
  if descriptors[spec.id] then
    if descriptors[spec.id].role ~= spec.role then fail("cannot change a registered pane role") end
    return spec.id
  end
  local store = { id = spec.id, role = spec.role, values = {}, adapter = "ux_chrome_pane." .. spec.id }
  local manifest = {
    schema_version = 1,
    plugin = { id = "ux.chrome.pane." .. spec.id, label = spec.label or spec.id, version = "0.1.0" },
    components = { { id = "presentation", label = spec.role .. " presentation", states = {
      setting(store, "wrap", "wrap", "inherit", enum({ "inherit", "on", "off" })),
      setting(store, "cursorline", "cursorline", "inherit", enum({ "inherit", "on", "off" })),
      setting(store, "gutter", "gutter", "inherit", enum({ "inherit", "none", "numbers", "relative" })),
    } } },
  }
  register(store, manifest)
  descriptors[spec.id] = store
  return spec.id
end

--- Coordinate Markdown through public APIs. Backend owns its decoration lifecycle;
--- no private renderer state, setup replay, or buffer-wide enable toggles are used.
markdown = function(item)
  if item.content ~= "markdown" then return { active = false } end
  local filetype = vim.bo[item.buffer].filetype
  if filetype ~= "" then vim.treesitter.language.register("markdown", filetype) end
  local syntax_ok, syntax_error = item.syntax_started, nil
  if not syntax_ok then
    local syntax = vim.bo[item.buffer].syntax
    syntax_ok, syntax_error = pcall(vim.treesitter.start, item.buffer, "markdown")
    if not syntax_ok then vim.bo[item.buffer].syntax = syntax end
    item.syntax_started = syntax_ok
  end
  local ok, backend = pcall(require, "render-markdown")
  if ok and type(backend.render) == "function" then
    -- Chrome coalesces updates. The backend's independent debounce can drop a
    -- final streamed update, so disable it for this explicitly owned buffer.
    local rendered, err = pcall(backend.render, {
      buf = item.buffer, win = item.window, config = { debounce = 0 },
    })
    return { active = rendered, backend = "render-markdown", reason = not rendered and tostring(err) or nil }
  end
  return { active = syntax_ok, backend = "treesitter", reason = not syntax_ok and tostring(syntax_error) or nil }
end

queue_markdown = function(buf)
  if pending[buf] then return end
  pending[buf] = true
  vim.defer_fn(function()
    pending[buf] = nil
    for _, item in pairs(windows) do
      if item.buffer == buf and item.content == "markdown" and live(item) then
        item.markdown = markdown(item)
      end
    end
  end, 16)
end

local function watch(buf)
  if watched[buf] then return end
  watched[buf] = true
  api.nvim_buf_attach(buf, false, {
    on_lines = function() queue_markdown(buf) end,
    on_detach = function() watched[buf] = nil end,
  })
end

--- Attach existing windows; never acquires editor bars or creates layouts.
function M.attach(spec)
  spec = copy(spec)
  if type(spec) == "table" and spec.window == 0 then spec.window = api.nvim_get_current_win() end
  if type(spec) ~= "table" or not api.nvim_win_is_valid(spec.window or -1) then fail("valid window required") end
  local buf = spec.buffer or api.nvim_win_get_buf(spec.window)
  if api.nvim_win_get_buf(spec.window) ~= buf then fail("window does not display the supplied buffer") end
  local content = spec.content or "plaintext"
  if not contents[content] then fail("unknown content type") end
  for _, item in pairs(windows) do
    if item.buffer == buf and item.content ~= content then
      fail("content type belongs to the buffer; use a new buffer when its content type changes")
    end
  end
  M.register(spec)
  local old = windows[spec.window]
  if old and old.id == spec.id and old.buffer == buf then
    if old.content ~= content then old.content = content; old.markdown = markdown(old) end
    render(old)
    return M.inspect(spec.window)
  end
  if old then M.detach(spec.window) end
  local chrome = package.loaded.ux_chrome
  if chrome and chrome._prepare_pane then
    local ok, err = chrome._prepare_pane(spec.window)
    if not ok then fail(tostring(err)) end
  end
  serial = serial + 1
  local item = {
    id = spec.id, window = spec.window, buffer = buf, content = content,
    opening = capture(spec.window), serial = serial,
  }
  windows[spec.window] = item
  local ok, err = pcall(render, item)
  if not ok then write(spec.window, item.opening); windows[spec.window] = nil; error(err) end
  item.markdown = markdown(item)
  if content == "markdown" then watch(buf) end
  return M.inspect(spec.window)
end

function M.detach(win)
  local item = windows[win]
  if not item then return true end
  if api.nvim_win_is_valid(win) then
    local current, restore = capture(win), {}
    for _, name in ipairs(options) do
      -- Preserve an external edit made after our last application.
      if item.applied and current[name] == item.applied[name] then restore[name] = item.opening[name] end
    end
    if not restore.winhighlight and item.applied then
      restore.winhighlight = restore_highlights(current.winhighlight, item.applied.winhighlight, item.opening.winhighlight)
    end
    write(win, restore)
  end
  windows[win] = nil
  return true
end

function M.inspect(win)
  local item = windows[win]
  if not item then return nil end
  return {
    id = item.id, role = descriptors[item.id].role, content = item.content,
    window = win, buffer = item.buffer, effective = effective(descriptors[item.id]),
    overrides = copy(descriptors[item.id].values), markdown = copy(item.markdown),
  }
end

function M.owns(win) return windows[win] ~= nil end

function M.teardown()
  for _, win in ipairs(sorted(windows)) do M.detach(win) end
  for _, id in ipairs(sorted(descriptors)) do
    local ok, err = foundation.unregister(descriptors[id].handle)
    if not ok then return false, err end
    descriptors[id] = nil
  end
  if shared then
    local ok, err = foundation.unregister(shared.handle)
    if not ok then return false, err end
    shared = nil
  end
  if group then api.nvim_del_augroup_by_id(group); group = nil end
  return true
end

return M
