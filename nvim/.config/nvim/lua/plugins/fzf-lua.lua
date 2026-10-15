return {
  "ibhagwan/fzf-lua",
  opts = {
    -- `files` already defaults to hidden = true; only grep needs the flag, and
    -- `--hidden` alone makes rg descend into .git
    grep = {
      -- fzf-lua blanks RIPGREP_CONFIG_PATH by default, which drops ~/.ripgreprc
      RIPGREP_CONFIG_PATH = vim.env.RIPGREP_CONFIG_PATH,
      rg_opts = "--hidden -g '!.git' --column --line-number --no-heading "
        .. "--color=always --smart-case --max-columns=4096 -e",
    },
  },
}
