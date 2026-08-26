local M = {
  passed = 0,
  failed = 0,
}

function M.equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error((message or "values differ")
      .. "\nexpected: " .. vim.inspect(expected)
      .. "\nactual:   " .. vim.inspect(actual), 2)
  end
end

function M.truthy(value, message)
  if not value then error(message or "expected a truthy value", 2) end
  return value
end

function M.contains(value, needle, message)
  local text = tostring(value or "")
  if not text:find(needle, 1, true) then
    error(message or ("expected %q to contain %q"):format(text, needle), 2)
  end
end

function M.error_code(err, expected, message)
  M.equal(type(err), "table", message or "expected a structured error")
  M.equal(err.code, expected, message or "unexpected error code")
end

function M.test(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  if ok then
    M.passed = M.passed + 1
    print("ok - " .. name)
  else
    M.failed = M.failed + 1
    io.stderr:write("not ok - " .. name .. "\n" .. tostring(err) .. "\n")
  end
end

function M.finish()
  if M.failed > 0 then
    error(("%d tests failed; %d passed"):format(M.failed, M.passed))
  end
  print(("all %d tests passed"):format(M.passed))
end

function M.assert_plain(value, path, seen)
  path = path or "value"
  local kind = type(value)
  if kind == "function" or kind == "thread" or kind == "userdata" then
    error(path .. " contains executable or opaque data: " .. kind, 2)
  end
  if kind ~= "table" then return end
  if getmetatable(value) ~= nil then error(path .. " contains a metatable", 2) end
  seen = seen or {}
  if seen[value] then error(path .. " contains a cycle", 2) end
  seen[value] = true
  for key, item in pairs(value) do
    M.assert_plain(key, path .. ".<key>", seen)
    M.assert_plain(item, path .. "." .. tostring(key), seen)
  end
  seen[value] = nil
end

function M.assert_json(value, path)
  M.assert_plain(value, path)
  local ok, err = pcall(vim.json.encode, value)
  if not ok then error((path or "value") .. " is not JSON-safe: " .. tostring(err), 2) end
end

function M.values(items, key)
  local result = {}
  for _, item in ipairs(items or {}) do result[#result + 1] = item[key] end
  return result
end

function M.set(items, key)
  local result = {}
  for _, item in ipairs(items or {}) do result[item[key] or item] = true end
  return result
end

function M.find_registration(foundation, plugin_id)
  for _, registration in ipairs(foundation.registrations()) do
    local manifest = registration.manifest or registration
    if manifest.plugin and manifest.plugin.id == plugin_id then return registration end
  end
end

function M.find_component(manifest, component_id)
  for _, component in ipairs((manifest or {}).components or {}) do
    if component.id == component_id then return component end
  end
end

function M.first_property(manifest, predicate)
  for _, component in ipairs((manifest or {}).components or {}) do
    for _, state in ipairs(component.states or {}) do
      for _, property in ipairs(state.properties or {}) do
        if not predicate or predicate(component, state, property) then
          return table.concat({ manifest.plugin.id, component.id, state.id, property.id }, "/"),
            component, state, property
        end
      end
    end
  end
end

function M.module_keys(prefix)
  local result = {}
  for name in pairs(package.loaded) do
    if name == prefix or vim.startswith(name, prefix .. ".") then result[#result + 1] = name end
  end
  table.sort(result)
  return result
end

function M.dependency_root(environment_name, sibling_name)
  local configured = vim.env[environment_name]
  if configured and configured ~= "" then return vim.fn.fnamemodify(configured, ":p") end
  local chrome_root = vim.g.ux_chrome_root
    or vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
  return vim.fs.joinpath(vim.fs.dirname(chrome_root), sibling_name)
end

function M.snapshot_options()
  local windows = {}
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    windows[window] = {
      statusline = vim.api.nvim_get_option_value("statusline", { win = window }),
      statusline_local = vim.api.nvim_get_option_value("statusline", { win = window, scope = "local" }),
      winbar = vim.api.nvim_get_option_value("winbar", { win = window }),
      winbar_local = vim.api.nvim_get_option_value("winbar", { win = window, scope = "local" }),
      statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { win = window }),
      statuscolumn_local = vim.api.nvim_get_option_value("statuscolumn", { win = window, scope = "local" }),
      foldtext = vim.api.nvim_get_option_value("foldtext", { win = window }),
      foldtext_local = vim.api.nvim_get_option_value("foldtext", { win = window, scope = "local" }),
      winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = window }),
      winhighlight_local = vim.api.nvim_get_option_value("winhighlight", { win = window, scope = "local" }),
      fillchars = vim.api.nvim_get_option_value("fillchars", { win = window }),
      fillchars_local = vim.api.nvim_get_option_value("fillchars", { win = window, scope = "local" }),
    }
  end
  return {
    tabline = vim.o.tabline,
    showtabline = vim.o.showtabline,
    statusline = vim.api.nvim_get_option_value("statusline", { scope = "global" }),
    laststatus = vim.o.laststatus,
    winbar = vim.api.nvim_get_option_value("winbar", { scope = "global" }),
    fillchars = vim.o.fillchars,
    windows = windows,
  }
end

function M.assert_options(snapshot, message)
  local current = M.snapshot_options()
  M.equal(current, snapshot, message or "editor options were not restored exactly")
end

return M
