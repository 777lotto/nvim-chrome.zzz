-- Shared output drawer. Providers publish cached text; rendering never runs I/O.
local api = vim.api
local panes = require("ux_chrome.panes")
local util = require("ux_chrome.util")
local M = {}
local providers, tabs = {}, {}
local group, pending, generation = nil, false, 0
local levels = { debug = true, info = true, warn = true, error = true }
local render, update, counts
local owned_options = { "winbar", "winfixheight", "scrolloff", "statusline" }
local namespace = api.nvim_create_namespace("UXChromeDrawer")

local function fail(message) error("ux_chrome.drawer: " .. message, 3) end
local function current() return api.nvim_get_current_tabpage() end
local function live(state)
  return state.window and api.nvim_win_is_valid(state.window)
    and api.nvim_win_get_buf(state.window) == state.buffer
end
local function state_for(tab)
  if not tabs[tab] then
    tabs[tab] = { height = 10, follow = true, filter = "", seen = {}, unread = 0, errors = 0 }
    counts(tabs[tab])
  end
  return tabs[tab]
end
local function ids()
  local result = vim.tbl_keys(providers)
  table.sort(result)
  return result
end
local function source(id)
  if not providers[id] then fail("unknown provider: " .. tostring(id)) end
  return providers[id]
end
local function release_window(state)
  if state.window and api.nvim_win_is_valid(state.window) then
    local attached = panes.inspect(state.window)
    if attached and attached.buffer == state.buffer then panes.detach(state.window) end
    for _, name in ipairs(owned_options) do
      if state.opening and state.applied and vim.wo[state.window][name] == state.applied[name] then
        vim.wo[state.window][name] = state.opening[name]
      end
    end
  end
  state.opening, state.applied = nil, nil
end
local function redraw()
  vim.cmd("redrawstatus")
end
counts = function(state)
  state.unread, state.errors = 0, 0
  for id, provider in pairs(providers) do
    for _, entry in ipairs(provider.entries) do
      if entry.sequence > (state.seen[id] or 0) then
        state.unread = state.unread + 1
        if entry.level == "error" then state.errors = state.errors + 1 end
      end
    end
  end
end
local function queue()
  if pending then return end
  pending = true
  local ticket = generation
  vim.schedule(function()
    if ticket ~= generation then return end
    pending = false
    update()
  end)
end
local function pause_if_scrolled(state)
  if not live(state) or not state.follow then return end
  local cursor = api.nvim_win_get_cursor(state.window)[1]
  local bottom = api.nvim_win_call(state.window, function() return vim.fn.line("w$") end)
  if cursor < api.nvim_buf_line_count(state.buffer) or bottom < api.nvim_buf_line_count(state.buffer) then
    state.follow = false
    return true
  end
  return false
end
local function initialize()
  if group then return end
  group = api.nvim_create_augroup("UXChromeDrawer", { clear = true })
  api.nvim_create_autocmd({ "CursorMoved", "WinScrolled" }, { group = group, callback = function()
    for _, state in pairs(tabs) do
      if pause_if_scrolled(state) then queue() end
    end
  end })
  api.nvim_create_autocmd("WinResized", { group = group, callback = function()
    for _, state in pairs(tabs) do
      if live(state) then state.height = api.nvim_win_get_height(state.window) end
    end
  end })
  api.nvim_create_autocmd("WinLeave", { group = group, callback = function()
    for _, state in pairs(tabs) do
      if live(state) then state.height = api.nvim_win_get_height(state.window) end
    end
  end })
  api.nvim_create_autocmd("WinClosed", { group = group, callback = function(event)
    for _, state in pairs(tabs) do
      if state.window == tonumber(event.match) then
        release_window(state)
        state.window = nil
      end
    end
    queue()
  end })
  api.nvim_create_autocmd("BufWinEnter", { group = group, callback = function()
    for _, state in pairs(tabs) do
      if state.window and not live(state) then
        release_window(state)
        state.window = nil
      end
    end
  end })
  api.nvim_create_autocmd("TabEnter", { group = group, callback = queue })
  api.nvim_create_autocmd("TabClosed", { group = group, callback = function()
    for tab, state in pairs(tabs) do
      if not api.nvim_tabpage_is_valid(tab) then
        tabs[tab] = nil
        if state.buffer and api.nvim_buf_is_valid(state.buffer) then
          api.nvim_buf_delete(state.buffer, { force = true })
        end
      end
    end
  end })
end

function M.register(spec)
  if type(spec) ~= "table" or type(spec.id) ~= "string"
      or not spec.id:match("^[a-z][a-z0-9_]*%.[a-z0-9_.]+$") then fail("stable dotted id required") end
  for segment in (spec.id .. "."):gmatch("(.-)%.") do
    if not segment:match("^[a-z][a-z0-9_]*$") then fail("invalid id segment") end
  end
  if spec.label ~= nil and (type(spec.label) ~= "string" or spec.label:find("[%c]")) then
    fail("label must be a single line")
  end
  local limit = spec.limit or 5000
  if type(limit) ~= "number" or limit < 1 or limit > 50000 or limit % 1 ~= 0 then
    fail("limit must be an integer from 1 to 50000")
  end
  for _, name in ipairs({ "refresh", "clear" }) do
    if spec[name] ~= nil and type(spec[name]) ~= "function" then fail(name .. " must be a function") end
  end
  if providers[spec.id] then fail("provider already registered: " .. spec.id) end
  initialize()
  state_for(current())
  providers[spec.id] = {
    id = spec.id, label = spec.label or spec.id, limit = limit,
    refresh = spec.refresh, clear = spec.clear, entries = {}, sequence = 0,
  }
  queue()
  return spec.id
end

local function normalize(entries)
  if type(entries) == "string" or (type(entries) == "table" and entries.text ~= nil) then entries = { entries } end
  if type(entries) ~= "table" or not vim.islist(entries) then fail("entries must be a list or string") end
  local result = {}
  for _, entry in ipairs(entries) do
    if type(entry) == "string" then entry = { text = entry } end
    if type(entry) ~= "table" or type(entry.text) ~= "string" then fail("entry text must be a string") end
    local level = entry.level or "info"
    if not levels[level] then fail("invalid entry level") end
    for _, line in ipairs(vim.split(entry.text, "\n", { plain = true })) do
      result[#result + 1] = { text = line:gsub("[%z\1-\8\11-\31\127]", " "), level = level }
    end
  end
  return result
end
local function publish(provider, entries, replace)
  local normalized = normalize(entries) -- validate atomically before changing state
  if replace then provider.entries = {} end
  for _, entry in ipairs(normalized) do
    provider.sequence = provider.sequence + 1
    entry.sequence = provider.sequence
    provider.entries[#provider.entries + 1] = entry
  end
  if #provider.entries > provider.limit then
    provider.entries = vim.list_slice(provider.entries, #provider.entries - provider.limit + 1)
  end
  queue()
  return true
end
function M.append(id, entries) return publish(source(id), entries, false) end
function M.replace(id, entries) return publish(source(id), entries, true) end

function M.providers()
  local result = {}
  for _, id in ipairs(ids()) do
    local provider = providers[id]
    result[#result + 1] = { id = id, label = provider.label, count = #provider.entries }
  end
  return result
end

function M.refresh(id)
  local state = state_for(current())
  local provider = source(id or state.selected)
  if provider.refresh then
    local entries = provider.refresh()
    if entries ~= nil then M.replace(provider.id, entries) end
  end
  return true
end

function M.clear()
  local state = state_for(current())
  local provider = source(state.selected)
  if provider.clear then provider.clear() end
  provider.entries = {}
  queue()
  return true
end

local function selected(state)
  if not providers[state.selected] then state.selected = ids()[1] end
  return providers[state.selected]
end
local function header(state)
  local provider = providers[state.selected]
  local label = provider and provider.label or "No sources"
  return " " .. util.status_escape(label) .. " | " .. (state.follow and "Following" or "Paused")
    .. (state.filter ~= "" and " | Filter: " .. util.status_escape(state.filter) or "")
    .. " %= [s] source  [f] follow  [F] filter  [r] refresh  [C] clear  [q] close "
end

render = function(tab, state)
  if not live(state) then return end
  local provider = selected(state)
  local lines, sequences, highlights = {}, {}, {}
  if provider then
    for _, entry in ipairs(provider.entries) do
      if state.filter == "" or entry.text:lower():find(state.filter:lower(), 1, true) then
        lines[#lines + 1] = entry.text
        sequences[#sequences + 1] = entry.sequence
        if entry.level == "error" or entry.level == "warn" then
          highlights[#highlights + 1] = { row = #lines - 1, group = entry.level == "error" and "DiagnosticError" or "DiagnosticWarn" }
        end
      end
    end
  end
  if #lines == 0 then lines = { provider and "(no output)" or "(no sources registered)" } end
  local view = api.nvim_win_call(state.window, vim.fn.winsaveview)
  local old_sequences = state.sequences or {}
  local function relocate(row)
    local anchor = old_sequences[row]
    if anchor then
      for index, sequence in ipairs(sequences) do if sequence >= anchor then return index end end
    end
    return math.min(row, #lines)
  end
  if not vim.deep_equal(lines, api.nvim_buf_get_lines(state.buffer, 0, -1, false)) then
    vim.bo[state.buffer].modifiable = true
    api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
    vim.bo[state.buffer].modifiable = false
    vim.bo[state.buffer].modified = false
  end
  api.nvim_buf_clear_namespace(state.buffer, namespace, 0, -1)
  for _, highlight in ipairs(highlights) do
    api.nvim_buf_set_extmark(state.buffer, namespace, highlight.row, 0,
      { end_row = highlight.row + 1, hl_group = highlight.group, hl_eol = true })
  end
  state.sequences = sequences
  if state.follow then
    api.nvim_win_set_cursor(state.window, { #lines, 0 })
    api.nvim_win_call(state.window, function() vim.cmd("normal! zb") end)
    if tab == current() and provider and state.filter == "" then state.seen[provider.id] = provider.sequence end
  else
    view.lnum, view.topline = relocate(view.lnum), relocate(view.topline)
    api.nvim_win_call(state.window, function() vim.fn.winrestview(view) end)
  end
  vim.wo[state.window].winbar = header(state)
  state.applied.winbar = vim.wo[state.window].winbar
end
update = function()
  for tab, state in pairs(tabs) do
    if api.nvim_tabpage_is_valid(tab) then
      pause_if_scrolled(state)
      render(tab, state)
      counts(state)
    end
  end
  redraw()
end

local function mappings(buf)
  local function map(key, callback, desc)
    vim.keymap.set("n", key, callback, { buffer = buf, silent = true, desc = "Drawer: " .. desc })
  end
  map("q", M.close, "close")
  map("s", M.choose, "select source")
  map("f", M.follow, "toggle follow")
  map("r", function() M.refresh() end, "refresh source")
  map("C", M.clear, "clear output")
  map("F", function()
    local tab = current()
    vim.ui.input({ prompt = "Filter output: ", default = state_for(tab).filter }, function(value)
      if value ~= nil and api.nvim_tabpage_is_valid(tab) then
        state_for(tab).filter = value
        queue()
      end
    end)
  end, "filter output (empty resets)")
end

function M.open(id, opts)
  initialize()
  opts = opts or {}
  if id ~= nil then source(id) end
  local tab = current()
  local state = state_for(tab)
  local previous = state.selected
  local next_id = id or (providers[state.selected] and state.selected) or ids()[1]
  local provider = next_id and providers[next_id]
  if provider and provider.refresh then M.refresh(provider.id) end
  state.selected = next_id
  if previous ~= state.selected then state.follow, state.sequences = true, nil end
  local origin = api.nvim_get_current_win()
  if not state.buffer or not api.nvim_buf_is_valid(state.buffer) then
    state.buffer = api.nvim_create_buf(false, true)
    vim.bo[state.buffer].bufhidden = "hide"
    vim.bo[state.buffer].filetype = "ux_chrome_drawer"
    vim.bo[state.buffer].modifiable = false
    mappings(state.buffer)
  end
  if not live(state) then
    state.return_window = origin
    state.window = api.nvim_open_win(state.buffer, false, {
      split = "below", win = -1, height = math.min(state.height, math.max(1, vim.o.lines - vim.o.cmdheight - 4)),
    })
  end
  panes.attach({ id = provider and provider.id or "ux.chrome.drawer", role = "log",
    content = "plaintext", window = state.window, buffer = state.buffer })
  if not state.opening then
    state.opening, state.applied = {}, {}
    for _, name in ipairs(owned_options) do state.opening[name] = vim.wo[state.window][name] end
  end
  vim.wo[state.window].winfixheight = true
  vim.wo[state.window].scrolloff = 0
  -- Attachment releases editor chrome options; retain the global status renderer.
  vim.wo[state.window].statusline = ""
  for _, name in ipairs(owned_options) do state.applied[name] = vim.wo[state.window][name] end
  render(tab, state)
  counts(state)
  if opts.focus ~= false then api.nvim_set_current_win(state.window) end
  redraw()
  return state.window
end

function M.close()
  local state = state_for(current())
  if not live(state) then return true end
  local win = state.window
  state.height = api.nvim_win_get_height(win)
  -- Neovim cannot close its last window: replace the disposable drawer buffer.
  local normal = 0
  for _, candidate in ipairs(api.nvim_tabpage_list_wins(current())) do
    if api.nvim_win_get_config(candidate).relative == "" then normal = normal + 1 end
  end
  if normal == 1 then
    release_window(state)
    api.nvim_win_set_buf(win, api.nvim_create_buf(true, false))
  else
    local focused = api.nvim_get_current_win() == win
    api.nvim_win_close(win, true)
    if focused and state.return_window and api.nvim_win_is_valid(state.return_window)
        and api.nvim_win_get_tabpage(state.return_window) == current() then
      api.nvim_set_current_win(state.return_window)
    end
  end
  state.window, state.opening, state.applied = nil, nil, nil
  redraw()
  return true
end
function M.toggle()
  if live(state_for(current())) then return M.close() end
  return M.open()
end
function M.follow(value)
  local state = state_for(current())
  if value == nil then value = not state.follow end
  state.follow = value == true
  render(current(), state)
  counts(state)
  redraw()
  return true
end
function M.filter(value)
  if type(value) ~= "string" or value:find("[%c]") then fail("filter must be a single line") end
  state_for(current()).filter = value
  queue()
  return true
end
function M.choose()
  local tab = current()
  vim.ui.select(M.providers(), { prompt = "Output source", format_item = function(item) return item.label end },
    function(item)
      if item and providers[item.id] and api.nvim_tabpage_is_valid(tab) and current() == tab then M.open(item.id) end
    end)
end
function M.status(tab)
  local state = state_for(tab or current())
  return { unread = state.unread, errors = state.errors, open = live(state) or false }
end
function M.inspect(tab)
  local state = state_for(tab or current())
  local result = vim.deepcopy(state)
  result.open = live(state) or false
  return result
end
function M.click(_, _, button)
  if button == "l" then vim.schedule(M.toggle) end
end
function M.unregister(id)
  source(id)
  providers[id] = nil
  for tab, state in pairs(tabs) do
    state.seen[id] = nil
    if state.selected == id then
      state.selected, state.sequences, state.follow = nil, nil, true
      local provider = selected(state)
      if live(state) then
        panes.attach({ id = provider and provider.id or "ux.chrome.drawer", role = "log",
          content = "plaintext", window = state.window, buffer = state.buffer })
        render(tab, state)
      end
    end
  end
  queue()
  return true
end
function M.setup()
  if providers["ux.chrome.messages"] then return end
  M.register({ id = "ux.chrome.messages", label = "Messages", refresh = function()
    local output = api.nvim_exec2("messages", { output = true }).output
    return output == "" and {} or vim.split(output, "\n", { plain = true })
  end })
end
function M.teardown()
  generation = generation + 1
  pending = false
  if group then api.nvim_del_augroup_by_id(group); group = nil end
  for _, state in pairs(tabs) do
    if live(state) then
      release_window(state)
      local ok = pcall(api.nvim_win_close, state.window, true)
      if not ok then
        api.nvim_win_set_buf(state.window, api.nvim_create_buf(true, false))
      end
    end
    if state.buffer and api.nvim_buf_is_valid(state.buffer) then api.nvim_buf_delete(state.buffer, { force = true }) end
  end
  providers, tabs = {}, {}
  return true
end
return M
