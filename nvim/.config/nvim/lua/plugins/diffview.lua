-- Set by the tmux review popups: nvim there only shows one diffview
local review_popup = vim.g.review_popup == 1

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
    opts = function()
      local actions = require("diffview.actions")
      -- In diffview, <S-h>/<S-l> step through the changed files
      local step_files = {
        { "n", "<S-h>", actions.select_prev_entry, { desc = "Open the diff for the previous file" } },
        { "n", "<S-l>", actions.select_next_entry, { desc = "Open the diff for the next file" } },
      }
      local opts = { keymaps = { view = step_files, file_panel = step_files } }
      if review_popup then
        local start_tab = vim.api.nvim_get_current_tabpage()
        opts.hooks = {
          -- Closes the empty [No Name] tab nvim starts with, leaving only the diff
          view_opened = function()
            if vim.api.nvim_tabpage_is_valid(start_tab) and #vim.api.nvim_list_tabpages() > 1 then
              vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(start_tab))
            end
          end,
          -- Closing the last diffview quits nvim and closes the popup; closing a
          -- file history opened on top returns to the diff
          view_closed = function(view)
            for _, other in ipairs(require("diffview.lib").views) do
              if other ~= view and vim.api.nvim_tabpage_is_valid(other.tabpage) then
                return
              end
            end
            vim.cmd("qa")
          end,
        }
      end
      return opts
    end,
  },
  -- No bufferline in the review popups, so diff windows only show diffview's files
  {
    "akinsho/bufferline.nvim",
    cond = not review_popup,
  },
}
