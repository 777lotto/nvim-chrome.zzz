local M = {}

local GROUP = "UXChromeLifecycle"

-- Events that can change surface ownership, window or buffer topology, or the
-- physical options Chrome manages. These are deliberate, comparatively rare
-- actions, so a full reconciliation is affordable here.
M.reconcile_events = {
  "BufAdd",
  "BufDelete",
  "DirChanged",
  "TabClosed",
  "TabEnter",
  "TabNewEntered",
  "VimResized",
  "WinClosed",
  "WinEnter",
  "WinLeave",
  "WinNew",
}

-- High-frequency editing events. Neovim re-evaluates the 'statusline',
-- 'winbar' and 'statuscolumn' expressions itself on redraw, so these must not
-- reconcile ownership. They only refresh scrollbar geometry.
M.redraw_events = {
  "CursorMoved",
  "CursorMovedI",
  "ModeChanged",
  "TextChanged",
  "TextChangedI",
  "TextChangedP",
  "TextChangedT",
  "WinScrolled",
}

-- Buffer presentation the tabline must show but which Neovim does not redraw on
-- its own. Cheap redraw plus an explicit tabline redraw.
M.tabline_events = {
  "BufEnter",
  "BufModifiedSet",
  "BufWritePost",
}

-- Options whose value decides whether a surface is externally owned, plus the
-- buffer flag that invalidates the cached buffer order.
M.watched_options = {
  "buflisted",
  "fillchars",
  "statuscolumn",
  "statusline",
  "tabline",
  "winbar",
  "winhighlight",
}

function M.setup(controller)
  local api = vim.api
  local group = api.nvim_create_augroup(GROUP, { clear = true })

  api.nvim_create_autocmd(M.reconcile_events, {
    group = group,
    callback = function(event)
      controller:request_refresh(event.event or "lifecycle")
    end,
    desc = "Reconcile UX Chrome surface ownership",
  })

  api.nvim_create_autocmd(M.redraw_events, {
    group = group,
    callback = function(event)
      controller:request_redraw(event.event or "lifecycle")
    end,
    desc = "Refresh UX Chrome scrollbar geometry",
  })

  api.nvim_create_autocmd(M.tabline_events, {
    group = group,
    callback = function(event)
      controller:request_redraw(event.event or "lifecycle", true)
    end,
    desc = "Redraw the UX Chrome tabline after buffer presentation changes",
  })

  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function(event)
      controller:request_refresh(event.event or "ColorScheme")
    end,
    desc = "Redraw UX Chrome after colorscheme replay",
  })

  api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = M.watched_options,
    callback = function(event)
      -- Chrome's own option writes raise OptionSet. Without this guard every
      -- reconcile scheduled a second, redundant reconcile of its own echo.
      if controller.refreshing then return end
      if event.match == "buflisted" then controller:invalidate_buffer_order() end
      controller:request_refresh(event.event or "OptionSet")
    end,
    desc = "Reconcile UX Chrome surface ownership after an option change",
  })

  api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "UXFoundationApplied", "UXFoundationAvailabilityChanged" },
    callback = function(event)
      controller:request_refresh(event.event or "User")
    end,
    desc = "Redraw UX Chrome after Foundation changes",
  })

  return group
end

function M.teardown(group)
  if group then pcall(vim.api.nvim_del_augroup_by_id, group) end
end

return M
