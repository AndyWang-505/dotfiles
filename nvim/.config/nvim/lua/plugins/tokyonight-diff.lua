return {
  "folke/tokyonight.nvim",
  opts = {
    on_highlights = function(hl, colors)
      hl.DiffAdd = { bg = "#1e3a2a" }
      hl.DiffDelete = { bg = "#4a1e2a" }
      hl.DiffChange = { bg = "#2a3a5a" }
      hl.DiffText = { bg = "#3e5a8a", bold = true }
      -- Diffview's titles naming each side's version; the dim default for
      -- unfocused windows is near the background
      hl.WinBar = { fg = colors.blue, bold = true }
      hl.WinBarNC = hl.WinBar
    end,
  },
}
