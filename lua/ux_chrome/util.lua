local M = {}

function M.deepcopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do
    result[M.deepcopy(key, seen)] = M.deepcopy(item, seen)
  end
  return setmetatable(result, getmetatable(value))
end

function M.merge(base, override)
  local result = M.deepcopy(base or {})
  for key, value in pairs(override or {}) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = M.merge(result[key], value)
    else
      result[key] = M.deepcopy(value)
    end
  end
  return result
end

function M.sorted_keys(value)
  local result = {}
  for key in pairs(value or {}) do result[#result + 1] = key end
  table.sort(result)
  return result
end

function M.clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function M.status_escape(value)
  return tostring(value or ""):gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end

function M.display_width(value)
  value = tostring(value or "")
  if vim and vim.fn and vim.fn.strdisplaywidth then
    return vim.fn.strdisplaywidth(value)
  end
  return #value
end

function M.truncate(value, maximum, marker)
  value = tostring(value or "")
  maximum = math.max(0, math.floor(tonumber(maximum) or 0))
  marker = tostring(marker or "…")
  if M.display_width(value) <= maximum then return value end
  if maximum == 0 then return "" end
  local marker_width = M.display_width(marker)
  if marker_width >= maximum then
    return vim and vim.fn and vim.fn.strcharpart
      and vim.fn.strcharpart(marker, 0, 1)
      or marker:sub(1, maximum)
  end
  local budget = maximum - marker_width
  local result = {}
  local width = 0
  local characters = vim and vim.fn and vim.fn.strchars and vim.fn.strchars(value) or #value
  for index = 0, characters - 1 do
    local character = vim and vim.fn and vim.fn.strcharpart
      and vim.fn.strcharpart(value, index, 1)
      or value:sub(index + 1, index + 1)
    local character_width = M.display_width(character)
    if width + character_width > budget then break end
    result[#result + 1] = character
    width = width + character_width
  end
  return table.concat(result) .. marker
end

function M.basename(path)
  path = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
  if path == "" then return "" end
  return path:match("([^/]+)$") or path
end

function M.split_path(path)
  local result = {}
  path = tostring(path or ""):gsub("\\", "/")
  for part in path:gmatch("[^/]+") do result[#result + 1] = part end
  return result
end

function M.inspect_error(err)
  if type(err) == "table" then
    return err.code and (err.code .. ": " .. tostring(err.message))
      or (vim and vim.inspect and vim.inspect(err) or tostring(err))
  end
  return tostring(err)
end

return M
