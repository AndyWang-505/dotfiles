local review = require("review_popup")

return {
  "ibhagwan/fzf-lua",
  opts = function(_, opts)
    -- `files` already defaults to hidden = true; only grep needs the flag, and
    -- `--hidden` alone makes rg descend into .git
    opts.grep = vim.tbl_deep_extend("force", opts.grep or {}, {
      -- fzf-lua blanks RIPGREP_CONFIG_PATH by default, which drops ~/.ripgreprc
      RIPGREP_CONFIG_PATH = vim.env.RIPGREP_CONFIG_PATH,
      rg_opts = "--hidden -g '!.git' --column --line-number --no-heading "
        .. "--color=always --smart-case --max-columns=4096 -e",
    })

    if review.enabled then
      -- From the review popup's diff tab, a pick (and gd / gr, which jump
      -- straight to a single result) opens in a new tab instead of inside the
      -- diff's layout. Elsewhere it behaves as usual. `true` keeps the other
      -- default actions, which any key set here would otherwise replace.
      local actions = require("fzf-lua.actions")
      local function from_diff_in_tab(action)
        return function(selected, picker_opts)
          return (review.in_diff_tab() and actions.file_tabedit or action)(selected, picker_opts)
        end
      end
      local picks = {
        true,
        ["enter"] = from_diff_in_tab(actions.file_edit_or_qf),
        ["ctrl-s"] = from_diff_in_tab(actions.file_split),
        ["ctrl-v"] = from_diff_in_tab(actions.file_vsplit),
        -- LazyVim's Trouble list would open its picks in the diff too
        ["ctrl-t"] = actions.file_tabedit,
      }
      opts.actions = vim.tbl_deep_extend("force", opts.actions or {}, { files = picks, buffers = picks })
      opts.lsp = vim.tbl_deep_extend("force", opts.lsp or {}, { jump1_action = from_diff_in_tab(actions.file_edit) })
    end
  end,
}
