-- Run with Neovim: this checks the actual extmarks produced by the renderer.
vim.opt.runtimepath:append('.')
local api = vim.api
local helpers = require('test.helpers')
local plugin = require('vcolumn')

-- Capture the redraw callback so tests can render without an attached UI.
local on_win
local set_provider = api.nvim_set_decoration_provider
api.nvim_set_decoration_provider = function(namespace, callbacks)
  on_win = callbacks.on_win
  return set_provider(namespace, callbacks)
end
plugin.setup()
api.nvim_set_decoration_provider = set_provider

local function render(highlights, line)
  plugin.setup({ cols = { 3, 5, 7 }, highlight_group = highlights })
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, { line or '' })
  on_win('win', api.nvim_get_current_win(), buf, 0, 1)
  local result = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, plugin.namespace, 0, -1,
    { details = true })) do
    local details = mark[4]
    result[#result + 1] = { details.virt_text_win_col + 1, details.virt_text[1][2] }
  end
  api.nvim_buf_delete(buf, { force = true })
  table.sort(result, function(a, b) return a[1] < b[1] end)
  return result
end

local test = {}

function test.single_highlight()
  helpers.assert_equal(render('GuideSoft'), {
    { 3, 'GuideSoft' }, { 5, 'GuideSoft' }, { 7, 'GuideSoft' },
  })
  helpers.assert_equal(render({ 'GuideSoft' }), render('GuideSoft'))
end

function test.cycling_highlights()
  helpers.assert_equal(render({ 'GuideSoft', 'GuideHard' }), {
    { 3, 'GuideSoft' }, { 5, 'GuideHard' }, { 7, 'GuideSoft' },
  })
end

function test.extra_highlights()
  helpers.assert_equal(render({ 'GuideSoft', 'GuideHard', 'GuideSoft', 'Unused' }), {
    { 3, 'GuideSoft' }, { 5, 'GuideHard' }, { 7, 'GuideSoft' },
  })
end

function test.skipped_column_keeps_its_index()
  helpers.assert_equal(render({ 'GuideSoft', 'GuideHard' }, '  x'), {
    { 5, 'GuideHard' }, { 7, 'GuideSoft' },
  })
end

function test.default_highlight()
  local expected = {
    { 3, 'vcolumn_hl' }, { 5, 'vcolumn_hl' }, { 7, 'vcolumn_hl' },
  }
  helpers.assert_equal(render(nil), expected)
  helpers.assert_equal(render({}), expected)
end

helpers.run(test)
