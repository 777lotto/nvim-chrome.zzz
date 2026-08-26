local defaults = require("ux_chrome.defaults")
local util = require("ux_chrome.util")

local State = {}
State.__index = State

function State.new()
  return setmetatable({
    values = util.deepcopy(defaults.structural_defaults),
    failures = {},
  }, State)
end

function State:get(key)
  return util.deepcopy(self.values[key])
end

function State:all()
  return util.deepcopy(self.values)
end

-- Internal read-only accessor for the render hot path. Callers must not mutate
-- the returned table; use State:all() for anything that escapes the renderer.
function State:raw()
  return self.values
end

function State:snapshot(keys)
  local values = {}
  for _, key in ipairs(keys or util.sorted_keys(self.values)) do
    if self.values[key] == nil then return nil, ("unknown UX Chrome structural key %q"):format(tostring(key)) end
    values[key] = util.deepcopy(self.values[key])
  end
  return values
end

function State:fail_next(stage, message)
  self.failures[stage] = message or ("injected " .. tostring(stage) .. " failure")
end

function State:_failure(stage)
  local message = self.failures[stage]
  self.failures[stage] = nil
  return message
end

function State:apply(changes)
  local failure = self:_failure("apply")
  if failure then return false, failure end
  local candidate = util.deepcopy(self.values)
  for _, change in ipairs(changes or {}) do
    if candidate[change.key] == nil then
      return false, ("unknown UX Chrome structural key %q"):format(tostring(change.key))
    end
    candidate[change.key] = util.deepcopy(change.value)
  end
  self.values = candidate
  return true
end

function State:restore(snapshot)
  local failure = self:_failure("restore")
  if failure then return false, failure end
  local candidate = util.deepcopy(self.values)
  for key, value in pairs(snapshot or {}) do
    if candidate[key] == nil then
      return false, ("unknown UX Chrome structural key %q"):format(tostring(key))
    end
    candidate[key] = util.deepcopy(value)
  end
  self.values = candidate
  return true
end

return State
