local common = require("ux_chrome.render.common")
local util = require("ux_chrome.util")

local M = {}

local function separators(values)
  local style = common.value(values, "buffer_tabs.separator_style", "slant")
  if style == "slant" then return "", "" end
  if style == "slope" then return "", "" end
  if style == "thin" then return "│", "│" end
  if style == "block" then return " ", " " end
  return common.value(values, "buffer_tabs.separator_left", ""),
    common.value(values, "buffer_tabs.separator_right", "")
end

local function state(buffer)
  if buffer.active then
    return buffer.modified and "active_modified" or "active"
  elseif buffer.visible then
    return buffer.modified and "visible_modified" or "visible"
  end
  return buffer.modified and "inactive_modified" or "inactive"
end

local GROUPS = {
  active = "UXChromeTabActive",
  active_modified = "UXChromeTabActiveModified",
  visible = "UXChromeTabVisible",
  visible_modified = "UXChromeTabVisibleModified",
  inactive = "UXChromeTabInactive",
  inactive_modified = "UXChromeTabInactiveModified",
}

local SEPARATORS = {
  active = "UXChromeTabSeparatorActive",
  active_modified = "UXChromeTabSeparatorActive",
  visible = "UXChromeTabSeparatorVisible",
  visible_modified = "UXChromeTabSeparatorVisible",
  inactive = "UXChromeTabSeparatorInactive",
  inactive_modified = "UXChromeTabSeparatorInactive",
}

local function label(buffer, values, maximum)
  local name = util.basename(buffer.name)
  if name == "" then name = "[No Name]" end
  name = util.truncate(name, common.value(values, "buffer_tabs.max_name_length", 18))
  local suffix = ""
  if buffer.modified then suffix = suffix .. " " .. common.value(values, "buffer_tabs.modified_icon", "●") end
  if buffer.active and common.value(values, "buffer_tabs.show_close", true) then
    suffix = suffix .. " " .. common.value(values, "buffer_tabs.close_icon", "×")
  end
  local result = " " .. name .. suffix .. " "
  if maximum then result = util.truncate(result, maximum) end
  return result
end

local function buffer_width(buffer, values, separator)
  return util.display_width(label(buffer, values)) + util.display_width(separator)
end

local function native_tabs(ctx, values, left_separator)
  if not common.value(values, "buffer_tabs.show_tabpages", true) or #(ctx.tabs or {}) <= 1 then
    return {}, 0
  end
  local segments = {}
  for _, tab in ipairs(ctx.tabs or {}) do
    local group = tab.active and "UXChromeNativeTabActive" or "UXChromeNativeTabInactive"
    local text = " " .. tostring(tab.label or ("T" .. tostring(tab.id or "?"))) .. " "
    segments[#segments + 1] = common.segment(group, left_separator, "native_tab_separator")
    segments[#segments + 1] = common.segment(group, text, tab.active and "native_tab_active" or "native_tab_inactive")
  end
  return segments, common.width(segments)
end

local function visible_range(buffers, values, budget, separator)
  if #buffers == 0 then return {}, 0, 0 end
  local active = 1
  for index, buffer in ipairs(buffers) do
    if buffer.active then active = index break end
  end
  local first, last = active, active
  local left_marker = common.value(values, "buffer_tabs.left_trunc_marker", "")
  local right_marker = common.value(values, "buffer_tabs.right_trunc_marker", "")
  local function marker_width(candidate_first, candidate_last)
    local width = 0
    if candidate_first > 1 then width = width + util.display_width(" " .. left_marker .. tostring(candidate_first - 1) .. " ") end
    if candidate_last < #buffers then width = width + util.display_width(" " .. right_marker .. tostring(#buffers - candidate_last) .. " ") end
    return width
  end
  local used = buffer_width(buffers[active], values, separator)
  local turn_left = true
  while first > 1 or last < #buffers do
    local candidate = turn_left and first - 1 or last + 1
    if candidate < 1 or candidate > #buffers then candidate = turn_left and last + 1 or first - 1 end
    if candidate < 1 or candidate > #buffers then break end
    local next_first = math.min(first, candidate)
    local next_last = math.max(last, candidate)
    local next_used = used + buffer_width(buffers[candidate], values, separator)
    if next_used + marker_width(next_first, next_last) > budget then
      if turn_left and last < #buffers then
        turn_left = false
      elseif not turn_left and first > 1 then
        turn_left = true
      else
        break
      end
      local other = turn_left and first - 1 or last + 1
      if other < 1 or other > #buffers
          or used + buffer_width(buffers[other], values, separator)
            + marker_width(math.min(first, other), math.max(last, other)) > budget then
        break
      end
      candidate = other
      next_first = math.min(first, candidate)
      next_last = math.max(last, candidate)
      next_used = used + buffer_width(buffers[candidate], values, separator)
    end
    first, last, used = next_first, next_last, next_used
    turn_left = not turn_left
  end
  return { first = first, last = last }, first - 1, #buffers - last
end

function M.render(ctx, values)
  ctx = ctx or {}
  values = values or {}
  local buffers = ctx.buffers or {}
  local columns = math.max(1, math.floor(tonumber(ctx.columns) or 80))
  local right_separator, left_separator = separators(values)
  local tabs, tabs_width = native_tabs(ctx, values, left_separator)
  local budget = math.max(4, columns - tabs_width)
  local range, hidden_left, hidden_right = visible_range(buffers, values, budget, right_separator)
  local segments = {}

  if hidden_left > 0 then
    segments[#segments + 1] = common.segment(
      "UXChromeTabOverflow",
      " " .. common.value(values, "buffer_tabs.left_trunc_marker", "") .. hidden_left .. " ",
      "overflow"
    )
  end

  if #buffers == 0 then
    segments[#segments + 1] = common.segment("UXChromeTabFill", " [No buffers] ", "empty")
  else
    for index = range.first, range.last do
      local buffer = buffers[index]
      local buffer_state = state(buffer)
      local remaining = math.max(4, budget - common.width(segments))
      segments[#segments + 1] = common.segment(
        GROUPS[buffer_state],
        label(buffer, values, remaining),
        buffer_state,
        "ux.chrome/buffer_tabs/" .. buffer_state .. "/foreground"
      )
      segments[#segments + 1] = common.segment(
        SEPARATORS[buffer_state],
        right_separator,
        "separator_" .. buffer_state
      )
    end
  end

  if hidden_right > 0 then
    segments[#segments + 1] = common.segment(
      "UXChromeTabOverflow",
      " " .. common.value(values, "buffer_tabs.right_trunc_marker", "") .. hidden_right .. " ",
      "overflow"
    )
  end
  segments[#segments + 1] = common.segment("UXChromeTabFill", " ", "fill")
  if #tabs > 0 then
    segments[#segments + 1] = common.control("%=")
    for _, segment in ipairs(tabs) do segments[#segments + 1] = segment end
  end
  local result = common.result(segments, {
    hidden_left = hidden_left,
    hidden_right = hidden_right,
    range = range,
  })
  if result.width > columns and #tabs > 0 then
    local without_tabs = {}
    for _, segment in ipairs(segments) do
      if segment.state ~= "native_tab_separator"
          and segment.state ~= "native_tab_active"
          and segment.state ~= "native_tab_inactive"
          and not (segment.control and segment.text == "%=") then
        without_tabs[#without_tabs + 1] = segment
      end
    end
    segments = without_tabs
    result = common.result(segments, {
      hidden_left = hidden_left,
      hidden_right = hidden_right,
      range = range,
      native_tabs_hidden = true,
    })
  end
  if result.width > columns then
    local excess = result.width - columns
    for _, segment in ipairs(segments) do
      if segment.state == "active" or segment.state == "active_modified" then
        segment.text = util.truncate(segment.text, math.max(1, util.display_width(segment.text) - excess))
        break
      end
    end
    result = common.result(segments, {
      hidden_left = hidden_left,
      hidden_right = hidden_right,
      range = range,
      native_tabs_hidden = #tabs > 0,
    })
  end
  if result.width > columns then
    local priorities = {
      fill = 1,
      overflow = 2,
      empty = 3,
      inactive = 4,
      inactive_modified = 4,
      visible = 5,
      visible_modified = 5,
      active = 7,
      active_modified = 7,
    }
    local shrinkable = {}
    for _, segment in ipairs(segments) do shrinkable[#shrinkable + 1] = segment end
    table.sort(shrinkable, function(left, right)
      if left.control ~= right.control then return not left.control end
      return (priorities[left.state] or (tostring(left.state):match("^separator_") and 6 or 8))
        < (priorities[right.state] or (tostring(right.state):match("^separator_") and 6 or 8))
    end)
    for _, segment in ipairs(shrinkable) do
      if result.width <= columns then break end
      if not segment.control then
        local segment_width = util.display_width(segment.text)
        local target = math.max(0, segment_width - (result.width - columns))
        segment.text = util.truncate(segment.text, target)
        result = common.result(segments, {
          hidden_left = hidden_left,
          hidden_right = hidden_right,
          range = range,
          native_tabs_hidden = #tabs > 0,
        })
      end
    end
  end
  return result
end

return M
