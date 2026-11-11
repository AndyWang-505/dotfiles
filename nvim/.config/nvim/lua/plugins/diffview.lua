-- Set by the tmux review popups: nvim there only shows one diffview
local review_popup = vim.g.review_popup == 1

-- The review popup's three views, switched with 1 / 2 / 3. review.sh passes the
-- branch's fork point and base; without them only the uncommitted changes can
-- be shown.
local review_modes = {
  { name = "branch", key = "1", label = "Branch diff" },
  { name = "uncommitted", key = "2", label = "Uncommitted" },
  { name = "commits", key = "3", label = "Commits" },
}

local function review_mode(mode)
  local fork, base = vim.g.review_fork, vim.g.review_base
  local lib = package.loaded["diffview.lib"]
  local old_views = lib and vim.list_slice(lib.views) or {}
  -- Switching between the two diffs stays on the file being read
  local current = old_views[1] and old_views[1]:infer_cur_file()
  local selected = current and current.path
    and " --selected-file=" .. vim.fn.fnameescape(old_views[1].adapter.ctx.toplevel .. "/" .. current.path)
    or ""

  local command
  if mode == "uncommitted" then
    command = "DiffviewOpen" .. selected
  elseif not fork then
    vim.notify("No base branch found, so only the uncommitted changes can be shown", vim.log.levels.WARN)
    return
  elseif mode == "branch" then
    command = "DiffviewOpen " .. fork .. selected
  else
    -- Merges are left out: one that brought the base in would list every
    -- change the base made since the fork
    local count = vim.trim(vim.fn.system({ "git", "rev-list", "--count", "--no-merges", fork .. "..HEAD" }))
    if count == "0" then
      vim.notify("No commits since forking from " .. base, vim.log.levels.WARN)
      return
    end
    command = "DiffviewFileHistory --range=" .. fork .. "..HEAD --no-merges"
  end

  -- The new view opens before the old ones close, so closing them is not
  -- closing the last diffview, which quits the popup
  vim.cmd(command)
  for _, view in ipairs(old_views) do
    view:close()
    require("diffview.lib").dispose_view(view)
  end
  vim.g.review_mode = mode
  vim.cmd.redrawtabline()
end

-- The popup has no bufferline, so the tabline shows which view is open, the
-- base and whether editing is on
function _G.ReviewTabline()
  local parts = {}
  for _, mode in ipairs(review_modes) do
    local highlight = mode.name == vim.g.review_mode and "%#TabLineSel#" or "%#TabLine#"
    table.insert(parts, highlight .. " " .. mode.key .. " " .. mode.label .. " ")
  end
  local base = vim.g.review_base and "since forking from " .. vim.g.review_base or "no base branch"
  local editing = vim.g.review_editable and "editing (<leader>ge: read-only)" or "read-only (<leader>ge: edit)"
  local tabs = vim.fn.tabpagenr("$") > 1 and "  |  tab %{tabpagenr()}/%{tabpagenr('$')}" or ""
  -- %< makes a narrow popup cut the details on the right, not the modes
  return table.concat(parts) .. "%#TabLineFill#%<  " .. base .. "  |  " .. editing .. tabs
end

-- Edits in the popup land in the real files, so their buffers start
-- read-only; <leader>ge toggles that for every file at once. Diffview's own
-- buffers (panels, old versions) are never editable and are left alone.
local function apply_editable(bufnr)
  if vim.bo[bufnr].buftype == "" then
    vim.bo[bufnr].modifiable = vim.g.review_editable == true
  end
end

local function toggle_editable()
  vim.g.review_editable = not vim.g.review_editable
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      apply_editable(bufnr)
    end
  end
  vim.cmd.redrawtabline()
end

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
      if review_popup then
        vim.api.nvim_create_user_command("ReviewMode", function(command)
          review_mode(command.args)
        end, { nargs = 1, complete = function() return { "branch", "uncommitted", "commits" } end })
        vim.o.showtabline = 2
        vim.o.tabline = "%!v:lua.ReviewTabline()"

        vim.api.nvim_create_autocmd("BufWinEnter", {
          callback = function(event)
            apply_editable(event.buf)
            if vim.bo[event.buf].buftype == "" then
              vim.keymap.set("n", "<leader>ge", toggle_editable, { buffer = event.buf, desc = "Review: toggle editing" })
            end
          end,
        })
      end
    end,
    opts = function()
      local actions = require("diffview.actions")
      -- In diffview, <S-h>/<S-l> step through the changed files
      local step_files = {
        { "n", "<S-h>", actions.select_prev_entry, { desc = "Open the diff for the previous file" } },
        { "n", "<S-l>", actions.select_next_entry, { desc = "Open the diff for the next file" } },
      }
      local mode_keys = {}
      local opts = {}
      if review_popup then
        -- Only in diffview's windows, so counts still work in a tab opened from
        -- a search. Buffer-local, so <leader>ge wins over any global mapping
        -- LazyVim sets after the plugins load
        for _, mode in ipairs(review_modes) do
          table.insert(mode_keys, { "n", mode.key, function() review_mode(mode.name) end, { desc = "Review: " .. mode.label } })
        end
        table.insert(mode_keys, { "n", "<leader>ge", toggle_editable, { desc = "Review: toggle editing" } })
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
      local with_steps = vim.list_extend(vim.list_slice(step_files), mode_keys)
      -- The commit list keeps diffview's own L, which shows the commit message
      opts.keymaps = { view = with_steps, file_panel = with_steps, file_history_panel = mode_keys }
      return opts
    end,
  },
  -- No bufferline in the review popups, so diff windows only show diffview's files
  {
    "akinsho/bufferline.nvim",
    cond = not review_popup,
  },
}
