local util = require("ux_chrome.util")

local M = {}

function M.render(ctx)
  ctx = ctx or {}
  local text = tostring(ctx.text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", " ")
  if text == "" then text = "[empty fold]" end
  local count = math.max(1, (tonumber(ctx.finish) or 1) - (tonumber(ctx.start) or 1) + 1)
  return util.truncate((" %s  …  %d lines "):format(text, count), tonumber(ctx.width) or 80)
end

return M
