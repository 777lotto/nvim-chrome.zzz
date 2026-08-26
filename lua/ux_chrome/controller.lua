local config_module = require("ux_chrome.config")
local foldtext_renderer = require("ux_chrome.render.foldtext")
local lifecycle = require("ux_chrome.lifecycle")
local Scrollbar = require("ux_chrome.scrollbar")
local State = require("ux_chrome.state")
local statuscolumn_renderer = require("ux_chrome.render.statuscolumn")
local statusline_renderer = require("ux_chrome.render.statusline")
local tabline_renderer = require("ux_chrome.render.tabline")
local util = require("ux_chrome.util")
local winbar_renderer = require("ux_chrome.render.winbar")

local Controller = {}
Controller.__index = Controller

Controller.expressions = {
  tabline = "%!v:lua.require'ux_chrome'.tabline()",
  statusline = "%!v:lua.require'ux_chrome'.statusline()",
  winbar = "%!v:lua.require'ux_chrome'.winbar()",
  foldtext = "v:lua.require'ux_chrome'.foldtext()",
}

local GLOBAL_SPECS = {
  tabline = { primary = "tabline", options = { "tabline", "showtabline" } },
  statusline = { primary = "statusline", options = { "statusline", "laststatus" } },
  winbar = { primary = "winbar", options = { "winbar" } },
}

local WINDOW_LOCAL_SPECS = {
  statusline = { primary = "statusline", desired = Controller.expressions.statusline },
  winbar = { primary = "winbar", desired = Controller.expressions.winbar },
}

local WINDOW_SURFACES = { "statusline", "winbar", "statuscolumn", "windows" }
local MAPPED_OPTIONS = { fillchars = true, winhighlight = true }

local function api_error(action, message)
  return ("UX Chrome %s failed: %s"):format(action, tostring(message))
end

local function option_get(api, name, opts)
  local ok, value = pcall(api.nvim_get_option_value, name, opts or {})
  if not ok then return nil, api_error("option read", value) end
  return value
end

local function option_set(api, name, value, opts)
  local ok, err = pcall(api.nvim_set_option_value, name, value, opts or {})
  if not ok then return false, api_error("option write", err) end
  return true
end

local function option_default(api, name)
  local ok, info = pcall(api.nvim_get_option_info2, name, {})
  if not ok or type(info) ~= "table" then return nil end
  return info.default
end

local function option_map(value)
  local order, entries = {}, {}
  for item in tostring(value or ""):gmatch("[^,]+") do
    local key = item:match("^([^:]+):")
    if key then
      if entries[key] == nil then order[#order + 1] = key end
      entries[key] = item
    else
      order[#order + 1] = "\0" .. tostring(#order + 1)
      entries[order[#order]] = item
    end
  end
  return order, entries
end

local function merge_option_map(value, replacements)
  local order, entries = option_map(value)
  -- Sorted, not pairs(): a comma-separated option value must be byte-identical
  -- across processes so snapshots, comparisons and fixtures stay deterministic.
  for _, key in ipairs(util.sorted_keys(replacements)) do
    if entries[key] == nil then order[#order + 1] = key end
    entries[key] = key .. ":" .. replacements[key]
  end
  local result = {}
  for _, key in ipairs(order) do
    if entries[key] and entries[key] ~= "" then result[#result + 1] = entries[key] end
  end
  return table.concat(result, ",")
end

local function selectively_restore_map(current, applied, opening)
  local order, current_entries = option_map(current)
  local _, applied_entries = option_map(applied)
  local _, opening_entries = option_map(opening)
  for key, applied_entry in pairs(applied_entries) do
    local opening_entry = opening_entries[key]
    if applied_entry ~= opening_entry and current_entries[key] == applied_entry then
      current_entries[key] = opening_entry
    end
  end
  local result = {}
  for _, key in ipairs(order) do
    if current_entries[key] and current_entries[key] ~= "" then
      result[#result + 1] = current_entries[key]
    end
  end
  return table.concat(result, ",")
end

local function has_mappings(value, keys)
  local _, entries = option_map(value)
  for _, key in ipairs(keys) do
    if entries[key] ~= nil then return true end
  end
  return false
end

local function same_options(current, expected)
  for key, value in pairs(expected or {}) do
    if current[key] ~= value then return false end
  end
  return true
end

local function releasable_options(current, owner)
  if not owner.applied then return util.deepcopy(owner.snapshot or {}) end
  if same_options(current, owner.applied) then return util.deepcopy(owner.snapshot or {}) end
  local result = {}
  for name, opening in pairs(owner.snapshot or {}) do
    if MAPPED_OPTIONS[name] then
      local restored = selectively_restore_map(current[name], owner.applied[name], opening)
      if restored ~= current[name] then result[name] = restored end
    elseif current[name] == owner.applied[name] then
      result[name] = util.deepcopy(opening)
    end
  end
  return result
end

function Controller.new(config, api)
  return setmetatable({
    api = api or vim.api,
    config = util.deepcopy(config),
    state_store = State.new(),
    scrollbar = Scrollbar.new(api or vim.api),
    global_owners = {},
    window_owners = {},
    surface_status = {},
    buffer_order = {},
    buffer_order_dirty = true,
    started = false,
    scheduled = false,
    refreshing = false,
    tearing_down = false,
    pending_before_start = false,
    pending_reconcile = false,
    pending_redraw = false,
    pending_tabline = false,
  }, Controller)
end

function Controller:get_value(key)
  return self.state_store:get(key)
end

function Controller:values()
  return self.state_store:all()
end

-- Structural values for the redraw hot path. Renderers only read, so this
-- deliberately avoids the deep copy that Controller:values() performs.
function Controller:render_values()
  return self.state_store:raw()
end

function Controller:_normal_windows()
  local result = {}
  for _, win in ipairs(self.api.nvim_list_wins()) do
    if self.api.nvim_win_is_valid(win) then
      local ok, window_config = pcall(self.api.nvim_win_get_config, win)
      if ok and (not window_config.relative or window_config.relative == "") then result[#result + 1] = win end
    end
  end
  table.sort(result)
  return result
end

function Controller:_global_values(names)
  local result = {}
  for _, name in ipairs(names) do
    local value, err = option_get(self.api, name, { scope = "global" })
    if value == nil then return nil, err end
    result[name] = value
  end
  return result
end

function Controller:_window_values(win, names)
  local result = {}
  for _, name in ipairs(names) do
    local value, err = option_get(self.api, name, { win = win, scope = "local" })
    if value == nil then return nil, err end
    result[name] = value
  end
  return result
end

function Controller:_window_effective_values(win, names)
  local result = {}
  for _, name in ipairs(names) do
    local value, err = option_get(self.api, name, { win = win })
    if value == nil then return nil, err end
    result[name] = value
  end
  return result
end

function Controller:_set_global_values(values)
  for _, name in ipairs(util.sorted_keys(values)) do
    local current, err = option_get(self.api, name, { scope = "global" })
    if current == nil then return false, err end
    if current ~= values[name] then
      local ok
      ok, err = option_set(self.api, name, values[name], { scope = "global" })
      if not ok then return false, err end
    end
  end
  return true
end

function Controller:_set_window_values(win, values)
  if not self.api.nvim_win_is_valid(win) then return true end
  for _, name in ipairs(util.sorted_keys(values)) do
    local current, err = option_get(self.api, name, { win = win })
    if current == nil then return false, err end
    if current ~= values[name] then
      local ok
      ok, err = option_set(self.api, name, values[name], { win = win, scope = "local" })
      if not ok then return false, err end
    end
  end
  return true
end

function Controller:_physical_snapshot()
  local result = {
    globals = {},
    windows = {},
    global_owners = util.deepcopy(self.global_owners),
    window_owners = util.deepcopy(self.window_owners),
    surface_status = util.deepcopy(self.surface_status),
  }
  for surface in pairs(self.global_owners) do
    local spec = GLOBAL_SPECS[surface]
    local values, err = self:_global_values(spec.options)
    if not values then return nil, err end
    result.globals[surface] = values
  end
  for win, surfaces in pairs(self.window_owners) do
    if self.api.nvim_win_is_valid(win) then
      local names = {}
      for _, owner in pairs(surfaces) do
        for name in pairs(owner.applied or {}) do names[name] = true end
      end
      local values, err = self:_window_values(win, util.sorted_keys(names))
      if not values then return nil, err end
      result.windows[win] = values
    end
  end
  return result
end

function Controller:_restore_physical(snapshot)
  for surface, owner in pairs(self.global_owners) do
    if not snapshot.global_owners or not snapshot.global_owners[surface] then
      local current, current_error = self:_global_values(GLOBAL_SPECS[surface].options)
      if not current then return false, current_error end
      local values = releasable_options(current, owner)
      if next(values) ~= nil then
        local released, release_error = self:_set_global_values(values)
        if not released then return false, release_error end
      end
    end
  end
  local current_window_owners = self.window_owners
  for win, surfaces in pairs(current_window_owners) do
    local opening = snapshot.window_owners and snapshot.window_owners[win]
    for surface, owner in pairs(surfaces) do
      if not opening or not opening[surface] then
        if self.api.nvim_win_is_valid(win) then
          local current, current_error = self:_window_values(win, util.sorted_keys(owner.applied))
          if not current then return false, current_error end
          local values = releasable_options(current, owner)
          if next(values) ~= nil then
            local released, release_error = self:_set_window_values(win, values)
            if not released then return false, release_error end
          end
        end
      end
    end
  end
  for _, surface in ipairs(util.sorted_keys(snapshot.globals)) do
    local ok, err = self:_set_global_values(snapshot.globals[surface])
    if not ok then return false, err end
  end
  for _, win in ipairs(util.sorted_keys(snapshot.windows)) do
    local ok, err = self:_set_window_values(win, snapshot.windows[win])
    if not ok then return false, err end
  end
  self.global_owners = util.deepcopy(snapshot.global_owners or {})
  self.window_owners = util.deepcopy(snapshot.window_owners or {})
  self.surface_status = util.deepcopy(snapshot.surface_status or {})
  return true
end

function Controller:adapter_snapshot(keys)
  local values, err = self.state_store:snapshot(keys)
  if not values then return nil, err end
  local physical
  physical, err = self:_physical_snapshot()
  if not physical then return nil, err end
  return { values = values, physical = physical }
end

function Controller:adapter_apply(changes)
  return self.state_store:apply(changes)
end

function Controller:adapter_restore(snapshot)
  local ok, err = self.state_store:restore(snapshot and snapshot.values or {})
  if not ok then return false, err end
  if snapshot and snapshot.physical then return self:_restore_physical(snapshot.physical) end
  return true
end

function Controller:adapter_rerender()
  local failure = self.state_store:_failure("rerender")
  if failure then return false, failure end
  if self.tearing_down then return true end
  if not self.started then
    self.pending_before_start = true
    return true
  end
  return self:refresh("foundation_adapter")
end

function Controller:inject_failure(stage, message)
  self.state_store:fail_next(stage, message)
end

function Controller:_global_desired(surface, values)
  if surface == "tabline" then
    return {
      tabline = self.expressions.tabline,
      showtabline = values["buffer_tabs.always_show"] and 2 or 1,
    }
  elseif surface == "statusline" then
    return {
      statusline = self.expressions.statusline,
      laststatus = values["statusline.placement"] == "global" and 3 or 2,
    }
  end
  return { winbar = self.expressions.winbar }
end

function Controller:_release_global(surface, reason)
  local owner = self.global_owners[surface]
  if not owner then
    self.surface_status[surface] = { active = false, reason = reason }
    return true
  end
  local current, err = self:_global_values(GLOBAL_SPECS[surface].options)
  if not current then return false, err end
  local values = releasable_options(current, owner)
  if next(values) ~= nil then
    local ok
    ok, err = self:_set_global_values(values)
    if not ok then return false, err end
  end
  if not same_options(current, owner.applied) then
    reason = reason or "external owner changed the acquired option"
  end
  self.global_owners[surface] = nil
  self.surface_status[surface] = { active = false, reason = reason }
  return true
end

function Controller:_reconcile_global(surface, values)
  local mode = self.config.ownership[surface]
  if mode == "external" or not self.config.enabled then
    return self:_release_global(surface, "configured for external ownership")
  end
  local spec = GLOBAL_SPECS[surface]
  local current, err = self:_global_values(spec.options)
  if not current then return false, err end
  local owner = self.global_owners[surface]
  if owner and mode == "auto" and not same_options(current, owner.applied) then
    return self:_release_global(surface, "late external owner took the surface")
  end
  if not owner then
    local default = option_default(self.api, spec.primary)
    if mode == "auto" and current[spec.primary] ~= "" and current[spec.primary] ~= default then
      self.surface_status[surface] = { active = false, reason = "surface is already owned" }
      return true
    end
    owner = { snapshot = util.deepcopy(current) }
    self.global_owners[surface] = owner
  end
  local desired = self:_global_desired(surface, values)
  local ok
  ok, err = self:_set_global_values(desired)
  if not ok then return false, err end
  owner.applied = util.deepcopy(desired)
  self.surface_status[surface] = { active = true, mode = mode }
  return true
end

function Controller:_window_entry(win)
  self.window_owners[win] = self.window_owners[win] or {}
  return self.window_owners[win]
end

function Controller:_release_window(win, surface, reason)
  local entries = self.window_owners[win]
  local owner = entries and entries[surface]
  if not owner then return true end
  if self.api.nvim_win_is_valid(win) then
    local current, err = self:_window_values(win, util.sorted_keys(owner.applied))
    if not current then return false, err end
    local values = releasable_options(current, owner)
    if next(values) ~= nil then
      local ok
      ok, err = self:_set_window_values(win, values)
      if not ok then return false, err end
    end
  end
  entries[surface] = nil
  if next(entries) == nil then self.window_owners[win] = nil end
  if reason then self.surface_status[surface] = { active = false, reason = reason } end
  return true
end

function Controller:_statuscolumn_desired(values)
  return {
    statuscolumn = statuscolumn_renderer.expression(values),
    foldtext = self.expressions.foldtext,
  }
end

function Controller:_window_treatment_desired(win, current, values)
  local active = win == current
  local inactive_group = values["windows.inactive_style"] == "dim" and "UXChromeWindowInactive" or "NormalNC"
  local opening_winhighlight, err = option_get(self.api, "winhighlight", { win = win })
  if opening_winhighlight == nil then return nil, err end
  local winhighlight = merge_option_map(
    opening_winhighlight,
    {
      Normal = "UXChromeWindowActive",
      NormalNC = inactive_group,
      WinSeparator = active and "UXChromeSplitActive" or "UXChromeSplitInactive",
      SignColumn = "UXChromeGutterSign",
      FoldColumn = "UXChromeGutterFold",
      LineNr = "UXChromeLineNumber",
      CursorLineNr = "UXChromeLineNumberCurrent",
      Folded = "UXChromeFolded",
    }
  )
  local opening_fillchars
  opening_fillchars, err = option_get(self.api, "fillchars", { win = win })
  if opening_fillchars == nil then return nil, err end
  local fillchars = merge_option_map(
    opening_fillchars,
    {
      vert = values["windows.split_vertical"],
      horiz = values["windows.split_horizontal"],
      horizup = values["windows.split_horizontal"],
      horizdown = values["windows.split_horizontal"],
      vertleft = values["windows.split_vertical"],
      vertright = values["windows.split_vertical"],
      verthoriz = values["windows.split_vertical"],
      foldopen = values["gutter.fold_open"],
      foldclose = values["gutter.fold_closed"],
      foldsep = values["gutter.fold_separator"],
    }
  )
  return { winhighlight = winhighlight, fillchars = fillchars }
end

function Controller:_reconcile_window(win, surface, values, current)
  local mode = self.config.ownership[surface]
  if mode == "external" or not self.config.enabled then
    return self:_release_window(win, surface, "configured for external ownership")
  end
  local local_spec = WINDOW_LOCAL_SPECS[surface]
  if local_spec and mode == "auto" then
    return self:_release_window(win, surface)
  end
  local desired, err
  if local_spec then
    desired = { [local_spec.primary] = local_spec.desired }
  elseif surface == "statuscolumn" then
    desired = self:_statuscolumn_desired(values)
  else
    desired, err = self:_window_treatment_desired(win, current, values)
    if not desired then return false, err end
  end
  local names = util.sorted_keys(desired)
  local current_values
  current_values, err = self:_window_values(win, names)
  if not current_values then return false, err end
  local effective_values
  effective_values, err = self:_window_effective_values(win, names)
  if not effective_values then return false, err end
  local entries = self:_window_entry(win)
  local owner = entries[surface]
  if owner and mode == "auto" and not same_options(current_values, owner.applied) then
    return self:_release_window(win, surface, "late external owner took a window surface")
  end
  if not owner then
    if mode == "auto" then
      if surface == "statuscolumn" then
        local statuscolumn_default = option_default(self.api, "statuscolumn")
        local foldtext_default = option_default(self.api, "foldtext")
        if effective_values.statuscolumn ~= (statuscolumn_default or "")
            or effective_values.foldtext ~= (foldtext_default or "foldtext()") then
          self.surface_status[surface] = {
            active = false,
            reason = "statuscolumn or foldtext is already owned",
          }
          return true
        end
      elseif surface == "windows" then
        local highlight_owned = has_mappings(effective_values.winhighlight, {
          "Normal", "NormalNC", "WinSeparator", "SignColumn", "FoldColumn", "LineNr", "CursorLineNr", "Folded",
        })
        local fill_owned = has_mappings(effective_values.fillchars, {
          "vert", "horiz", "horizup", "horizdown", "vertleft", "vertright", "verthoriz",
          "foldopen", "foldclose", "foldsep",
        })
        if highlight_owned or fill_owned then
          self.surface_status[surface] = {
            active = false,
            reason = "window highlight or fill presentation is already owned",
          }
          return true
        end
      end
    end
    owner = { snapshot = util.deepcopy(current_values) }
    entries[surface] = owner
  end
  local ok
  ok, err = self:_set_window_values(win, desired)
  if not ok then return false, err end
  owner.applied = util.deepcopy(desired)
  self.surface_status[surface] = { active = true, mode = mode }
  return true
end

function Controller:invalidate_buffer_order()
  self.buffer_order_dirty = true
end

function Controller:_sync_buffer_order(force)
  if not force and not self.buffer_order_dirty then return end
  local listed, present = {}, {}
  for _, buf in ipairs(self.api.nvim_list_bufs()) do
    if self.api.nvim_buf_is_valid(buf) then
      local ok, value = pcall(self.api.nvim_get_option_value, "buflisted", { buf = buf })
      if ok and value then listed[#listed + 1] = buf present[buf] = true end
    end
  end
  table.sort(listed)
  local next_order, known = {}, {}
  for _, buf in ipairs(self.buffer_order) do
    if present[buf] then next_order[#next_order + 1] = buf known[buf] = true end
  end
  for _, buf in ipairs(listed) do if not known[buf] then next_order[#next_order + 1] = buf end end
  self.buffer_order = next_order
  self.buffer_order_dirty = false
end

function Controller:_tabline_context()
  self:_sync_buffer_order()
  local current_buf = self.api.nvim_get_current_buf()
  local visible = {}
  for _, win in ipairs(self:_normal_windows()) do visible[self.api.nvim_win_get_buf(win)] = true end
  local buffers = {}
  for _, buf in ipairs(self.buffer_order) do
    buffers[#buffers + 1] = {
      id = buf,
      name = self.api.nvim_buf_get_name(buf),
      modified = self.api.nvim_get_option_value("modified", { buf = buf }),
      active = buf == current_buf,
      visible = visible[buf] == true,
    }
  end
  local tabs = {}
  local current_tab = self.api.nvim_get_current_tabpage()
  for _, tab in ipairs(self.api.nvim_list_tabpages()) do
    local tab_window = self.api.nvim_tabpage_get_win(tab)
    local buf = tab_window and self.api.nvim_win_get_buf(tab_window) or nil
    tabs[#tabs + 1] = {
      id = self.api.nvim_tabpage_get_number(tab),
      active = tab == current_tab,
      label = buf and util.basename(self.api.nvim_buf_get_name(buf)) or nil,
    }
  end
  return { buffers = buffers, tabs = tabs, columns = vim.o.columns }
end

function Controller:_render_window()
  local win = tonumber(vim.g.statusline_winid)
  if not win or not self.api.nvim_win_is_valid(win) then win = self.api.nvim_get_current_win() end
  return win
end

function Controller:_statusline_context()
  local win = self:_render_window()
  local buf = self.api.nvim_win_get_buf(win)
  local cursor = self.api.nvim_win_get_cursor(win)
  local encoding = self.api.nvim_get_option_value("fileencoding", { buf = buf })
  if encoding == "" then encoding = vim.o.encoding end
  return {
    active = win == self.api.nvim_get_current_win(),
    mode = vim.api.nvim_get_mode().mode,
    name = self.api.nvim_buf_get_name(buf),
    modified = self.api.nvim_get_option_value("modified", { buf = buf }),
    readonly = self.api.nvim_get_option_value("readonly", { buf = buf }),
    filetype = self.api.nvim_get_option_value("filetype", { buf = buf }),
    fileformat = self.api.nvim_get_option_value("fileformat", { buf = buf }),
    encoding = encoding,
    line = cursor[1],
    column = cursor[2] + 1,
    total_lines = self.api.nvim_buf_line_count(buf),
    width = self:render_values()["statusline.placement"] == "global"
        and vim.o.columns or self.api.nvim_win_get_width(win),
  }
end

function Controller:_winbar_context()
  local win = self:_render_window()
  local buf = self.api.nvim_win_get_buf(win)
  return {
    active = win == self.api.nvim_get_current_win(),
    name = self.api.nvim_buf_get_name(buf),
    modified = self.api.nvim_get_option_value("modified", { buf = buf }),
    width = self.api.nvim_win_get_width(win),
  }
end

function Controller:tabline()
  return tabline_renderer.render(self:_tabline_context(), self:render_values()).text
end

function Controller:statusline()
  return statusline_renderer.render(self:_statusline_context(), self:render_values()).text
end

function Controller:winbar()
  return winbar_renderer.render(self:_winbar_context(), self:render_values()).text
end

function Controller:statuscolumn()
  return statuscolumn_renderer.number({
    lnum = vim.v.lnum,
    relnum = vim.v.relnum,
    virtnum = vim.v.virtnum,
    number = vim.wo.number,
    relativenumber = vim.wo.relativenumber,
    numberwidth = vim.wo.numberwidth,
  })
end

function Controller:foldtext()
  local line = self.api.nvim_buf_get_lines(0, vim.v.foldstart - 1, vim.v.foldstart, false)[1] or ""
  return foldtext_renderer.render({
    text = line,
    start = vim.v.foldstart,
    finish = vim.v.foldend,
    width = self.api.nvim_win_get_width(0),
  })
end

function Controller:refresh(reason)
  if self.refreshing or self.tearing_down then return true end
  local opening, snapshot_error = self:_physical_snapshot()
  if not opening then return false, snapshot_error end
  self.refreshing = true
  local ok, err = xpcall(function()
    local values = self:values()
    for _, surface in ipairs({ "tabline", "statusline", "winbar" }) do
      local applied, apply_error = self:_reconcile_global(surface, values)
      if not applied then error(apply_error, 0) end
    end
    local global_status = {
      statusline = util.deepcopy(self.surface_status.statusline),
      winbar = util.deepcopy(self.surface_status.winbar),
    }
    local current = self.api.nvim_get_current_win()
    local windows = self:_normal_windows()
    local live = {}
    for _, win in ipairs(windows) do
      live[win] = true
      for _, surface in ipairs(WINDOW_SURFACES) do
        local applied, apply_error = self:_reconcile_window(win, surface, values, current)
        if not applied then error(apply_error, 0) end
      end
    end
    for win in pairs(self.window_owners) do if not live[win] then self.window_owners[win] = nil end end

    for _, surface in ipairs({ "statusline", "winbar" }) do
      local status = global_status[surface] or { active = false }
      local option = WINDOW_LOCAL_SPECS[surface].primary
      local explicit, external = 0, 0
      for _, win in ipairs(windows) do
        if self.window_owners[win] and self.window_owners[win][surface] then
          explicit = explicit + 1
        else
          local local_values, local_error = self:_window_values(win, { option })
          if not local_values then error(local_error, 0) end
          if local_values[option] ~= "" then external = external + 1 end
        end
      end
      status.windows_explicit = explicit
      status.windows_external = external
      self.surface_status[surface] = status
    end

    for _, surface in ipairs({ "statuscolumn", "windows" }) do
      local observed = self.surface_status[surface] or {}
      local owned = 0
      for _, win in ipairs(windows) do
        if self.window_owners[win] and self.window_owners[win][surface] then owned = owned + 1 end
      end
      local mode = self.config.ownership[surface]
      if owned > 0 then
        self.surface_status[surface] = {
          active = true,
          mode = mode,
          windows_owned = owned,
          windows_deferred = #windows - owned,
          reason = owned < #windows and observed.reason or nil,
        }
      else
        self.surface_status[surface] = {
          active = false,
          mode = mode,
          windows_owned = 0,
          windows_deferred = #windows,
          reason = (not self.config.enabled or mode == "external")
              and "configured for external ownership"
            or observed.reason or "window surface is already owned",
        }
      end
    end
    local scrollbar_mode = self.config.ownership.scrollbar
    if not self.config.enabled or scrollbar_mode == "external" then
      self.scrollbar:stop()
      self.surface_status.scrollbar = { active = false, reason = "configured for external ownership" }
    else
      local rendered, render_error = self.scrollbar:refresh(windows, values, current)
      if not rendered then error(render_error, 0) end
      self.surface_status.scrollbar = { active = values["scrollbar.enabled"], mode = scrollbar_mode }
    end
    self:_sync_buffer_order(true)
    if self.surface_status.tabline and self.surface_status.tabline.active then
      pcall(vim.cmd, "redrawtabline")
    end
    local redraw_status = false
    for _, surface in ipairs({ "statusline", "winbar", "statuscolumn", "windows" }) do
      if self.surface_status[surface] and self.surface_status[surface].active then
        redraw_status = true
        break
      end
    end
    if redraw_status then pcall(vim.cmd, "redrawstatus") end
    self.last_refresh_reason = reason or "manual"
    self.last_error = nil
  end, debug.traceback)
  if not ok then
    local restored, restore_error = self:_restore_physical(opening)
    self.refreshing = false
    if not restored then return false, err .. "\nrollback failed: " .. tostring(restore_error) end
    return false, err
  end
  self.refreshing = false
  return true
end

-- Cheap path for high-frequency editing events. Neovim re-evaluates the
-- 'statusline', 'winbar' and 'statuscolumn' expressions on its own redraw, so
-- this never reads or writes a managed option; it only follows scroll geometry
-- and, when buffer presentation changed, asks for a tabline redraw.
function Controller:redraw(reason, tabline)
  if self.tearing_down or not self.started then return true end
  local mode = self.config.ownership.scrollbar
  if self.config.enabled and mode ~= "external" then
    local values = self:render_values()
    local ok, err = self.scrollbar:refresh(
      self:_normal_windows(), values, self.api.nvim_get_current_win()
    )
    if not ok then return false, err end
  end
  if tabline and self.surface_status.tabline and self.surface_status.tabline.active then
    pcall(vim.cmd, "redrawtabline")
  end
  self.last_redraw_reason = reason or "manual"
  return true
end

function Controller:_schedule()
  if self.scheduled or self.tearing_down then return end
  self.scheduled = true
  vim.schedule(function()
    self.scheduled = false
    if not self.started or self.tearing_down then return end
    local reconcile = self.pending_reconcile
    local tabline = self.pending_tabline
    local reason = self.pending_reason or "lifecycle"
    self.pending_reconcile = false
    self.pending_redraw = false
    self.pending_tabline = false
    self.pending_reason = nil
    local ok, err
    if reconcile then
      ok, err = self:refresh(reason)
    else
      ok, err = self:redraw(reason, tabline)
    end
    if not ok then self.last_error = err end
  end)
end

-- Request a full ownership reconciliation. A pending reconcile always wins over
-- a pending redraw scheduled in the same tick.
function Controller:request_refresh(reason)
  if self.tearing_down then return end
  self.pending_reconcile = true
  self.pending_reason = reason
  self:_schedule()
end

function Controller:request_redraw(reason, tabline)
  if self.tearing_down then return end
  self.pending_redraw = true
  if tabline then self.pending_tabline = true end
  if not self.pending_reconcile then self.pending_reason = reason end
  self:_schedule()
end

function Controller:start()
  if self.started then return self:refresh("repeat_setup") end
  self.started = true
  self.augroup = lifecycle.setup(self)
  local ok, err = self:refresh(self.pending_before_start and "deferred_foundation_apply" or "setup")
  self.pending_before_start = false
  if not ok then
    lifecycle.teardown(self.augroup)
    self.augroup = nil
    self.started = false
    return false, err
  end
  return true
end

function Controller:_release_all()
  self.scrollbar:stop()
  for _, win in ipairs(util.sorted_keys(self.window_owners)) do
    for _, surface in ipairs(WINDOW_SURFACES) do
      local ok, err = self:_release_window(win, surface)
      if not ok then return false, err end
    end
  end
  for _, surface in ipairs({ "tabline", "statusline", "winbar" }) do
    local ok, err = self:_release_global(surface)
    if not ok then return false, err end
  end
  return true
end

function Controller:stop()
  lifecycle.teardown(self.augroup)
  self.augroup = nil
  self.started = false
  self.scheduled = false
  self.pending_reconcile = false
  self.pending_redraw = false
  self.pending_tabline = false
  self.pending_reason = nil
  return self:_release_all()
end

function Controller:set_ownership(surface, mode)
  if self.config.ownership[surface] == nil then
    return false, ("unknown UX Chrome surface %q"):format(tostring(surface))
  end
  local snapshot, snapshot_error = self:_physical_snapshot()
  if not snapshot then return false, snapshot_error end
  local previous = self.config.ownership[surface]
  self.config.ownership[surface] = config_module.ownership_value(mode)
  local ok, err = self:refresh("ownership_change")
  if ok then return true end
  self.config.ownership[surface] = previous
  local restored, restore_error = self:_restore_physical(snapshot)
  if not restored then return false, err .. "\nrollback failed: " .. tostring(restore_error) end
  return false, err
end

function Controller:set_all_ownership(mode)
  local snapshot, snapshot_error = self:_physical_snapshot()
  if not snapshot then return false, snapshot_error end
  local previous = util.deepcopy(self.config.ownership)
  local normalized = config_module.ownership_value(mode)
  for surface in pairs(self.config.ownership) do self.config.ownership[surface] = normalized end
  local ok, err = self:refresh("ownership_change")
  if ok then return true end
  self.config.ownership = previous
  local restored, restore_error = self:_restore_physical(snapshot)
  if not restored then return false, err .. "\nrollback failed: " .. tostring(restore_error) end
  return false, err
end

function Controller:reconfigure(next_config)
  local snapshot, snapshot_error = self:_physical_snapshot()
  if not snapshot then return false, snapshot_error end
  local previous = self.config
  self.config = util.deepcopy(next_config)
  local ok, err = self:refresh("reconfigure")
  if ok then return true end
  self.config = previous
  local restored, restore_error = self:_restore_physical(snapshot)
  if not restored then return false, err .. "\nrollback failed: " .. tostring(restore_error) end
  return false, err
end

function Controller:toggle(surface, force_ux)
  local current = self.config.ownership[surface]
  if current == nil then return false, ("unknown UX Chrome surface %q"):format(tostring(surface)) end
  local mode = current == "external" and (force_ux and "ux" or "auto") or "external"
  return self:set_ownership(surface, mode)
end

function Controller:_current_buffer_index()
  self:_sync_buffer_order(true)
  local current = self.api.nvim_get_current_buf()
  for index, buf in ipairs(self.buffer_order) do if buf == current then return index end end
end

function Controller:select_buffer(which)
  self:_sync_buffer_order(true)
  if #self.buffer_order == 0 then return false, "no listed buffers" end
  local current = self:_current_buffer_index() or 1
  local index
  if which == "next" then index = current % #self.buffer_order + 1
  elseif which == "prev" then index = (current - 2) % #self.buffer_order + 1
  elseif which == "first" then index = 1
  elseif which == "last" then index = #self.buffer_order
  else return false, "unknown buffer selection" end
  self.api.nvim_set_current_buf(self.buffer_order[index])
  return true
end

function Controller:move_buffer(delta)
  local index = self:_current_buffer_index()
  if not index or #self.buffer_order < 2 then return true end
  local target = util.clamp(index + delta, 1, #self.buffer_order)
  if target == index then return true end
  local value = table.remove(self.buffer_order, index)
  table.insert(self.buffer_order, target, value)
  self:request_redraw("buffer_move", true)
  return true
end

function Controller:close_buffer()
  local ok, err = pcall(self.api.nvim_buf_delete, self.api.nvim_get_current_buf(), {})
  if not ok then return false, err end
  return true
end

function Controller:public_state()
  return {
    started = self.started,
    ownership = util.deepcopy(self.config.ownership),
    surfaces = util.deepcopy(self.surface_status),
    values = self:values(),
    buffer_order = util.deepcopy(self.buffer_order),
    scrollbars = self.scrollbar:state(),
    last_refresh_reason = self.last_refresh_reason,
    last_redraw_reason = self.last_redraw_reason,
    last_error = self.last_error,
  }
end

return Controller
