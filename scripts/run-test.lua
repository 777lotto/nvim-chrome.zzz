local test_file = vim.env.UX_CHROME_TEST_FILE

if not test_file or test_file == "" then
  io.stderr:write("UX_CHROME_TEST_FILE must name a test file\n")
  vim.cmd("cquit 2")
  return
end

local ok, failure = xpcall(function()
  dofile(test_file)
end, debug.traceback)

if not ok then
  io.stderr:write(failure .. "\n")
  vim.cmd("cquit 1")
  return
end

vim.cmd("quitall!")
