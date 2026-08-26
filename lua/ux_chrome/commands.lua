local M = {}

local SURFACES = { "all", "tabline", "statusline", "winbar", "statuscolumn", "windows", "scrollbar" }

local function complete(_, line)
  local prefix = line:match("(%S*)$") or ""
  local result = {}
  for _, item in ipairs(SURFACES) do
    if item:sub(1, #prefix) == prefix then result[#result + 1] = item end
  end
  return result
end

local function notify_error(err)
  local message = type(err) == "table" and (err.message or vim.inspect(err)) or tostring(err)
  vim.notify("UX Chrome: " .. message, vim.log.levels.ERROR)
end

local function run(callback)
  local ok, value, err = pcall(callback)
  if not ok then notify_error(value) return end
  if value == false or value == nil then notify_error(err or "operation failed") end
end

local function command(name, callback, opts)
  pcall(vim.api.nvim_del_user_command, name)
  vim.api.nvim_create_user_command(name, callback, opts or {})
end

function M.setup()
  command("UXChromeEnable", function(args)
    run(function() return require("ux_chrome").enable(args.args, args.bang) end)
  end, { nargs = "?", bang = true, complete = complete, desc = "Enable a UX Chrome surface" })
  command("UXChromeDisable", function(args)
    run(function() return require("ux_chrome").disable(args.args) end)
  end, { nargs = "?", complete = complete, desc = "Restore a UX Chrome surface" })
  command("UXChromeToggle", function(args)
    run(function() return require("ux_chrome").toggle(args.args, args.bang) end)
  end, { nargs = "?", bang = true, complete = complete, desc = "Toggle a UX Chrome surface" })
  command("UXChromeRefresh", function() run(function() return require("ux_chrome").refresh() end) end,
    { desc = "Refresh UX Chrome" })
  command("UXChromeReset", function() run(function() return require("ux_chrome").reset() end) end,
    { desc = "Reset UX Chrome presentation values to declared defaults" })
  command("UXChromeDebug", function()
    vim.notify(vim.inspect(require("ux_chrome").debug()), vim.log.levels.INFO)
  end, { desc = "Inspect UX Chrome state" })
  command("UXChromeHealth", function()
    vim.cmd("checkhealth ux_chrome")
  end, { desc = "Inspect UX Chrome health" })

  for _, item in ipairs({
    { "UXChromeBufferNext", "next" },
    { "UXChromeBufferPrev", "prev" },
    { "UXChromeBufferFirst", "first" },
    { "UXChromeBufferLast", "last" },
  }) do
    command(item[1], function() run(function() return require("ux_chrome").select_buffer(item[2]) end) end,
      { desc = item[1]:gsub("UXChrome", "UX Chrome ") })
  end
  command("UXChromeBufferClose", function() run(function() return require("ux_chrome").close_buffer() end) end,
    { desc = "Close the current buffer" })
  command("UXChromeBufferMoveLeft", function() run(function() return require("ux_chrome").move_buffer(-1) end) end,
    { desc = "Move current buffer left in UX Chrome order" })
  command("UXChromeBufferMoveRight", function() run(function() return require("ux_chrome").move_buffer(1) end) end,
    { desc = "Move current buffer right in UX Chrome order" })
  return true
end

return M
