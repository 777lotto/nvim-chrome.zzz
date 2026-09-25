local adapter = require("ux_chrome.adapters.chrome")
local config = require("ux_chrome.config")
local Controller = require("ux_chrome.controller")
local defaults = require("ux_chrome.defaults")
local fixture_catalog = require("ux_chrome.fixtures")
local manifest_builder = require("ux_chrome.manifest")
local util = require("ux_chrome.util")

local M = {
  contract_version = 1,
  version = defaults.version,
}

local runtime

local function load_foundation(opts)
  local ok, foundation = pcall(require, "ux_foundation")
  if not ok then
    error("UX Chrome requires UX-foundation.nvim schema v1: " .. tostring(foundation), 3)
  end
  if foundation.contract_version ~= 1 then
    error(("UX Chrome requires Foundation contract 1, found %s"):format(
      tostring(foundation.contract_version)
    ), 3)
  end
  foundation.setup(opts or {})
  return foundation
end

local function describe(err)
  return util.inspect_error(err)
end

local function instance()
  if not runtime then M.setup() end
  return runtime
end

function M.setup(opts)
  if runtime and opts == nil then
    local ok, err = runtime.controller:refresh("repeat_setup")
    if not ok then error(describe(err), 2) end
    return M
  end
  local normalized = config.normalize(opts)
  if runtime then
    runtime.foundation.setup(normalized.foundation)
    local ok, err = runtime.controller:reconfigure(normalized)
    if not ok then error(describe(err), 2) end
    runtime.config = normalized
    return M
  end

  local foundation = load_foundation(normalized.foundation)
  local controller = Controller.new(normalized)
  local manifest = manifest_builder.build()
  local implementation = {
    adapters = {
      ux_chrome = adapter.new(controller),
    },
  }
  local handle, err = foundation.register(manifest, implementation)
  if not handle then error("UX Chrome registration failed: " .. describe(err), 2) end

  runtime = {
    foundation = foundation,
    controller = controller,
    config = normalized,
    handle = handle,
    manifest = manifest,
  }
  local started
  started, err = controller:start()
  if not started then
    controller.tearing_down = true
    controller:stop()
    foundation.unregister(handle)
    controller.tearing_down = false
    runtime = nil
    error("UX Chrome setup failed: " .. describe(err), 2)
  end
  return M
end

function M.refresh()
  return instance().controller:refresh("manual")
end

function M.teardown()
  local components = package.loaded["ux_chrome.components"]
  if components then
    local ok, err = components.teardown()
    if not ok then return false, err end
  end
  local panes = package.loaded["ux_chrome.panes"]
  if panes then
    local ok, err = panes.teardown()
    if not ok then return false, err end
  end
  if not runtime then return true end
  local current = runtime
  current.controller.tearing_down = true
  local stopped, stop_error = current.controller:stop()
  if not stopped then
    current.controller.tearing_down = false
    return false, stop_error
  end
  local ok, err = current.foundation.unregister(current.handle)
  if not ok then
    current.controller.tearing_down = false
    current.controller:start()
    return false, err
  end
  runtime = nil
  return true
end

-- Pane-only consumers do not initialize or acquire editor-wide surfaces.
function M.attach(spec) return require("ux_chrome.panes").attach(spec) end
function M.detach(window) return require("ux_chrome.panes").detach(window) end

-- Internal ownership handoff before a pane captures its opening options.
function M._prepare_pane(window)
  if not runtime then return true end
  for _, surface in ipairs({ "statusline", "winbar", "statuscolumn", "windows" }) do
    local ok, err = runtime.controller:_release_window(window, surface, "explicit plugin pane")
    if not ok then return false, err end
  end
  return true
end

function M.reset()
  local current = instance()
  local transaction, err = current.foundation.begin_transaction()
  if not transaction then return false, err end
  local ok
  ok, err = transaction:reset({ plugin_id = "ux.chrome" })
  if not ok then
    transaction:revert()
    transaction:commit()
    return false, err
  end
  return transaction:commit()
end

local function surface_name(surface)
  if surface == nil or surface == "" or surface == "all" then return nil end
  if surface == "splits" then return "windows" end
  return surface
end

local function surfaces()
  return { "tabline", "statusline", "winbar", "statuscolumn", "windows", "scrollbar" }
end

local function set_mode(surface, mode)
  local current = instance()
  surface = surface_name(surface)
  if surface then
    return current.controller:set_ownership(surface, mode)
  else
    return current.controller:set_all_ownership(mode)
  end
end

function M.enable(surface, force)
  return set_mode(surface, force == true and "ux" or "auto")
end

function M.disable(surface)
  return set_mode(surface, "external")
end

function M.toggle(surface, force)
  local current = instance()
  surface = surface_name(surface)
  if surface then
    return current.controller:toggle(surface, force == true)
  else
    local enable = false
    for _, name in ipairs(surfaces()) do
      if current.controller.config.ownership[name] == "external" then enable = true break end
    end
    return current.controller:set_all_ownership(
      enable and (force and "ux" or "auto") or "external"
    )
  end
end

function M.state()
  if not runtime then
    return {
      initialized = false,
      contract_version = M.contract_version,
      version = M.version,
    }
  end
  local result = runtime.controller:public_state()
  result.initialized = true
  result.contract_version = M.contract_version
  result.version = M.version
  result.plugin_id = runtime.manifest.plugin.id
  return result
end

function M.debug()
  local result = M.state()
  result.manifest = M.manifest()
  result.fixture_ids = fixture_catalog.ids()
  if runtime then result.foundation = runtime.foundation.state() end
  return result
end

function M.manifest()
  return manifest_builder.build()
end

function M.fixtures()
  return fixture_catalog.all()
end

function M.tabline()
  return instance().controller:tabline()
end

function M.statusline()
  return instance().controller:statusline()
end

function M.winbar()
  return instance().controller:winbar()
end

function M.statuscolumn()
  return instance().controller:statuscolumn()
end

function M.foldtext()
  return instance().controller:foldtext()
end

function M.select_buffer(which)
  return instance().controller:select_buffer(which)
end

function M.move_buffer(delta)
  return instance().controller:move_buffer(delta)
end

function M.close_buffer()
  return instance().controller:close_buffer()
end

function M.health()
  return require("ux_chrome.health").report()
end

function M._set_ownership(surface, mode)
  return set_mode(surface, mode)
end

function M._inject_failure_for_tests(stage, message)
  instance().controller:inject_failure(stage, message)
end

function M._controller_for_tests()
  return instance().controller
end

function M._reset_for_tests()
  return M.teardown()
end

return M
