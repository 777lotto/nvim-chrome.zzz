-- Optional integration against the distribution's installed/pinned backend.
local h = require("tests.helpers")
vim.opt.runtimepath:prepend(assert(vim.env.UX_FOUNDATION_ROOT))
vim.opt.runtimepath:prepend(assert(vim.env.UX_MARKDOWN_ROOT))
if vim.env.UX_PARSER_ROOT then vim.opt.runtimepath:prepend(vim.env.UX_PARSER_ROOT) end
require("ux_foundation").setup({ load_active = false })
require("render-markdown").setup({ render_modes = true, anti_conceal = { enabled = false } })
local panes = require("ux_chrome.panes")
local api = vim.api

h.test("real Markdown backend renders plugin filetypes and streamed updates", function()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "chrome-test-document"
  api.nvim_buf_set_lines(buf, 0, -1, false, { "# Shared heading", "", "A **strong** word." })
  local win = api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 60, height = 10 })
  panes.attach({ id = "fixture.markdown", role = "context", content = "markdown", window = win, buffer = buf })
  local ns = api.nvim_get_namespaces()["render-markdown.nvim"]
  h.truthy(ns, "backend did not initialize")
  h.truthy(vim.wait(2000, function()
    vim.cmd.redraw()
    return #api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) > 0
  end), "backend did not decorate the custom filetype: " .. vim.inspect(panes.inspect(win)))
  h.equal(vim.bo[buf].filetype, "chrome-test-document")
  api.nvim_buf_set_lines(buf, 0, -1, false, { "Plain text", "", "", "## Streamed heading" })
  h.truthy(vim.wait(2000, function()
    vim.cmd.redraw()
    for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})) do
      if mark[2] == 3 then return true end
    end
    return false
  end), "backend did not render streamed content")
  assert(panes.teardown())
  api.nvim_win_close(win, true)
  api.nvim_buf_delete(buf, { force = true })
end)

h.finish()
