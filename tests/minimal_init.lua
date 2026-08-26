local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":p:h:h")
local test_root = vim.fn.tempname()

for _, directory in ipairs({ "config", "data", "state", "cache" }) do
  vim.fn.mkdir(vim.fs.joinpath(test_root, directory), "p")
end

vim.env.XDG_CONFIG_HOME = vim.fs.joinpath(test_root, "config")
vim.env.XDG_DATA_HOME = vim.fs.joinpath(test_root, "data")
vim.env.XDG_STATE_HOME = vim.fs.joinpath(test_root, "state")
vim.env.XDG_CACHE_HOME = vim.fs.joinpath(test_root, "cache")

vim.o.loadplugins = false
vim.opt.runtimepath = { root, vim.env.VIMRUNTIME }
vim.opt.packpath = { root }
package.path = root .. "/?.lua;" .. package.path
vim.opt.shadafile = "NONE"
vim.opt.swapfile = false

vim.g.ux_chrome_test_root = test_root
vim.g.ux_chrome_root = root
