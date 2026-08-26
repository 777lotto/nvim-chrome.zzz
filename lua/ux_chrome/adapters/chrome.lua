local util = require("ux_chrome.util")

local M = {}

local REQUIRED_METHODS = {
  "get_value",
  "adapter_snapshot",
  "adapter_apply",
  "adapter_restore",
  "adapter_rerender",
}

local function copy(value)
  return util.deepcopy(value)
end

local function invoke(controller, method, ...)
  return controller[method](controller, ...)
end

function M.new(controller)
  if type(controller) ~= "table" then
    error("ux_chrome.adapters.chrome.new() expects a controller table")
  end
  for _, method in ipairs(REQUIRED_METHODS) do
    if type(controller[method]) ~= "function" then
      error("Chrome controller is missing method: " .. method)
    end
  end

  local adapter = {}

  function adapter.probe()
    return {
      available = true,
      capabilities = {
        adapter_id = "ux_chrome",
        batched_apply = true,
        exact_restore = true,
        managed_renderer = true,
        redraw_only_rerender = true,
        rollback = true,
      },
    }
  end

  function adapter.get(_, key)
    local value, err = invoke(controller, "get_value", key)
    if value == nil then return nil, err end
    return copy(value)
  end

  function adapter.snapshot(_, keys)
    local value, err = invoke(controller, "adapter_snapshot", copy(keys))
    if value == nil then return nil, err end
    return copy(value)
  end

  function adapter.apply(_, changes)
    return invoke(controller, "adapter_apply", copy(changes))
  end

  function adapter.restore(ctx, snapshot)
    return invoke(controller, "adapter_restore", copy(snapshot), copy(ctx))
  end

  function adapter.rerender(_, keys)
    return invoke(controller, "adapter_rerender", copy(keys))
  end

  return adapter
end

return M
