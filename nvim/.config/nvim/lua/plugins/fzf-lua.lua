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
    -- In the tmux review popup a picked file opens in a new tab: opening it in
    -- the current window would swap it into the diff. `true` keeps the other
    -- default file actions, which any key set here would otherwise replace.
    if vim.g.review_popup == 1 then
      opts.actions = vim.tbl_deep_extend("force", opts.actions or {}, {
        files = { true, ["enter"] = require("fzf-lua.actions").file_tabedit },
      })
    end
  end,
}
