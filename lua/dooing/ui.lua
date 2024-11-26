---@diagnostic disable: undefined-global, param-type-mismatch
-- Explicitly declare vim as a global variable
local vim = vim

-- UI Module for Dooing Plugin
-- Handles window creation, rendering and UI interactions for todo management

---@class DoingUI
---@field toggle_todo_window function
---@field render_todos function
---@field close_window function
---@field new_todo function
---@field toggle_todo function
---@field delete_todo function
---@field delete_completed function
local M = {}

--------------------------------------------------
-- Dependencies
--------------------------------------------------
local state = require("dooing.state")
local config = require("dooing.config")

--------------------------------------------------
-- Local Variables
--------------------------------------------------
-- Namespace for highlighting
local ns_id = vim.api.nvim_create_namespace("dooing")

-- Window and buffer IDs
---@type integer|nil
local win_id = nil
---@type integer|nil
local buf_id = nil
---@type integer|nil
local help_win_id = nil
---@type integer|nil
local help_buf_id = nil
---@type integer|nil
local tag_win_id = nil
---@type integer|nil
local tag_buf_id = nil

-- Forward declare local functions that are used in keymaps
local create_help_window
local create_tag_window
local edit_todo

--------------------------------------------------
-- Highlights Setup
--------------------------------------------------
-- Set up highlights
vim.api.nvim_set_hl(0, "DooingPending", { link = "Question", default = true })
vim.api.nvim_set_hl(0, "DooingDone", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "DooingHelpText", { link = "Directory", default = true })

--------------------------------------------------
-- Todo Management Functions
--------------------------------------------------

-- Handles editing of existing todos
edit_todo = function()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]

	if line_content:match("^%s+[○✓]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						todo_index = i
						break
					end
				end
			end
		end

		vim.ui.input({ prompt = "Edit to-do: ", default = state.todos[todo_index].text }, function(input)
			if input and input ~= "" then
				state.todos[todo_index].text = input
				state.save_todos()
				M.render_todos()
			end
		end)
	end
end

--------------------------------------------------
-- Core Window Management
--------------------------------------------------

-- Creates and manages the help window
create_help_window = function()
	if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
		vim.api.nvim_win_close(help_win_id, true)
		help_win_id = nil
		help_buf_id = nil
		return
	end

	help_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 40
	local height = 15
	local ui = vim.api.nvim_list_uis()[1]
	local col = math.floor((ui.width - width) / 2) + width + 2
	local row = math.floor((ui.height - height) / 2)

	help_win_id = vim.api.nvim_open_win(help_buf_id, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " help ",
		title_pos = "center",
		zindex = 200,
	})

	local help_content = {
		" Keybindings:",
		" ",
		" i     - Add new to-do",
		" x     - Toggle to-do status",
		" d     - Delete current to-do",
		" D     - Delete all completed todos",
		" ?     - Toggle this help window",
		" q     - Close window",
		" t     - Toggle tags window",
		" e     - Edit to-do item",
		" c     - Clear active tag filter",
		" ",
	}

	vim.api.nvim_buf_set_lines(help_buf_id, 0, -1, false, help_content)
	vim.api.nvim_buf_set_option(help_buf_id, "modifiable", false)
	vim.api.nvim_buf_set_option(help_buf_id, "buftype", "nofile")

	for i = 0, #help_content - 1 do
		vim.api.nvim_buf_add_highlight(help_buf_id, ns_id, "DooingHelpText", i, 0, -1)
	end

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = help_buf_id,
		callback = function()
			if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
				vim.api.nvim_win_close(help_win_id, true)
				help_win_id = nil
				help_buf_id = nil
			end
			return true
		end,
	})

	local function close_help()
		if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
			vim.api.nvim_win_close(help_win_id, true)
			help_win_id = nil
			help_buf_id = nil
		end
	end

	vim.keymap.set("n", "q", close_help, { buffer = help_buf_id })
	vim.keymap.set("n", "?", close_help, { buffer = help_buf_id })
end

-- Creates and manages the tags window
create_tag_window = function()
	if tag_win_id and vim.api.nvim_win_is_valid(tag_win_id) then
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
		return
	end

	tag_buf_id = vim.api.nvim_create_buf(false, true)

	local width = 30
	local height = 10
	local ui = vim.api.nvim_list_uis()[1]
	local main_width = 40
	local main_col = math.floor((ui.width - main_width) / 2)
	local col = main_col - width - 2
	local row = math.floor((ui.height - height) / 2)

	tag_win_id = vim.api.nvim_open_win(tag_buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " tags ",
		title_pos = "center",
	})

	local tags = state.get_all_tags()
	if #tags == 0 then
		tags = { "No tags found" }
	end
	vim.api.nvim_buf_set_lines(tag_buf_id, 0, -1, false, tags)

	vim.keymap.set("n", "<CR>", function()
		local cursor = vim.api.nvim_win_get_cursor(tag_win_id)
		local tag = vim.api.nvim_buf_get_lines(tag_buf_id, cursor[1] - 1, cursor[1], false)[1]
		if tag ~= "No tags found" then
			state.set_filter(tag)
			vim.api.nvim_win_close(tag_win_id, true)
			tag_win_id = nil
			tag_buf_id = nil
			M.render_todos()
		end
	end, { buffer = tag_buf_id })

	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(tag_win_id, true)
		tag_win_id = nil
		tag_buf_id = nil
	end, { buffer = tag_buf_id })
end

-- Creates and configures the main todo window
local function create_window()
	local ui = vim.api.nvim_list_uis()[1]
	local width = 40
	local height = 20
	local col = math.floor((ui.width - width) / 2)
	local row = math.floor((ui.height - height) / 2)

	buf_id = vim.api.nvim_create_buf(false, true)

	win_id = vim.api.nvim_open_win(buf_id, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " to-dos ",
		title_pos = "center",
		footer = " [?] for help ",
		footer_pos = "center",
	})

	vim.api.nvim_win_set_option(win_id, "wrap", true)
	vim.api.nvim_win_set_option(win_id, "linebreak", true)
	vim.api.nvim_win_set_option(win_id, "breakindent", true)
	vim.api.nvim_win_set_option(win_id, "breakindentopt", "shift:2")
	vim.api.nvim_win_set_option(win_id, "showbreak", " ")

	vim.keymap.set("n", config.options.keymaps.new_todo, M.new_todo, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.toggle_todo, M.toggle_todo, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.delete_todo, M.delete_todo, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.delete_completed, M.delete_completed, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.close_window, M.close_window, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.toggle_help, create_help_window, { buffer = buf_id, nowait = true })
	vim.keymap.set("n", config.options.keymaps.toggle_tags, create_tag_window, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.edit_todo, edit_todo, { buffer = buf_id })
	vim.keymap.set("n", config.options.keymaps.clear_filter, function()
		state.set_filter(nil)
		M.render_todos()
	end, { buffer = buf_id, desc = "Clear filter" })
end

-- Public Interface
--------------------------------------------------

-- Renders the todo list in the main window
function M.render_todos()
	if not buf_id then
		return
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", true)
	vim.api.nvim_buf_clear_namespace(buf_id, ns_id, 0, -1)

	local lines = { "" }
	state.sort_todos()

	for _, todo in ipairs(state.todos) do
		if not state.active_filter or todo.text:match("#" .. state.active_filter) then
			local icon = todo.done and "✓" or "○"
			local text = todo.text

			if todo.done then
				text = "~" .. text .. "~"
			end

			table.insert(lines, "  " .. icon .. " " .. text)
		end
	end

	if state.active_filter then
		table.insert(lines, 1, "")
		table.insert(lines, 1, "  Filtered by: #" .. state.active_filter)
	end

	table.insert(lines, "")
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)

	-- Add highlights
	for i, line in ipairs(lines) do
		if line:match("^%s+[○✓]") then
			local todo_index = i - (state.active_filter and 3 or 1)
			local todo = state.todos[todo_index]
			if todo then
				local hl_group = todo.done and "DooingDone" or "DooingPending"
				vim.api.nvim_buf_add_highlight(buf_id, ns_id, hl_group, i - 1, 0, -1)

				-- Highlight tags
				for tag in line:gmatch("#(%w+)") do
					local start_idx = line:find("#" .. tag) - 1
					vim.api.nvim_buf_add_highlight(buf_id, ns_id, "Type", i - 1, start_idx, start_idx + #tag + 1)
				end
			end
		elseif line:match("Filtered by:") then
			vim.api.nvim_buf_add_highlight(buf_id, ns_id, "WarningMsg", i - 1, 0, -1)
		end
	end

	vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
end

-- Toggles the main todo window visibility
function M.toggle_todo_window()
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		M.close_window()
	else
		create_window()
		M.render_todos()
	end
end

-- Closes all plugin windows
function M.close_window()
	if help_win_id and vim.api.nvim_win_is_valid(help_win_id) then
		vim.api.nvim_win_close(help_win_id, true)
		help_win_id = nil
		help_buf_id = nil
	end

	if win_id and vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_win_close(win_id, true)
		win_id = nil
		buf_id = nil
	end
end

-- Creates a new todo item
function M.new_todo()
	vim.ui.input({ prompt = "New to-do: " }, function(input)
		if input and input ~= "" then
			state.add_todo(input)
			M.render_todos()

			-- Find either the first completed todo or the last uncompleted todo
			local total_lines = vim.api.nvim_buf_line_count(buf_id)
			local target_line = nil
			local last_uncompleted_line = nil

			for i = 1, total_lines do
				local line = vim.api.nvim_buf_get_lines(buf_id, i - 1, i, false)[1]
				-- Track the last uncompleted todo
				if line:match("^%s+[○]") then
					last_uncompleted_line = i
				end
				-- Look for the first completed todo
				if line:match("^%s+[✓].*~") then
					target_line = i - 1 -- Position cursor one line above the completed todo
					break
				end
			end

			-- If no completed todos found, use the last uncompleted todo line
			if not target_line and last_uncompleted_line then
				target_line = last_uncompleted_line
			end

			-- If we found a valid line, move cursor there
			if target_line then
				vim.api.nvim_win_set_cursor(win_id, { target_line, 0 })
			end
		end
	end)
end

-- Toggles the completion status of the current todo
function M.toggle_todo()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]

	if line_content:match("^%s+[○✓]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then -- -2 for filter header
						state.toggle_todo(i)
						break
					end
				end
			end
		else
			state.toggle_todo(todo_index)
		end
		M.render_todos()
	end
end

-- Deletes the current todo item
function M.delete_todo()
	local cursor = vim.api.nvim_win_get_cursor(win_id)
	local todo_index = cursor[1] - 1
	local line_content = vim.api.nvim_buf_get_lines(buf_id, todo_index, todo_index + 1, false)[1]

	if line_content:match("^%s+[○✓]") then
		if state.active_filter then
			local visible_index = 0
			for i, todo in ipairs(state.todos) do
				if todo.text:match("#" .. state.active_filter) then
					visible_index = visible_index + 1
					if visible_index == todo_index - 2 then
						state.delete_todo(i)
						break
					end
				end
			end
		else
			state.delete_todo(todo_index)
		end
		M.render_todos()
	end
end

-- Deletes all completed todos
function M.delete_completed()
	state.delete_completed()
	M.render_todos()
end

return M
