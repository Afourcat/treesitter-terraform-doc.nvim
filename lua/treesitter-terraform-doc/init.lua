local ts_util = require('nvim-treesitter.ts_utils')
local q = require('vim.treesitter.query')
local utils = require('treesitter-terraform-doc.utils')

local M = {}

M.version = "0.3.0"
M.config = {
    -- The vim user command that will trigger the plugin.
    command_name       = "OpenDoc",

    -- The command that will take the url as a parameter.
    url_opener_command = "!open",

    -- If true, the cursor will jump to the anchor in the documentation.
    jump_anchor      = true,
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
    },
    {
        prefix = "newrelic",
        name = "newrelic"
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
local get_matches_from_node = function(query, node, bufnr, current_line)
    local dict = {}
    local dict_length = 0

    for id, capture, _ in query:iter_captures(node, bufnr) do
        local name = query.captures[id]
        if not dict[name] then              -- Prevent inserting the same thing twice in the array.
            if name == "argument_name" then -- If the argument is the name of one of the field return it.
                local a = capture:range()
                if M.config.jump_anchor and current_line == a + 1 then
                    dict_length = dict_length + 1
                    dict[name] = vim.treesitter.get_node_text(capture, bufnr)
                end
            else
                dict_length = dict_length + 1
                dict[name] = vim.treesitter.get_node_text(capture, bufnr)
            end
        end
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
---@return      string? The argument name.
---@nodiscard
local get_block_info = function(node, bufnr)
    local query = vim.treesitter.query.parse('hcl', [[
        (block
          (identifier) @block_type (#match? @block_type "resource|data")
          (string_lit
            (template_literal) @resource
          )
          (string_lit
            (template_literal) @user_name
          )
          (body
            (attribute
                (identifier) @argument_name
            )
          )
        )
    ]])

    local cursor = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor[1]
    local dict, dict_length = get_matches_from_node(query, node, bufnr, current_line)

    -- Checks if all captures have matched
    if dict_length ~= 3 and dict_length ~= 4 then
        print("Invalid resource targeted, try a 'resource' or 'data' block")
        return nil, nil
    end

    local provider, name = split_at_first_occurence(dict["resource"], "_")
    local type = M.block_type_url_mapping[dict["block_type"]]

    local source = find_provider_source(provider)

    return source, provider, type, name, dict["argument_name"]
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

    local source, provider, type, name, argument_name = get_block_info(node, bufnr)
    if provider == nil or name == nil then
        return
    end

    local url = 'https://registry.terraform.io/providers/' .. source .. '/' ..
        provider .. '/latest/docs/' .. type .. '/' .. name

    if M.config.jump_anchor and argument_name then
        url = url .. "\\\\#" .. argument_name
    end

    local cmd = 'silent exec "' .. M.config.url_opener_command .. ' \'' .. url .. '\'"'
    vim.cmd(cmd)
end

---
--- Setup the configuration for the plugin.
---   Register the "OpenDoc" (or config.command_name) command.
---
--- @param config table The configuration table.
M.setup = function(config)
    M.config = table.merge(M.config, config)

    vim.api.nvim_create_user_command(
        M.config.command_name,
        open_doc_from_cursor_position,
        { nargs = 0 }
    )
end

return M
