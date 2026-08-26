local util = require("ux_chrome.util")

local Scrollbar = {}
Scrollbar.__index = Scrollbar

local function valid_window(api, win)
  return type(win) == "number" and api.nvim_win_is_valid(win)
end

function Scrollbar.new(api)
  return setmetatable({
    api = api or vim.api,
    rails = {},
    updating = false,
  }, Scrollbar)
end

function Scrollbar:_close(target)
  local rail = self.rails[target]
  if not rail then return end
  if valid_window(self.api, rail.win) then pcall(self.api.nvim_win_close, rail.win, true) end
  if rail.buf and self.api.nvim_buf_is_valid(rail.buf) then pcall(self.api.nvim_buf_delete, rail.buf, { force = true }) end
  self.rails[target] = nil
end

function Scrollbar:stop()
  local targets = util.sorted_keys(self.rails)
  for _, target in ipairs(targets) do self:_close(target) end
end

local function geometry(api, win, values)
  if not valid_window(api, win) then return nil end
  local config = api.nvim_win_get_config(win)
  if config.relative and config.relative ~= "" then return nil end
  local buf = api.nvim_win_get_buf(win)
  if not api.nvim_buf_is_valid(buf) then return nil end
  local buftype = api.nvim_get_option_value("buftype", { buf = buf })
  if buftype ~= "" then return nil end
  local total = api.nvim_buf_line_count(buf)
  if total < values["scrollbar.min_lines"] then return nil end
  local ok, viewport = pcall(api.nvim_win_call, win, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  if not ok or type(viewport) ~= "table" then return nil end
  local top, bottom = tonumber(viewport[1]), tonumber(viewport[2])
  if not top or not bottom then return nil end
  local height = math.max(1, api.nvim_win_get_height(win))
  local visible = math.max(1, bottom - top + 1)
  if total <= visible then return nil end
  local thumb_height = values["scrollbar.thumb_size"] == "single"
      and 1 or math.max(1, math.floor((visible / total) * height))
  thumb_height = math.min(height, thumb_height)
  local range = math.max(1, total - visible)
  local start = math.floor(((top - 1) / range) * math.max(0, height - thumb_height))
  local cursor = api.nvim_win_get_cursor(win)
  local cursor_line = util.clamp(tonumber(cursor[1]) or 1, 1, total)
  local marker_row = math.floor(((cursor_line - 1) / math.max(1, total - 1)) * math.max(0, height - 1))
  return {
    target = win,
    buf = buf,
    height = height,
    width = math.max(1, api.nvim_win_get_width(win)),
    thumb_start = util.clamp(start, 0, height - thumb_height),
    thumb_height = thumb_height,
    marker_row = marker_row,
    top = top,
    bottom = bottom,
    total = total,
  }
end

function Scrollbar:_ensure(geo)
  local rail = self.rails[geo.target]
  if rail and (not valid_window(self.api, rail.win) or not self.api.nvim_buf_is_valid(rail.buf)) then
    self:_close(geo.target)
    rail = nil
  end
  if not rail then
    local buf = self.api.nvim_create_buf(false, true)
    self.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
    self.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    self.api.nvim_set_option_value("swapfile", false, { buf = buf })
    local win = self.api.nvim_open_win(buf, false, {
      relative = "win",
      win = geo.target,
      row = 0,
      col = geo.width,
      width = 1,
      height = geo.height,
      anchor = "NE",
      focusable = false,
      style = "minimal",
      zindex = 45,
      noautocmd = true,
    })
    self.api.nvim_set_option_value("winhighlight", "Normal:UXChromeScrollbarTrack", { win = win })
    rail = {
      buf = buf,
      win = win,
      namespace = self.api.nvim_create_namespace("ux_chrome_scrollbar_" .. tostring(geo.target)),
    }
    self.rails[geo.target] = rail
  else
    self.api.nvim_win_set_config(rail.win, {
      relative = "win",
      win = geo.target,
      row = 0,
      col = geo.width,
      width = 1,
      height = geo.height,
      anchor = "NE",
    })
  end
  return rail
end

function Scrollbar:_draw(rail, geo, values)
  local signature = table.concat({
    geo.height,
    geo.thumb_start,
    geo.thumb_height,
    geo.marker_row,
    values["scrollbar.track_glyph"],
    values["scrollbar.thumb_glyph"],
  }, "\0")
  if rail.signature == signature then return end
  rail.signature = signature
  local lines = {}
  for index = 0, geo.height - 1 do
    local thumb = index >= geo.thumb_start and index < geo.thumb_start + geo.thumb_height
    lines[#lines + 1] = thumb and values["scrollbar.thumb_glyph"] or values["scrollbar.track_glyph"]
  end
  self.api.nvim_set_option_value("modifiable", true, { buf = rail.buf })
  self.api.nvim_buf_set_lines(rail.buf, 0, -1, false, lines)
  self.api.nvim_buf_clear_namespace(rail.buf, rail.namespace, 0, -1)
  for index = geo.thumb_start, geo.thumb_start + geo.thumb_height - 1 do
    self.api.nvim_buf_set_extmark(rail.buf, rail.namespace, index, 0, {
      line_hl_group = "UXChromeScrollbarThumb",
    })
  end
  self.api.nvim_buf_set_extmark(rail.buf, rail.namespace, geo.marker_row, 0, {
    line_hl_group = "UXChromeScrollbarMarker",
  })
  self.api.nvim_set_option_value("modifiable", false, { buf = rail.buf })
end

function Scrollbar:refresh(windows, values, current)
  if self.updating then return true end
  self.updating = true
  local ok, err = xpcall(function()
    local wanted = {}
    if values["scrollbar.enabled"] then
      for _, win in ipairs(windows or {}) do
        if values["scrollbar.show_inactive"] or win == current then
          local geo = geometry(self.api, win, values)
          if geo then
            wanted[win] = true
            self:_draw(self:_ensure(geo), geo, values)
          end
        end
      end
    end
    for _, target in ipairs(util.sorted_keys(self.rails)) do
      if not wanted[target] then self:_close(target) end
    end
  end, debug.traceback)
  self.updating = false
  if not ok then return false, err end
  return true
end

function Scrollbar:state()
  local result = {}
  for target, rail in pairs(self.rails) do
    result[#result + 1] = { target = target, win = rail.win, buf = rail.buf }
  end
  table.sort(result, function(left, right) return left.target < right.target end)
  return result
end

return Scrollbar
