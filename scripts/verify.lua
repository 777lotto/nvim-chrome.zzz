-- Run each suite in an isolated editor. Dependencies are read-only checkouts.
local function dependency(name, sibling)
  local path = vim.env[name]
  if not path or path == "" then path = vim.fs.joinpath(vim.fn.getcwd(), "..", sibling) end
  assert(vim.fn.isdirectory(path) == 1, "Set " .. name .. " to its dependency checkout")
  return vim.fn.fnamemodify(path, ":p")
end
local function run(args, env)
  local result = vim.system(args, { text = true, env = env }):wait()
  io.stdout:write(result.stdout or "")
  io.stderr:write(result.stderr or "")
  assert(result.code == 0, "Failed: " .. table.concat(args, " "))
end
local ok, err = xpcall(function()
  local env = {
    UX_FOUNDATION_ROOT = dependency("UX_FOUNDATION_ROOT", "UX-foundation.nvim"),
    UX_STYLING_ROOT = dependency("UX_STYLING_ROOT", "UX-styling.nvim"),
  }
  run({ vim.v.progpath, "--headless", "--clean", "-l", "scripts/check-lua.lua", "." })
  run({ "bash", "scripts/test-release-tested.sh" })
  for _, suite in ipairs({ "unit", "render", "smoke", "foundation_integration", "styling_integration" }) do
    env.UX_CHROME_TEST_FILE = "tests/" .. suite .. ".lua"
    run({ vim.v.progpath, "--headless", "-u", "tests/minimal_init.lua", "-l", "scripts/run-test.lua" }, env)
  end
  run({ vim.v.progpath, "--headless", "-u", "tests/minimal_init.lua", "-c", "helptags doc", "-c", "quit" })
  run({ "git", "diff", "--check" })
  run({ "git", "diff", "--exit-code", "--", "doc/tags" })
end, debug.traceback)
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
print("All verification gates passed")
