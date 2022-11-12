local ts_util = require('nvim-treesitter.ts_utils')
local q = require('vim.treesitter.query')
local utils = require('treesitter-terraform-doc.utils')

local M = {}

M.version = "0.3.0"
M.config = {
    command_name       = "OpenDoc",
    url_opener_command = "!open"
}
M.block_type_url_mapping = {
    resource = "resources",
    data     = "data-sources"
}
M.providers = {
    {
        prefix = "ibm",
        name   = "IBM-Cloud",
    },
    {
        prefix = "shell",
        name   = "scottwinkler",
    },
    {
        prefix = "fastly",
        name   = "fastly",
    },
    {
        prefix = "vcd",
        name = "vmware"
    }
}
M.default_provider = "hashicorp"

---
--- Get the first parent after root for the current_node
---
-- @param current_node node The current used node.
-- @return node?
local find_uppest_parent = function(current_node)
    local root = ts_util.get_root_for_node(current_node)
    local parent = current_node:parent()

    if parent:parent() == nil then
        print("No parent found")
        return nil
    end

    while parent:parent() ~= root do
        current_node = parent
        parent = current_node:parent()
    end

    return current_node
end

---
--- Split a string at the first occurence of a delimiter.
---
---@param  s        string  The string to split
---@param  char     string  The delimiter
---@param  exclude? boolean Remove the delimiter from the output
---@return          string  The first part of the string
---@return          string  The second part of the string
---@nodiscard
local split_at_first_occurence = function(s, char, exclude)
    exclude = exclude or true

    local index = string.find(s, char)
    local first = string.sub(s, 1, index - 1)

    local second_index = exclude and index + 1 or index
    local second = string.sub(s, second_index, -1)
    return first, second
end

---
--- Get a dictionary of all the variables in the current node.
---
-- @param  query Query   The treesitter query.
-- @param  node  tsnode  The treesitter node.
-- @param  bufnr integer The buffer number.
---@return       table   The dictionary of all match and their text value.
---@return       integer The length of the dictionary.
local get_matches_from_node = function(query, node, bufnr)
    local dict = {}
    local dict_length = 0

    for id, capture, _ in query:iter_captures(node, bufnr) do
        dict_length = dict_length + 1
        local name = query.captures[id]
        dict[name] = q.get_node_text(capture, bufnr)
    end
    return dict, dict_length
end

---
--- Find the corresponding provider
---
-- @param provider string The provider name previously extracted.
-- @return         string The provider source.
-- @nodiscard
local find_provider_source = function(provider)
    for _, v in ipairs(M.providers) do
        if v.prefix == provider then
            return v.name
        end
    end

    return M.default_provider
end

---
--- Get the terraform block provider, type and name.
---
-- @param node  tsnode  The node in which to look for the resource info.
-- @param bufnr integer The buffer number.
---@return      string? The resource provider source.
---@return      string? The resource provider.
---@return      string? The resource type.
---@return      string? The resource name.
---@nodiscard
local get_block_info = function(node, bufnr)
    local query = vim.treesitter.parse_query('hcl', [[
        (block
          (identifier) @block_type (#match? @block_type "resource|data")
          (string_lit
            (template_literal) @resource
          )
          (string_lit
            (template_literal) @user_name
          )
        )
    ]])

    local dict, dict_length = get_matches_from_node(query, node, bufnr)

    -- Checks if all captures have matched
    if dict_length ~= 3 then
        print("Invalid resource targeted, try a 'resource' or 'data' block")
        return nil, nil
    end

    local provider, name = split_at_first_occurence(dict["resource"], "_")
    local type = M.block_type_url_mapping[dict["block_type"]]

    local source = find_provider_source(provider)

    return source, provider, type, name
end

---
--- Open the terraform documentation from the current cursor position.
---
local open_doc_from_cursor_position = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = ts_util.get_node_at_cursor()
    local node = find_uppest_parent(cursor)
    if node == nil then
        return
    end

    local source, provider, type, name = get_block_info(node, bufnr)
    if provider == nil or name == nil then
        return
    end

    local url = 'https://registry.terraform.io/providers/' .. source .. '/' ..
        provider .. '/latest/docs/' .. type .. '/' .. name

    vim.cmd('silent exec "' .. M.config.url_opener_command .. ' \'' .. url .. '\'"')
end

---
--- Setup the configuration for the plugin.
---   Register the "OpenDoc" (or config.command_name) command.
---
--- @param config table The configuration table.
M.setup = function(config)
    utils.table_merge(M.config, config or {})

    vim.api.nvim_create_user_command(
        M.config.command_name,
        open_doc_from_cursor_position,
        { nargs = 0 }
    )
end

return M
