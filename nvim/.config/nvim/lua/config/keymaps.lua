-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Keymaps that only some repos need live in
-- config/local.lua, which this repo does not track.
pcall(require, "config.local")

-- tmux collapses <C-/> into a bare `/`, so bind the terminal toggle to a plain
-- ASCII control character that survives tmux and ssh
vim.keymap.set({ "n", "t" }, "<C-t>", function()
  Snacks.terminal.focus(nil, { cwd = LazyVim.root() })
end, { desc = "Terminal (Root Dir)" })
