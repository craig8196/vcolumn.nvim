-- The goal is to efficiently/minimally re-render the virtual column.
-- Tested with nvim v0.11.6, lua 5.1
--
-- Possible Approaches:
-- * The delete everything on_win event approach works, but rerenders too
--   frequently.
--   The delete by insert in-perceptible delay approach prevents this, but
--   still rerenders for the entire screen for every small change.
--   10 ms might prevent spams to refresh, but isn't fine-grained.
--   Also, 10 ms to update is frequently updating and we have to guess at the
--   size/location of the current window, which can get messy.
--   (Information is accurate during the callback, but the delay makes 
--   any information unreliable during a delay.)
-- * The fine-grained approach requires tracking window-information and now
--   is leaking some memory because of namespaces and leaking due to normal
--   namespace.
-- * Solution. Use one namespace. Track window changes in a manager.
--   Do only the updates needed.
--
-- Dev Notes:
-- * Namespaces cannot be deleted. Creating a per-window namespace creates a
--   memory/resource leak (not big, but still would annoy me).
-- * There is a weird disconnect with Window IDs and Window Numbers, beware.
--   > winid is used for Window ID, use with neovim api
--   > winnr is used for Window Number, use with vim api
--
-- Random notes:
-- Should adding a delay in rendering be necessary...
-- Most people type at a rate of about 8 characters per second (~40WPM).
-- Fast typers can hit 160WPM+ or 32+ characters per second.
-- This is rare, but possible.
-- So there is an average of 31.25ms between key strokes.
-- This means that we should delay render by less than 31ms.
-- I think that 24ms should be sufficient, rendering artifacts should be minor.
local Options = require('vcolumn.options')
local util = require('vcolumn.util')
local RangeTracker = require('vcolumn.range_tracker')

local api = vim.api
local buf_line_count = api.nvim_buf_line_count

-- Normalize configured columns using the current buffer's textwidth.
local function process_options_cols(cols)
  if cols == process_options_cols then cols = {} end
  local tw = vim.bo.textwidth or 0
  return util.parse_cols(cols, tw)
end

-- TODO do i need to do folds differently? the see FoldColumn highlight

local MODNAME = 'vcolumn'
local HL = MODNAME..'_hl'
local NS = MODNAME..'_ns'
local GROUP = MODNAME..'_gp'

-- Normalize one highlight or a list; an empty list uses the default group.
local function process_options_highlights(groups)
  if type(groups) == 'string' then return { groups } end
  if type(groups) == 'table' and #groups > 0 then return groups end
  return { HL }
end

local defaultOptions = {
  vcolumns = true,
  cols = process_options_cols, -- string|{ numbers } -> { sorted numbers }
  priority = 1,
  char = '▏',
  highlight_group = process_options_highlights,
  vcrosshairs = false,
  crosshairs_size = 16,
  crosshairs_char = '▏'
}
local M = {}
M.initialized = false
M.initialized_textwidth = false
M.opts = Options.new(defaultOptions)
M.state = { b = {} }
M.namespace = api.nvim_create_namespace(NS)
M.group = api.nvim_create_augroup(GROUP, {})

-------------------------------------------------------------------------------
--- Core Functionality
--- All the core logic is here. Everything else is wrapper code.
-------------------------------------------------------------------------------

-- Clear our marks from the rows in the given buffer.
local function clear_lines(bufnr, irowstart, irowend)
  if irowstart == irowend then return end
  api.nvim_buf_clear_namespace(bufnr, M.namespace, irowstart, irowend)
end

-- Clear all tracked marks and reset coverage so the next redraw rebuilds it.
local function clear_all()
  for bufnr, _ in pairs(M.state.b) do
    clear_lines(bufnr, 0, -1)
    M.state.b[bufnr] = RangeTracker.new()
  end
end

-- Read [istart, iend) and splice inline virtual text at its byte offsets.
-- Keep tabs intact so display widths can be measured after inserting text.
local function get_lines(bufnr, istart, iend)
  -- Fourth is options.
  local function ismarkinline(mark) return mark[4].virt_text_pos == 'inline' end
  -- First is text, second is highlight.
  local function getmarktext(marktext) return marktext[1] end

  local lines = api.nvim_buf_get_lines(bufnr, istart, iend, false)

  -- Looks like marks are returned in "traversal order" so sorting isn't needed.
  local ext_marks = api.nvim_buf_get_extmarks(
    bufnr, -1, { istart, 0 }, { iend, 0 },
    { details = true, type = 'virt_text' }
  )
  local inline_marks = vim.tbl_filter(ismarkinline, ext_marks)

  local lines_offset = {}
  local markrow, markcol, iline, line, offset, marktext
  for _, mark in ipairs(inline_marks) do
    markrow = mark[2]
    iline = markrow - istart + 1
    line = lines[iline]
    if line then
      offset = lines_offset[markrow] or 0
      markcol = mark[3] + offset
      marktext = table.concat(vim.tbl_map(getmarktext, mark[4].virt_text))
      line = line:sub(1, markcol) .. marktext .. line:sub(markcol + 1)
      lines[iline] = line
      lines_offset[markrow] = offset + #marktext
    end
  end

  return lines
end

-- Check a zero-based display column, accounting for tabs and wide characters.
-- Beyond the end of the line is blank; all cells of a tab are also blank.
local function is_blank_at(line, col)
  local width = 0
  for _, char in ipairs(vim.fn.split(line, '\\zs')) do
    width = width + vim.fn.strdisplaywidth(char, width)
    if width > col then return char == ' ' or char == '\t' end
  end
  return true
end

-- Overlay columns on blank display cells in the half-open row range.
local function add_lines(bufnr, irowstart, irowend)
  local lines = get_lines(bufnr, irowstart, irowend)
  if #lines < (irowend - irowstart) then return end

  -- Width calculations must use the target buffer's tab settings.
  api.nvim_buf_call(bufnr, function()
    for irow, line in ipairs(lines) do
      for i, col in ipairs(M.opts.cols) do
        if is_blank_at(line, col) then
          local groups = M.opts.highlight_group
          local highlight = groups[(i - 1) % #groups + 1]
          api.nvim_buf_set_extmark(
            bufnr, M.namespace, irowstart + irow - 1, 0, {
              virt_text = { { M.opts.char, highlight } },
              virt_text_pos = 'overlay',
              virt_text_win_col = col,
              strict = false,
              hl_mode = 'combine',
              priority = M.opts.priority,
            }
          )
        end
      end
    end
  end)
end

-- RangeTracker gives a list of updates that need to be performed.
-- Process them here.
local function perform_updates(bufnr, updates)
  for _, item in ipairs(updates) do
    if item[RangeTracker.TYPE] == RangeTracker.REMOVE then
      clear_lines(bufnr, item[RangeTracker.LO], item[RangeTracker.HI])
    elseif item[RangeTracker.TYPE] == RangeTracker.ADD then
      add_lines(bufnr, item[RangeTracker.LO], item[RangeTracker.HI])
    end
  end
end

-- Switches on when 'colorcolumn' is set.
local function clear_colorcolumn_highlight()
  api.nvim_set_hl(0, "ColorColumn", {})
end


-------------------------------------------------------------------------------
--- Event Handling
--- Functions that normalize the NVim events and IDs.
-------------------------------------------------------------------------------

-- Keep in mind that not all updated lines in the buffer are visible.
local function on_buf_lines_updated(_, bufnr, _, firstline, lastline, new_lastline)
  -- vim.print('on_lines: '..firstline..','..lastline..' new last:'..new_lastline)
  local tracker = M.state.b[bufnr]
  local updates

  local min = math.min(lastline, new_lastline)
  if min > firstline then
    -- Update some lines.
    updates = tracker:update_segment(firstline, min)
    perform_updates(bufnr, updates)
    updates = nil
  end

  if new_lastline < lastline then
    -- Lines were removed.
    local line_count = api.nvim_buf_line_count(bufnr)
    updates = tracker:remove_segment(new_lastline, lastline, line_count)
  elseif lastline < new_lastline then
    -- Lines were added.
    updates = tracker:insert_segment(lastline, new_lastline)
  end

  if updates then
    perform_updates(bufnr, updates)
  end
end

-- Set event listening if not setup and create buffer state for tracking window
-- changes.
local function do_buf_setup(bufnr)
  if not M.state.b[bufnr] then
    M.state.b[bufnr] = RangeTracker.new()

    -- New buffer. Attach to changes.
    api.nvim_buf_attach(bufnr, true, {
      on_lines = on_buf_lines_updated,
    })
  end
end

-- Gets called when there are new options.
-- Nvim will refresh the window after this gets called.
local function on_option_set(ev)
  if ev.match == 'colorcolumn' then
    clear_colorcolumn_highlight()
    local colorcolumn = api.nvim_get_option_value('colorcolumn', { scope = 'local' })
    colorcolumn = colorcolumn or {}
    -- Options will reparse columns.
    M.opts.cols = colorcolumn
  elseif ev.match == 'textwidth' then
    M.opts.cols = Options.get_user(M.opts).cols
  end
  clear_all()
end

-- Update any changed colors.
-- Nvim will refresh the window after this gets called.
local function on_color_scheme(_)
  local bg_color = api.nvim_get_hl(0, { name = 'ColorColumn' }).background or 0x111111
  api.nvim_set_hl(0, HL, { fg = bg_color, default = true })
  clear_all()
end

-- Update column compute on 'BufEnter', textwidth isn't set until about then.
local function on_buf_enter(ev)
  if not M.initialized_textwidth then
    M.opts.cols = Options.get_user(M.opts).cols
    M.initialized_textwidth = true
  end

  do_buf_setup(ev.buf)
end

-- Drop the closing window's ID from every buffer it may have displayed.
local function on_win_closed(ev)
  local winid = tonumber(ev.match)
  for bufnr, tracker in pairs(M.state.b) do
    perform_updates(bufnr, tracker:remove(winid))
  end
end

-- Clean up our tracking data for the buffer.
-- We don't need to clear extension marks as it will all get cleaned up.
local function on_buf_delete(ev)
  -- vim.print('on_buf_delete: '..ev.buf)
  M.state.b[ev.buf] = nil
end

-- Called everytime the display needs to be refreshed/updated for the user.
local function on_decor(_, winid, bufnr, topline, botline)
  -- There is some weird behavior where the last line of a buffer is not
  -- being rendered. The next line is a work-around.
  local bufend = buf_line_count(bufnr)
  if botline == (bufend - 1) then botline = bufend end

  do_buf_setup(bufnr)

  local tracker = M.state.b[bufnr]
  local updates = tracker:update(winid, topline, botline)
  perform_updates(bufnr, updates)
end

-------------------------------------------------------------------------------
--- Main
-------------------------------------------------------------------------------

local function init()
  if M.initialized then return end

  -- Set the default highlight group.
  clear_colorcolumn_highlight()
  on_color_scheme()

  local function autocmd(name, callback, pattern)
    api.nvim_create_autocmd(
      name, { group = M.group, pattern = pattern, callback = callback }
    )
  end

  autocmd('OptionSet', on_option_set, 'colorcolumn,textwidth')
  autocmd('ColorScheme', on_color_scheme)

  autocmd('BufEnter', on_buf_enter)
  autocmd('WinClosed', on_win_closed)
  autocmd('BufDelete', on_buf_delete)

  -- Update each line when they change.
  api.nvim_set_decoration_provider(M.namespace, {
    on_win = on_decor, -- refreshes entire window
  })

  M.initialized = true
end

-- Configure the plugin and install its event handlers once.
function M.setup(user_options)
  M.opts = Options.new(defaultOptions, user_options)
  init()
end

return M
