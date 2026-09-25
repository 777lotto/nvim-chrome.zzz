-- Shared single-line presentation. Callers own row identity and actions.
local M = {}
local api, fn = vim.api, vim.fn
local foundation, shared, group
local stores, watchers = {}, {}
local defaults = { padding = 1, indent = 2, gap = 2, truncation = "ellipsis" }
local keys = { "padding", "indent", "gap", "truncation" }
local highlights = { row = "UXChromeComponentRow", header = "UXChromeComponentHeader", empty = "UXChromeComponentEmpty" }

local function clean(text)
  return tostring(text or ""):gsub("%c", " ")
end

-- Display cells, not bytes. strcharpart(..., true) keeps combining marks
-- with their base character; highlight offsets below remain byte offsets.
function M.truncate(text, width, mode)
  text = clean(text)
  width = math.max(0, math.floor(width))
  if mode == "none" or fn.strdisplaywidth(text) <= width then return text end
  local suffix = mode == "clip" and "" or "…"
  if width < fn.strdisplaywidth(suffix) then return "" end
  local low, high = 0, fn.strchars(text, true)
  while low < high do
    local mid = math.floor((low + high + 1) / 2)
    if fn.strdisplaywidth(fn.strcharpart(text, 0, mid, true) .. suffix) <= width then
      low = mid
    else high = mid - 1 end
  end
  return fn.strcharpart(text, 0, low, true) .. suffix
end

local function redraw()
  local wins = vim.tbl_keys(watchers)
  table.sort(wins)
  for _, win in ipairs(wins) do
    local item = watchers[win]
    if item and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == item.buffer then
      local view = api.nvim_win_call(win, fn.winsaveview)
      local ok, err = pcall(item.redraw)
      if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == item.buffer then
        api.nvim_win_call(win, function() fn.winrestview(view) end)
      end
      if not ok then error(err) end
    else watchers[win] = nil end
  end
end

local function enum(values)
  local options = {}
  for _, value in ipairs(values) do options[#options + 1] = { id = value, label = value } end
  return { kind = "enum", options = options }
end

local function register(id, overrides)
  local store = { values = {}, adapter = id:gsub("%.", "_") }
  local states = {}
  for _, key in ipairs(keys) do
    local value = overrides and (key == "truncation" and "inherit" or -1) or defaults[key]
    store.values[key] = value
    local spec = key == "truncation"
        and enum(overrides and { "inherit", "ellipsis", "clip", "none" } or { "ellipsis", "clip", "none" })
      or { kind = "integer", min = overrides and -1 or 0, max = 8 }
    states[#states + 1] = {
      id = key, label = key,
      target = { kind = "structural", adapter_id = store.adapter, key = key, management = "managed" },
      properties = { { id = "value", label = "Value", field = "value", type = spec,
        declared = { source = "literal", value = value }, semantic_fallback = value,
        reset = "declared", persist = true, apply = { mode = "rerender" } } },
    }
  end
  local manifest = { schema_version = 1, plugin = { id = id, label = id, version = "0.1.0" },
    components = { { id = "navigation", label = "Navigation components", states = states,
      preview = { fixture_id = id .. ".navigation.v1" } } } }
  local fixture = { id = id .. ".navigation.v1", label = "Navigation", schema_version = 1,
    plugin_id = id, component_id = "navigation", lines = {
      { segments = { { text = " ▾ Sessions  (2)", hl_group = highlights.header } } },
      { segments = { { text = "   ● Example session", hl_group = highlights.row } } },
      { segments = { { text = "   (none)", hl_group = highlights.empty } } },
    } }
  local handle, err = foundation.register(manifest, { fixtures = { [fixture.id] = fixture }, adapters = {
    [store.adapter] = {
      probe = function() return { available = true, capabilities = { reversible = true, batched_apply = true } } end,
      get = function(_, key) return store.values[key] end,
      snapshot = function() return vim.deepcopy(store.values) end,
      apply = function(_, changes)
        for _, change in ipairs(changes) do store.values[change.key] = change.value end
        return true
      end,
      restore = function(_, snapshot) store.values = vim.deepcopy(snapshot); redraw(); return true end,
      rerender = function() redraw(); return true end,
    },
  } })
  if not handle then error(err.message) end
  store.handle = handle
  return store
end

local function initialize()
  if shared then return end
  foundation = require("ux_foundation")
  assert(foundation.contract_version == 1, "Chrome components require Foundation schema v1")
  shared = register("ux.chrome.components", false)
  local manifest, impl = require("ux_foundation.builder").highlights({
    plugin = { id = "ux.chrome.components.appearance", label = "Shared component colors", version = "0.1.0" },
    component = { id = "appearance", label = "Appearance" }, groups = {
      { id = "row", label = "Row", group = highlights.row, link = "Normal" },
      { id = "header", label = "Header", group = highlights.header, link = "Title" },
      { id = "empty", label = "Empty state", group = highlights.empty, link = "Comment" },
    },
  })
  for _, state in ipairs(manifest.components[1].states) do
    for _, color in ipairs({ { "foreground", "fg" }, { "background", "bg" } }) do
      state.properties[#state.properties + 1] = {
        id = color[1], label = color[1], field = color[2], type = { kind = "color", allow_unset = true },
        declared = { source = "literal", value = { kind = "unset" } },
        semantic_fallback = { kind = "unset" }, reset = "declared", persist = true,
        apply = { mode = "immediate" },
      }
    end
  end
  local handle, err = foundation.register(manifest, impl)
  if not handle then error(err.message) end
  shared.appearance = handle
  group = api.nvim_create_augroup("UXChromeComponents", { clear = true })
  api.nvim_create_autocmd("WinClosed", { group = group, callback = function(ev) watchers[tonumber(ev.match)] = nil end })
  api.nvim_create_autocmd("BufWinLeave", { group = group, callback = function(ev)
    local win = api.nvim_get_current_win()
    if watchers[win] and watchers[win].buffer == ev.buf then watchers[win] = nil end
  end })
  api.nvim_create_autocmd("WinResized", { group = group, callback = redraw })
end

function M.register(id)
  assert(type(id) == "string" and id:match("^[a-z][a-z0-9_]*[a-z0-9_.]*$") and not id:find("%.%.")
    and not id:match("%.$"), "invalid component identity")
  initialize()
  if not stores[id] then stores[id] = register("ux.chrome.component." .. id, true) end
end

function M.inspect(id)
  M.register(id)
  local values = {}
  for _, key in ipairs(keys) do
    local value = stores[id].values[key]
    values[key] = (value == -1 or value == "inherit") and shared.values[key] or value
  end
  return values
end

-- Create a rendering context on each redraw. Width is the actual pane width;
-- optional window/redraw binds cached application rendering to live edits.
function M.context(opts)
  M.register(opts.id)
  if opts.window and opts.redraw then
    assert(api.nvim_win_is_valid(opts.window), "invalid component window")
    assert(type(opts.redraw) == "function", "component redraw must be a function")
    watchers[opts.window] = { buffer = api.nvim_win_get_buf(opts.window), redraw = opts.redraw }
  end
  local context = { values = M.inspect(opts.id), width = opts.width or (opts.window and api.nvim_win_get_width(opts.window)) or 80 }
  function context:format(spec)
    local kind = spec.kind or "row"
    assert(highlights[kind], "unknown component kind")
    local depth = spec.depth or (kind == "header" and 0 or 1)
    assert(type(depth) == "number" and depth >= 0 and depth % 1 == 0 and depth <= 100, "invalid row depth")
    local prefix = string.rep(" ", self.values.padding + depth * self.values.indent)
    if spec.prefix and spec.prefix ~= "" then prefix = prefix .. clean(spec.prefix) .. " " end
    local text = prefix .. clean(spec.text)
    if spec.count ~= nil then text = text .. string.rep(" ", self.values.gap) .. "(" .. clean(spec.count) .. ")" end
    text = M.truncate(text, self.width, self.values.truncation)
    return text, { start = math.min(#prefix, #text), finish = #text, group = spec.highlight or highlights[kind] }
  end
  return context
end

function M.detach(win) watchers[win] = nil end

function M.teardown()
  if not shared then return true end
  for id, store in pairs(stores) do
    local ok, err = foundation.unregister(store.handle)
    if not ok then return false, err end
    stores[id] = nil
  end
  local ok, err = foundation.unregister(shared.appearance)
  if not ok then return false, err end
  ok, err = foundation.unregister(shared.handle)
  if not ok then return false, err end
  shared, watchers = nil, {}
  if group then api.nvim_del_augroup_by_id(group); group = nil end
  return true
end

return M
