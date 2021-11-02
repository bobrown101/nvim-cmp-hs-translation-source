# bobrown101/nvim_cmp_hs_translation_source

A completion source for nvim-cmp that will autocomplete translation keys in the current git project

![Screenshot](images/demo.gif)

## Install
```
use { 'bobrown101/git-blame.nvim' }

```

## Use
```lua
:lua require('git_blame').run()
```

## Keymap
```lua
vim.api.nvim_set_keymap('n', '<space>g', "<cmd>lua require('git_blame').run()<cr>", { noremap = true, silent = true })
```
