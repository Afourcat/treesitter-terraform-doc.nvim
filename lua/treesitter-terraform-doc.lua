local ts_util = require('nvim-treesitter.ts_utils')
local q = require('vim.treesitter.query')

local M = {}

M.version = "0.1.0"
M.config = {
    command_name = "OpenDoc",
    url_opener_command = "!open"
}

local find_uppest_parrent = function(current_node)
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

local get_resource_info = function(node, bufnr)
    local query = vim.treesitter.parse_query('hcl', [[
        (block
          (identifier) @block_type (#match? @block_type "resource|data")
          (string_lit
            (template_literal) @resource_type
          )
          (string_lit
            (template_literal) @resource_name
          )
        ) @main
    ]])

    local dict = {}
    local counter = 0
    for _, captures, _ in query:iter_matches(node, bufnr) do
        for id, capture_node in pairs(captures) do
            counter = counter + 1
            local name = query.captures[id]
            dict[name] = q.get_node_text(capture_node, bufnr)
        end
    end

    if counter ~= 4 then
        print("Invalid resource targeted, try a 'resource' or 'data' block")
        return nil, nil
    end

    -- split by snake_case
    local iter = string.gmatch(dict["resource_type"], '[^_]+')
    local resource_type = iter()

    -- Concat last words
    local resource_name = ""
    local next = iter()
    while next ~= nil do
        -- Skip the first _
        if resource_name == "" then
            resource_name = next
        else
            resource_name = resource_name .. "_" .. next
        end
        next = iter()
    end

    return resource_type, resource_name
end

local open_doc_from_cursor_position = function()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = ts_util.get_node_at_cursor()
    local node = find_uppest_parrent(cursor)
    if node == nil then
        return
    end

    local resource_type, resource_name = get_resource_info(node, bufnr)
    if resource_type == nil or resource_name == nil then
        return
    end

    local url = 'https://registry.terraform.io/providers/hashicorp/' ..
        resource_type .. '/latest/docs/resources/' .. resource_name

    vim.cmd('silent exec "' .. M.config.url_opener_command .. ' \'' .. url .. '\'"')
end

M.setup = function(config)
    for k, v in pairs(config or {}) do
        M.config[k] = v
    end

    vim.api.nvim_create_user_command(
        M.config.command_name,
        open_doc_from_cursor_position,
        { nargs = 0 }
    )
end

return M
