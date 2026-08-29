local M = {}

local function supported(version)
  return version.major > 0
    or version.minor > 12
    or (version.minor == 12 and version.patch >= 2)
end

function M.report()
  local chrome = require("ux_chrome")
  local state = chrome.state()
  local foundation_ok, foundation = pcall(require, "ux_foundation")
  local report = {
    version = chrome.version,
    neovim = vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
    neovim_supported = supported(vim.version()),
    foundation_available = foundation_ok and foundation.contract_version == 1,
    foundation_contract = foundation_ok and foundation.contract_version or nil,
    initialized = state.initialized,
    plugin_id = state.plugin_id,
    registered = state.initialized and state.plugin_id == "ux.chrome",
    restoration_capable = state.initialized and type(chrome.teardown) == "function",
    surfaces = state.surfaces or {},
    last_error = state.last_error,
  }
  report.ok = report.neovim_supported and report.foundation_available and report.last_error == nil
  return report
end

function M.check()
  local report = M.report()
  vim.health.start("UX Chrome")
  local version = vim.version()
  if supported(version) then
    vim.health.ok("Neovim " .. report.neovim .. " (supported; minimum 0.12.2)")
  else
    vim.health.error("Neovim 0.12.2 or newer is required; running " .. report.neovim)
  end
  if report.foundation_available then
    vim.health.ok("UX Foundation schema v1 is available")
  else
    vim.health.error("UX Foundation schema v1 is unavailable")
  end
  if report.initialized then
    vim.health.ok("UX Chrome is initialized")
  else
    vim.health.info("UX Chrome has not been set up in this session")
  end
  if report.registered then
    vim.health.ok("ux.chrome is registered and teardown restoration is available")
  elseif report.initialized then
    vim.health.error("UX Chrome is initialized without an active ux.chrome registration")
  end
  for surface, status in pairs(report.surfaces) do
    if status.active then
      vim.health.ok(surface .. " is active")
    else
      vim.health.info(surface .. " is deferred: " .. tostring(status.reason or "inactive"))
    end
  end
  if report.last_error then vim.health.error("Last refresh failed: " .. tostring(report.last_error)) end
end

return M
