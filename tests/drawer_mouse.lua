-- A real attached UI is required to exercise native mouse hit testing.
local h = require("tests.helpers")
h.test("native divider drag resizes the drawer and status click toggles it", function()
  local responses, serial = {}, 0
  local unpack = vim.mpack.Unpacker()
  local channel = vim.fn.jobstart({ vim.v.progpath, "--embed", "-u", "tests/minimal_init.lua" }, {
    on_stdout = function(_, chunks)
      for index, chunk in ipairs(chunks) do chunks[index] = chunk:gsub("\n", "\0") end
      local data, position = table.concat(chunks, "\n"), 1
      while position <= #data do
        local message
        message, position = unpack(data, position)
        if message and message[1] == 1 then responses[message[2]] = message end
      end
    end,
  })
  local function call(method, ...)
    serial = serial + 1
    local id = serial
    vim.fn.chansend(channel, vim.mpack.encode({ 0, id, method, { ... } }))
    assert(vim.wait(3000, function() return responses[id] ~= nil end), "RPC timeout: " .. method)
    local response = responses[id]
    responses[id] = nil
    assert(response[3] == vim.NIL, vim.inspect(response[3]))
    return response[4]
  end
  local function lua(code, ...) return call("nvim_exec_lua", code, { ... }) end
  local ok, err = xpcall(function()
    call("nvim_ui_attach", 120, 40, { rgb = true, ext_linegrid = true })
    lua([[
      vim.opt.runtimepath:prepend(...)
      vim.o.mouse = "a"
      require("ux_chrome").setup({ ownership = { statusline = "ux" } })
      require("ux_chrome.commands").setup()
      local drawer = require("ux_chrome.drawer")
      drawer.register({ id = "test.mouse", label = "Mouse logs" })
      drawer.append("test.mouse", { "fixture output", { text = "fixture error", level = "error" } })
      drawer.open("test.mouse")
      vim.cmd("redraw!")
    ]], h.dependency_root("UX_FOUNDATION_ROOT", "UX-foundation.nvim"))
    local win = lua("return require('ux_chrome.drawer').inspect().window")
    local height = call("nvim_win_get_height", win)
    local position = call("nvim_win_get_position", win)
    local row = position[1] - 1
    call("nvim_input_mouse", "left", "press", "", 0, row, 30)
    call("nvim_input_mouse", "left", "drag", "", 0, row - 3, 30)
    call("nvim_input_mouse", "left", "release", "", 0, row - 3, 30)
    lua("vim.cmd('redraw!')")
    h.equal(call("nvim_win_get_height", win), height + 3)
    lua("require('ux_chrome.drawer').close(); require('ux_chrome.drawer').open(); vim.cmd('redraw!')")
    h.equal(lua("return vim.api.nvim_win_get_height(require('ux_chrome.drawer').inspect().window)"), height + 3)
    local status = lua([[
      return vim.api.nvim_eval_statusline(require('ux_chrome').statusline(), { maxwidth = 120 }).str
    ]])
    local column = vim.fn.strdisplaywidth(status:sub(1, assert(status:find("Logs", 1, true)) - 1))
    call("nvim_input_mouse", "left", "press", "", 0, 38, column)
    call("nvim_input_mouse", "left", "release", "", 0, 38, column)
    h.truthy(lua("return vim.wait(1000, function() return not require('ux_chrome.drawer').status().open end)"))
  end, debug.traceback)
  vim.fn.jobstop(channel)
  if not ok then error(err) end
end)
h.finish()
