-- The nvim side of the tmux review popup (tmux/.config/tmux/scripts/review.sh),
-- which starts nvim with g:review_popup, g:review_fork and g:review_base.
-- Everything here is off in a normal nvim.
local M = {}

M.enabled = vim.g.review_popup == 1

M.modes = {
  { name = "branch", key = "1", label = "Branch diff" },
  { name = "uncommitted", key = "2", label = "Uncommitted" },
  { name = "commits", key = "3", label = "Commits" },
}

local function warn(message)
  vim.notify(message, vim.log.levels.WARN)
end

function M.in_diff_tab()
  return package.loaded["diffview.lib"] ~= nil and require("diffview.lib").get_current_view() ~= nil
end

function M.switch(mode)
  local fork, base = vim.g.review_fork, vim.g.review_base
  local old_views = package.loaded["diffview.lib"] and vim.list_slice(require("diffview.lib").views) or {}
  local current = old_views[1] and old_views[1]:infer_cur_file()
  local selected = current
      and " --selected-file=" .. vim.fn.fnameescape(old_views[1].adapter.ctx.toplevel .. "/" .. current.path)
    or ""

  local command
  if mode == "uncommitted" then
    command = "DiffviewOpen" .. selected
  elseif not fork then
    return warn("No base branch found, so only the uncommitted changes can be shown")
  elseif mode == "branch" then
    command = "DiffviewOpen " .. fork .. selected
  else
    -- A merge that brought the base in would list every change the base made
    local range = fork .. "..HEAD"
    if vim.trim(vim.fn.system({ "git", "rev-list", "--count", "--no-merges", range })) == "0" then
      return warn("No commits since forking from " .. base)
    end
    command = "DiffviewFileHistory --range=" .. range .. " --no-merges"
  end

  -- Open first: closing the last diffview quits the popup
  vim.cmd(command)
  for _, view in ipairs(old_views) do
    view:close()
    require("diffview.lib").dispose_view(view)
  end
  vim.g.review_mode = mode
  vim.cmd.redrawtabline()
end

-- Edits would land in the real files, so file buffers start read-only.
-- Diffview's own buffers (panels, old versions) are never editable.
local function apply_editing(bufnr)
  if vim.bo[bufnr].buftype == "" then
    vim.bo[bufnr].modifiable = vim.g.review_editable == true
  end
end

function M.toggle_editing()
  vim.g.review_editable = not vim.g.review_editable
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      apply_editing(bufnr)
    end
  end
  vim.cmd.redrawtabline()
end

-- Diffview's restore and stage keys write to the files or the index without
-- going through a buffer, so read-only has to stop them itself
local function when_editing(action)
  return function()
    if vim.g.review_editable then
      return action()
    end
    warn("Read-only: <leader>ge to enable editing first")
  end
end

function M.tabline()
  local parts = {}
  for _, mode in ipairs(M.modes) do
    local highlight = mode.name == vim.g.review_mode and "%#TabLineSel#" or "%#TabLine#"
    table.insert(parts, ("%s %s %s "):format(highlight, mode.key, mode.label))
  end
  local base = vim.g.review_base and "since forking from " .. vim.g.review_base:gsub("%%", "%%%%") or "no base branch"
  local editing = vim.g.review_editable and "editing (<leader>ge: read-only)" or "read-only (<leader>ge: edit)"
  local tabs = vim.fn.tabpagenr("$") > 1 and "  |  tab %{tabpagenr()}/%{tabpagenr('$')}" or ""
  -- %< cuts the details, not the modes, when the popup is narrow
  return table.concat(parts) .. "%#TabLineFill#%<  " .. base .. "  |  " .. editing .. tabs
end

local function mode_keys()
  local keys = {}
  for _, mode in ipairs(M.modes) do
    table.insert(keys, {
      "n",
      mode.key,
      function()
        M.switch(mode.name)
      end,
      { desc = "Review: " .. mode.label },
    })
  end
  table.insert(keys, { "n", "<leader>ge", M.toggle_editing, { desc = "Review: toggle editing" } })
  return keys
end

function M.setup()
  vim.api.nvim_create_user_command("ReviewMode", function(command)
    M.switch(command.args)
  end, {
    nargs = 1,
    complete = function()
      return vim.tbl_map(function(mode)
        return mode.name
      end, M.modes)
    end,
  })
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require'review_popup'.tabline()"

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
    desc = "Review popup: read-only files and mode keys",
    callback = function(event)
      -- BufReadPost catches files an LSP rename loads without showing them
      apply_editing(event.buf)
      if event.event ~= "BufWinEnter" then
        return
      end
      if vim.bo[event.buf].buftype == "" then
        vim.keymap.set("n", "<leader>ge", M.toggle_editing, { buffer = event.buf, desc = "Review: toggle editing" })
      elseif vim.api.nvim_buf_get_name(event.buf):match("^diffview://") then
        -- An empty view shows diffview://null, which diffview's keymaps skip
        for _, key in ipairs(mode_keys()) do
          vim.keymap.set(key[1], key[2], key[3], vim.tbl_extend("force", key[4], { buffer = event.buf }))
        end
      end
    end,
  })
end

-- Adds the popup's keys and hooks to diffview's opts. The keys are
-- buffer-local in diffview's windows only, so counts still work in other tabs
-- and they win over LazyVim's global mappings, which it sets after the plugins.
function M.extend_diffview(opts, actions)
  local keys = mode_keys()
  local function guarded(key, action, desc)
    return { "n", key, when_editing(action), { desc = desc } }
  end
  local keymaps = opts.keymaps
  keymaps.view = vim.list_extend(vim.list_slice(keymaps.view), keys)
  keymaps.file_panel = vim.list_extend(vim.list_slice(keymaps.file_panel), keys)
  vim.list_extend(keymaps.file_panel, {
    guarded("-", actions.toggle_stage_entry, "Stage / unstage the selected entry"),
    guarded("s", actions.toggle_stage_entry, "Stage / unstage the selected entry"),
    guarded("S", actions.stage_all, "Stage all entries"),
    guarded("U", actions.unstage_all, "Unstage all entries"),
    guarded("X", actions.restore_entry, "Restore entry to the state on the left side"),
  })
  -- No <S-h>/<S-l> here: the commit list keeps diffview's own L (commit message)
  keymaps.file_history_panel = vim.list_extend(mode_keys(), {
    guarded("X", actions.restore_entry, "Restore file to the state from the selected entry"),
  })

  local start_tab = vim.api.nvim_get_current_tabpage()
  opts.hooks = {
    -- Leaves only the diff, not the empty tab nvim starts with
    view_opened = function()
      if vim.api.nvim_tabpage_is_valid(start_tab) and #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(start_tab))
      end
    end,
    -- Closing the last diffview closes the popup
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

return M
