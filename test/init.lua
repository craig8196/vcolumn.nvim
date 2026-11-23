
package.path = package.path .. ';./lua/?/init.lua;./lua/?.lua'

vim.api.nvim_set_hl(0, 'myhl', { fg = 'gray' })

vim.api.nvim_set_keymap('n', '<F4>', ':q!<CR>', { noremap = true, silent = true })
require('vcolumn').setup({
  cols = '3,5,7,+20,+0,-10',
  highlight_group = 'myhl',
})



