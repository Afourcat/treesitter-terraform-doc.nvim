local M = {}

-- Track active window for cleanup
M._active_win = nil
M._active_buf = nil

--- Calculate window dimensions
--- @param width_ratio number Width as ratio of editor width (0.0-1.0)
--- @param height_ratio number Height as ratio of editor height (0.0-1.0)
--- @param opts table Window options
--- @return table config Window configuration
local function calculate_window_config(width_ratio, height_ratio, opts)
	local editor_width = vim.o.columns
	local editor_height = vim.o.lines

	local width = math.floor(editor_width * width_ratio)
	local height = math.floor(editor_height * height_ratio)

	local row = math.floor((editor_height - height) / 2)
	local col = math.floor((editor_width - width) / 2)

	return {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = opts.border or "rounded",
		title = opts.title or "Documentation",
		title_pos = opts.title_pos or "center",
	}
end

--- Close the documentation window
function M.close()
	if M._active_win and vim.api.nvim_win_is_valid(M._active_win) then
		vim.api.nvim_win_close(M._active_win, true)
	end
	if M._active_buf and vim.api.nvim_buf_is_valid(M._active_buf) then
		vim.api.nvim_buf_delete(M._active_buf, { force = true })
	end
	M._active_win = nil
	M._active_buf = nil
end

--- Setup keymaps for the documentation buffer
--- @param bufnr number Buffer number
local function setup_keymaps(bufnr)
	local close_keys = { "q", "<Esc>" }
	for _, key in ipairs(close_keys) do
		vim.api.nvim_buf_set_keymap(bufnr, "n", key, "", {
			noremap = true,
			silent = true,
			callback = M.close,
		})
	end
end

--- Open a floating window with markdown content
--- @param content string Markdown content to display
--- @param opts table Window options (width, height, border, title, title_pos)
--- @return number|nil win_id Window ID or nil on error
function M.open(content, opts)
	opts = opts or {}

	-- Close any existing window first
	M.close()

	-- Create a new scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	if buf == 0 then
		vim.notify("Failed to create buffer", vim.log.levels.ERROR)
		return nil
	end

	-- Split content into lines
	local lines = vim.split(content, "\n")

	-- Set buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Set buffer options
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

	-- Calculate window config
	local win_config = calculate_window_config(opts.width or 0.8, opts.height or 0.8, opts)

	-- Create the floating window
	local win = vim.api.nvim_open_win(buf, true, win_config)
	if win == 0 then
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.notify("Failed to create window", vim.log.levels.ERROR)
		return nil
	end

	-- Set window options
	vim.api.nvim_set_option_value("wrap", true, { win = win })
	vim.api.nvim_set_option_value("linebreak", true, { win = win })
	vim.api.nvim_set_option_value("cursorline", true, { win = win })

	-- Setup keymaps
	setup_keymaps(buf)

	-- Track active window/buffer
	M._active_win = win
	M._active_buf = buf

	return win
end

return M
