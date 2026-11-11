-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.autoformat = false

-- In diffs, the side without a line shows ╱ in its place
vim.opt.fillchars:append({ diff = "╱" })
