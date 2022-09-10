# Treesitter Terraform Doc

This is a simple plugin to open documentation of the current Terraform resource.

## Features

Add the command "OpenDoc" user command that opens the documentation of the currently targeted resource in terraform hcl file in your default browser.

## Requirements

- git
- [Neovim](https://github.com/neovim/neovim) ≥ 0.5
- [Treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- MacOS (right now)

## Installation

Install from your favorite package manager:
And then

```lua
require('lspconfig').terraformls.setup {
    on_attach = function()
        -- This register the user command OpenDoc that you are able to bind to any key.
        require('treesitter-terraform-doc').setup()
        ...
    end,
    ...
}

```

## TODO

- Add a parameter to set the code used for url openning.
