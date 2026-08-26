local common = require("ux_chrome.render.common")
local util = require("ux_chrome.util")

local M = {}

function M.render(ctx, values)
  ctx = ctx or {}
  values = values or {}
  local parts = util.split_path(ctx.name)
  if #parts == 0 then parts = { "[No Name]" } end
  local max_depth = common.value(values, "winbar.max_depth", 4)
  local hidden = math.max(0, #parts - max_depth)
  local first = hidden + 1
  local segments = {}
  local base_group = ctx.active == false and "UXChromeWinbarInactive" or "UXChromeWinbarActive"
  if hidden > 0 then
    segments[#segments + 1] = common.segment("UXChromeWinbarSeparator", " … ", "overflow")
  end
  for index = first, #parts do
    if index > first then
      segments[#segments + 1] = common.segment(
        "UXChromeWinbarSeparator",
        common.value(values, "winbar.separator", " › "),
        "separator"
      )
    end
    local group = index == #parts and ctx.active ~= false and "UXChromeWinbarCurrent" or base_group
    segments[#segments + 1] = common.segment(group, parts[index], index == #parts and "current" or "parent")
  end
  if ctx.modified then
    segments[#segments + 1] = common.segment("UXChromeWinbarModified", " ●", "modified")
  end
  local width = math.max(1, math.floor(tonumber(ctx.width) or 80))
  while common.width(segments) > width do
    local parent_index
    for index, segment in ipairs(segments) do
      if segment.state == "parent" then parent_index = index break end
    end
    if not parent_index then break end
    table.remove(segments, parent_index)
    if segments[parent_index] and segments[parent_index].state == "separator" then
      table.remove(segments, parent_index)
    elseif segments[parent_index - 1] and segments[parent_index - 1].state == "separator" then
      table.remove(segments, parent_index - 1)
    end
    hidden = hidden + 1
  end
  if common.width(segments) > width then
    for index = #segments, 1, -1 do
      if segments[index].state == "modified" then
        table.remove(segments, index)
        break
      end
    end
  end
  local current
  for _, segment in ipairs(segments) do
    if segment.state == "current" then current = segment break end
  end
  if current and common.width(segments) > width then
    local fixed = common.width(segments) - util.display_width(current.text)
    if fixed >= width then
      for index = #segments, 1, -1 do
        if segments[index].state == "overflow" then
          table.remove(segments, index)
          break
        end
      end
      fixed = common.width(segments) - util.display_width(current.text)
    end
    current.text = util.truncate(current.text, math.max(0, width - fixed))
  end
  return common.result(segments, { hidden = hidden })
end

return M
