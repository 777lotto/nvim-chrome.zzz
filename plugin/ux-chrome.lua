if vim.g.loaded_ux_chrome then return end
vim.g.loaded_ux_chrome = true

require("ux_chrome.commands").setup()
