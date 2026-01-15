local utils = require("treesitter-terraform-doc.utils")
local api = require("treesitter-terraform-doc.api")
local window = require("treesitter-terraform-doc.window")

local M = {}

M.version = "0.4.0"
M.config = {
	-- The vim user command that will trigger the plugin (opens in browser).
	command_name = "OpenDoc",

	-- The command that will take the url as a parameter.
	url_opener_command = "!open",

	-- If true, the cursor will jump to the anchor in the documentation.
	jump_anchor = true,

	-- The vim user command that will open documentation in a floating window.
	window_command_name = "OpenDocWindow",

	-- Floating window options.
	window = {
		width = 0.8, -- Width as percentage of editor width (0.0-1.0)
		height = 0.8, -- Height as percentage of editor height
		border = "rounded", -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
		title = "Terraform Documentation",
		title_pos = "center", -- "left", "center", "right"
	},

	-- Cache options for provider version lookups.
	cache = {
		enabled = true,
		ttl = 3600, -- Cache TTL in seconds (1 hour)
	},
}
M.block_type_url_mapping = {
	resource = "resources",
	data = "data-sources",
}
M.providers = {
	{
		prefix = "ibm",
		name = "IBM-Cloud",
	},
	{
		prefix = "shell",
		name = "scottwinkler",
	},
	{
		prefix = "fastly",
		name = "fastly",
	},
	{
		prefix = "vcd",
		name = "vmware",
	},
	{
		prefix = "newrelic",
		name = "newrelic",
	},
	{
		prefix = "cloudflare",
		name = "cloudflare",
	},
}
M.default_provider = "hashicorp"

---
--- Get the first parent after root for the current_node
---
-- @param current_node node The current used node.
-- @return node?
local find_uppest_parent = function(current_node)
	local root = current_node:tree():root()
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
		if not dict[name] then -- Prevent inserting the same thing twice in the array.
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
	local query = vim.treesitter.query.parse(
		"hcl",
		[[
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
            )?
          )
        )
    ]]
	)

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
	local parser = vim.treesitter.get_parser(0, "terraform")
	if parser == nil then
		print("No parser found for the current buffer, please ensure you are starting treesitter properly.")
		return
	end

	local cursor_node
	local ok = pcall(require, "nvim-treesitter.ts_utils")
	if ok then
		-- Old version of nvim-treesitter we are setting cursor using the old way
		local ts_utils = require("nvim-treesitter.ts_utils")
		cursor_node = ts_utils.get_node_at_cursor()
	else
		-- Using the new way to get the cursor node
		cursor_node = vim.treesitter.get_node()
	end

	local node = find_uppest_parent(cursor_node)
	if node == nil then
		return
	end

	local source, provider, type, name, argument_name = get_block_info(node, bufnr)
	if provider == nil or name == nil then
		return
	end

	local url = "https://registry.terraform.io/providers/"
		.. source
		.. "/"
		.. provider
		.. "/latest/docs/"
		.. type
		.. "/"
		.. name

	if M.config.jump_anchor and argument_name then
		url = url .. "\\\\#" .. argument_name .. "-1" -- The '-1' is to match the id generated by terraform doc.
	end

	local cmd = 'silent exec "' .. M.config.url_opener_command .. " '" .. url .. "'\""
	vim.cmd(cmd)
end

---
--- Open the terraform documentation in a floating window.
---
local open_doc_in_window = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local parser = vim.treesitter.get_parser(0, "terraform")
	if parser == nil then
		vim.notify(
			"No parser found for the current buffer, please ensure you are starting treesitter properly.",
			vim.log.levels.ERROR
		)
		return
	end

	local cursor_node
	local ok = pcall(require, "nvim-treesitter.ts_utils")
	if ok then
		local ts_utils = require("nvim-treesitter.ts_utils")
		cursor_node = ts_utils.get_node_at_cursor()
	else
		cursor_node = vim.treesitter.get_node()
	end

	local node = find_uppest_parent(cursor_node)
	if node == nil then
		return
	end

	local source, provider, type, name, _ = get_block_info(node, bufnr)
	if provider == nil or name == nil then
		return
	end

	-- Show loading message
	vim.notify("Fetching documentation...", vim.log.levels.INFO)

	-- Set cache TTL
	if M.config.cache.enabled then
		api.set_cache_ttl(M.config.cache.ttl)
	else
		api.set_cache_ttl(0)
	end

	-- Step 1: Get provider version ID
	local version_id, err = api.get_provider_version_id(source, provider)
	if err then
		vim.notify("Failed to get provider version: " .. err, vim.log.levels.ERROR)
		return
	end

	-- Step 2: Get documentation ID
	local doc_id, doc_err = api.get_doc_id(version_id, type, name)
	if doc_err then
		vim.notify("Failed to find documentation: " .. doc_err, vim.log.levels.ERROR)
		return
	end

	-- Step 3: Fetch documentation content
	local content, content_err = api.fetch_doc_content(doc_id)
	if content_err then
		vim.notify("Failed to fetch documentation: " .. content_err, vim.log.levels.ERROR)
		return
	end

	-- Step 4: Strip frontmatter
	content = api.strip_frontmatter(content)

	-- Step 5: Open in floating window
	local win = window.open(content, {
		width = M.config.window.width,
		height = M.config.window.height,
		border = M.config.window.border,
		title = M.config.window.title .. " - " .. provider .. "_" .. name,
		title_pos = M.config.window.title_pos,
	})

	if not win then
		vim.notify("Failed to open documentation window", vim.log.levels.ERROR)
	end
end

---
--- Setup the configuration for the plugin.
---   Register the "OpenDoc" (or config.command_name) command.
---   Register the "OpenDocWindow" (or config.window_command_name) command.
---
--- @param config table The configuration table.
M.setup = function(config)
	M.config = utils.merge(M.config, config)

	-- Register browser command (existing)
	vim.api.nvim_create_user_command(M.config.command_name, open_doc_from_cursor_position, { nargs = 0 })

	-- Register window command (new)
	vim.api.nvim_create_user_command(M.config.window_command_name, open_doc_in_window, { nargs = 0 })
end

-- Export submodules for advanced usage
M.api = api
M.window = window

return M
