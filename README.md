# Treesitter Terraform Doc

This is a simple plugin to open documentation of the current Terraform resource.

## Features

Add the "OpenDoc" user command that opens the documentation of the resource targeted by the cursor in a terraform "hcl" file, directly into your default browser.

## Requirements

- git
- [Neovim](https://github.com/neovim/neovim) ≥ 0.5
- [Treesitter](https://github.com/nvim-treesitter/nvim-treesitter) and the hcl parser
- MacOS (by default)

## Installation

1. Install from your favorite package manager.
2. Add the following to your terraform lsp config:

```lua
require('lspconfig').terraformls.setup {
    on_attach = function()
        -- This register the user command "OpenDoc" that you are able to bind to any key.
        require('treesitter-terraform-doc').setup()
        ...
    end,
    ...
}

```
---
Here is another example with the default config:
```lua
require('treesitter-terraform-doc').setup({
    -- The vim user command that will trigger the plugin.
    command_name       = "OpenDoc",

    -- The command that will take the url as a parameter.
    url_opener_command = "!open"

    -- If true, the cursor will jump to the anchor in the documentation.
    jump_argument      = true
})
```

For example, on linux you could change it to:
```lua
require('treesitter-terraform-doc').setup({
    command_name       = "OpenDoc",
    url_opener_command = "!firefox"
    jump_argument      = true
})
```
in order to run the command with firefox.

## Custom Provider

You can add or override provider by adding the following to your config:

```lua
require('treesitter-terraform-doc').setup({
    ...,
    provider = {
        prefix = "test",
        name   = "custom-provider-source"
    }
})
```
