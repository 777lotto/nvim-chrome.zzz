local root = arg[1] or "."
local files = vim.fn.globpath(root, "**/*.lua", false, true)
local failures = {}

table.sort(files)

for _, path in ipairs(files) do
  local chunk, message = loadfile(path)
  if not chunk then
    failures[#failures + 1] = ("%s: %s"):format(path, message)
  end
end

if #files == 0 then
  io.stderr:write(("no Lua files found below %s\n"):format(root))
  vim.cmd("cquit 1")
  return
elseif #failures > 0 then
  io.stderr:write("Lua compilation failed:\n" .. table.concat(failures, "\n") .. "\n")
  vim.cmd("cquit 1")
  return
end

print(("Lua compilation passed for %d files"):format(#files))
vim.cmd("quitall!")
