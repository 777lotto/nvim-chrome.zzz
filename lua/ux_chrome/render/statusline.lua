local common = require("ux_chrome.render.common")
local util = require("ux_chrome.util")

local M = {}

local MODE_MAP = {
  n = { "normal", "NORMAL" }, no = { "normal", "O-PENDING" }, nov = { "normal", "O-PENDING" },
  noV = { "normal", "O-PENDING-LINE" }, ["no\22"] = { "normal", "O-PENDING-BLOCK" },
  niI = { "normal", "NORMAL" }, niR = { "normal", "NORMAL" }, niV = { "normal", "NORMAL" },
  nt = { "normal", "N-TERMINAL" }, ntT = { "normal", "N-TERMINAL" },
  i = { "insert", "INSERT" }, ic = { "insert", "INSERT" }, ix = { "insert", "INSERT" },
  v = { "visual", "VISUAL" }, V = { "visual", "V-LINE" }, ["\22"] = { "visual", "V-BLOCK" },
  vs = { "visual", "VISUAL" }, Vs = { "visual", "V-LINE" }, ["\22s"] = { "visual", "V-BLOCK" },
  s = { "visual", "SELECT" }, S = { "visual", "S-LINE" }, ["\19"] = { "visual", "S-BLOCK" },
  R = { "replace", "REPLACE" }, Rc = { "replace", "REPLACE" }, Rx = { "replace", "REPLACE" },
  Rv = { "replace", "V-REPLACE" }, Rvc = { "replace", "V-REPLACE" },
  Rvx = { "replace", "V-REPLACE" },
  c = { "command", "COMMAND" }, cr = { "command", "COMMAND" },
  cv = { "command", "EX" }, cvr = { "command", "EX" }, ce = { "command", "EX" },
  r = { "command", "PROMPT" }, rm = { "command", "MORE" }, ["r?"] = { "command", "CONFIRM" },
  ["!"] = { "command", "SHELL" },
  t = { "terminal", "TERMINAL" },
}

function M.mode(value)
  return MODE_MAP[value] or { "normal", tostring(value or "NORMAL"):upper() }
end

local function add(segments, group, text, state)
  segments[#segments + 1] = common.segment(group, text, state)
end

local function right_items(ctx, values)
  local items = {}
  if common.value(values, "statusline.show_encoding", true) and ctx.encoding and ctx.encoding ~= "" then
    items[#items + 1] = { priority = 1, text = ctx.encoding, state = "encoding" }
  end
  if ctx.fileformat and ctx.fileformat ~= "" then
    items[#items + 1] = { priority = 2, text = ctx.fileformat, state = "fileformat" }
  end
  if common.value(values, "statusline.show_filetype", true) and ctx.filetype and ctx.filetype ~= "" then
    items[#items + 1] = { priority = 3, text = ctx.filetype, state = "filetype" }
  end
  if common.value(values, "statusline.show_progress", true) then
    local total = math.max(1, tonumber(ctx.total_lines) or 1)
    local line = util.clamp(tonumber(ctx.line) or 1, 1, total)
    items[#items + 1] = {
      priority = 5,
      text = ("%d%%"):format(math.floor((line / total) * 100)),
      state = "progress",
      group = "UXChromeStatusProgress",
    }
  end
  if common.value(values, "statusline.show_ruler", true) then
    items[#items + 1] = {
      priority = 6,
      text = ("%d:%d"):format(tonumber(ctx.line) or 1, tonumber(ctx.column) or 1),
      state = "ruler",
      group = "UXChromeStatusProgress",
    }
  end
  return items
end

function M.render(ctx, values)
  ctx = ctx or {}
  values = values or {}
  local width = math.max(1, math.floor(tonumber(ctx.width) or 80))
  local name = util.basename(ctx.name)
  if name == "" then name = "[No Name]" end
  if ctx.active == false then
    local left = { common.segment("UXChromeStatusInactive", " " .. name .. " ", "inactive") }
    local right = common.segment(
      "UXChromeStatusInactive",
      (" %d:%d "):format(tonumber(ctx.line) or 1, tonumber(ctx.column) or 1),
      "inactive_ruler"
    )
    local right_width = util.display_width(right.text)
    if right_width >= width then
      right.text = util.truncate(right.text, width)
      return common.result({ right }, { active = false, mode = "inactive" })
    end
    left[1].text = util.truncate(left[1].text, width - right_width)
    left[#left + 1] = common.control("%=")
    left[#left + 1] = right
    return common.result(left, { active = false, mode = "inactive" })
  end

  local mode = M.mode(ctx.mode)
  local mode_id, mode_label = mode[1], mode[2]
  local compact = width < 48
  local segments = {}
  if common.value(values, "statusline.show_mode", true) then
    local rendered_mode = compact and (" " .. mode_label:sub(1, 1) .. " ") or (" " .. mode_label .. " ")
    add(segments, "UXChromeStatusMode" .. mode_id:gsub("^%l", string.upper), rendered_mode, mode_id)
    add(segments, "UXChromeStatusSeparator" .. mode_id:gsub("^%l", string.upper),
      common.value(values, "statusline.section_separator_left", ""), "mode_separator")
  end

  local primary_segment = common.segment("UXChromeStatusPrimary", " ", "primary")
  segments[#segments + 1] = primary_segment
  local filename_segment = common.segment("UXChromeStatusBody", name .. " ", "filename")
  segments[#segments + 1] = filename_segment
  if ctx.modified then add(segments, "UXChromeStatusModified", compact and "+" or " + ", "modified") end
  if ctx.readonly then add(segments, "UXChromeStatusReadonly", compact and "RO" or " RO ", "readonly") end

  local right = right_items(ctx, values)
  local separator = compact and " "
    or (" " .. common.value(values, "statusline.component_separator", "│") .. " ")
  local item_padding = compact and "" or " "
  local section_separator = common.value(values, "statusline.section_separator_right", "")
  local show_section_separator = #right > 0
  local function right_width()
    local result = show_section_separator and util.display_width(section_separator) or 0
    for index, item in ipairs(right) do
      result = result + util.display_width(item_padding .. item.text .. item_padding)
      if index > 1 then result = result + util.display_width(separator) end
    end
    return result
  end
  local function remove_lowest_right()
    if #right == 0 then return false end
    local remove_index = 1
    for index = 2, #right do
      if right[index].priority < right[remove_index].priority then remove_index = index end
    end
    table.remove(right, remove_index)
    return true
  end
  while #right > 2 and common.width(segments) + right_width() > width do
    remove_lowest_right()
  end

  local function fixed_left_width()
    return common.width(segments) - util.display_width(filename_segment.text)
  end
  local function remove_left_state(wanted)
    for index = #segments, 1, -1 do
      if segments[index].state == wanted then
        table.remove(segments, index)
        return true
      end
    end
    return false
  end
  for _, wanted in ipairs({ "readonly", "modified", "primary", "mode_separator", mode_id }) do
    if fixed_left_width() + right_width() <= width then break end
    remove_left_state(wanted)
  end
  if fixed_left_width() + right_width() > width and show_section_separator then
    show_section_separator = false
  end
  while fixed_left_width() + right_width() > width and remove_lowest_right() do
    if #right == 0 then show_section_separator = false end
  end
  local filename_budget = math.max(0, width - fixed_left_width() - right_width())
  filename_segment.text = util.truncate(filename_segment.text, filename_budget)
  segments[#segments + 1] = common.control("%=")
  if show_section_separator then
    add(segments, "UXChromeStatusInfo", section_separator, "right_section_separator")
  end
  for index, item in ipairs(right) do
    if index > 1 then add(segments, "UXChromeStatusInfo", separator, "component_separator") end
    add(segments, item.group or "UXChromeStatusInfo", item_padding .. item.text .. item_padding, item.state)
  end
  return common.result(segments, { active = true, mode = mode_id, right_items = right })
end

return M
