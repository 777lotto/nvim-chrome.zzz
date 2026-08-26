local util = require("ux_chrome.util")

local M = {}

function M.number(ctx)
  ctx = ctx or {}
  if (tonumber(ctx.virtnum) or 0) ~= 0 or (ctx.number == false and ctx.relativenumber == false) then
    return ""
  end
  local lnum = tonumber(ctx.lnum) or 0
  local relnum = tonumber(ctx.relnum) or 0
  local value = ctx.relativenumber and relnum > 0 and relnum or lnum
  local width = math.max(1, math.floor(tonumber(ctx.numberwidth) or 4))
  local group = relnum == 0 and "UXChromeLineNumberCurrent" or "UXChromeLineNumber"
  return ("%%#%s#%" .. width .. "d"):format(group, value)
end

function M.expression(values)
  local separator = util.status_escape((values or {})["gutter.separator"] or "│")
  -- %{%...%}, not %{...}: Vim re-parses the result of %{%...%} as statusline
  -- syntax, which is what makes the returned "%#Group#" prefix an actual
  -- highlight switch. With plain %{} it is printed as literal text.
  return "%#UXChromeGutterFold#%C%#UXChromeGutterSign#%s%="
    .. "%{%v:lua.require'ux_chrome'.statuscolumn()%}"
    .. "%#UXChromeGutterSeparator#" .. separator
end

return M
