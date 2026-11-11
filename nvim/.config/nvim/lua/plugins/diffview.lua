local review = require("review_popup")

return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview open" },
      { "<leader>gD", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Repo history" },
      { "<leader>gq", "<cmd>DiffviewClose<cr>", desc = "Diffview close" },
    },
    init = function()
      if review.enabled then
        review.setup()
      end
    end,
    opts = function()
      local actions = require("diffview.actions")
      -- In diffview, <S-h>/<S-l> step through the changed files
      local step_files = {
        { "n", "<S-h>", actions.select_prev_entry, { desc = "Open the diff for the previous file" } },
        { "n", "<S-l>", actions.select_next_entry, { desc = "Open the diff for the next file" } },
      }
      local opts = {
        -- Lines that only the old side has show red, not the green of lines
        -- the new side added
        enhanced_diff_hl = true,
        -- Each side's title names its version: a commit, or WORKING TREE
        view = { default = { winbar_info = true }, file_history = { winbar_info = true } },
        keymaps = { view = step_files, file_panel = step_files },
      }
      if review.enabled then
        review.extend_diffview(opts, actions)
      end
      return opts
    end,
  },
  -- No bufferline in the review popups, so diff windows only show diffview's files
  {
    "akinsho/bufferline.nvim",
    cond = not review.enabled,
  },
  -- Search and replace writes to the files directly, past the popup's read-only
  -- buffers
  {
    "MagicDuck/grug-far.nvim",
    cond = not review.enabled,
  },
}
