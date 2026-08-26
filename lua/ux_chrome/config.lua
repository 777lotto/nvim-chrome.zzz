local defaults = require("ux_chrome.defaults")
local util = require("ux_chrome.util")

local M = {}

local ALIASES = {
  auto = "auto",
  ux = "ux",
  takeover = "ux",
  external = "external",
  off = "external",
}

local function ownership_value(value, path)
  if value == true then return "ux" end
  if value == false then return "external" end
  if type(value) ~= "string" or not ALIASES[value] then
    error(("%s must be auto, ux, or external"):format(path), 3)
  end
  return ALIASES[value]
end

function M.normalize(opts)
  if opts == nil then opts = {} end
  if type(opts) ~= "table" then error("ux_chrome.setup() expects a table", 3) end
  if opts.foundation ~= nil and type(opts.foundation) ~= "table" then
    error("ux_chrome.setup().foundation must be a table", 3)
  end
  if opts.ownership ~= nil and type(opts.ownership) ~= "table" then
    error("ux_chrome.setup().ownership must be a table", 3)
  end
  local result = {
    enabled = opts.enabled ~= false,
    foundation = util.deepcopy(opts.foundation or {}),
    ownership = util.deepcopy(defaults.ownership),
  }
  local provided = util.deepcopy(opts.ownership or {})
  if provided.splits ~= nil and provided.windows == nil then provided.windows = provided.splits end
  for key in pairs(provided) do
    if defaults.ownership[key] == nil and key ~= "splits" then
      error(("ux_chrome.setup().ownership contains unknown surface %q"):format(tostring(key)), 3)
    end
  end
  for key in pairs(defaults.ownership) do
    if provided[key] ~= nil then
      result.ownership[key] = ownership_value(provided[key], "ownership." .. key)
    end
  end
  return result
end

function M.ownership_value(value)
  return ownership_value(value, "ownership mode")
end

return M
