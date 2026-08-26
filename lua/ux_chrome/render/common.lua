local util = require("ux_chrome.util")

local M = {}

function M.segment(group, text, state, property_id)
  return {
    group = group,
    text = tostring(text or ""),
    state = state,
    property_id = property_id,
  }
end

function M.control(text)
  return { control = true, text = tostring(text or "") }
end

function M.width(segments)
  local width = 0
  for _, segment in ipairs(segments or {}) do
    if not segment.control then width = width + util.display_width(segment.text) end
  end
  return width
end

function M.compose(segments)
  local result = {}
  for _, segment in ipairs(segments or {}) do
    if segment.control then
      result[#result + 1] = segment.text
    else
      result[#result + 1] = "%#" .. segment.group .. "#" .. util.status_escape(segment.text)
    end
  end
  result[#result + 1] = "%*"
  return table.concat(result)
end

function M.result(segments, meta)
  local result = meta or {}
  result.segments = segments
  result.width = M.width(segments)
  result.text = M.compose(segments)
  return result
end

function M.value(values, key, fallback)
  local value = values and values[key]
  if value == nil then return fallback end
  return value
end

return M
