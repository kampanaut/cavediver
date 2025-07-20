---Navigation domain core routines for coordination mode management.
---
---This module contains the main business logic for managing navigation modes
---that provide coordination context for other domains.

local data = require('cavediver.domains.navigation.data')
local history = require('cavediver.domains.history')

local M = {}

function M.cycle_buffer(direction)
	if #history.get_ordered_buffers() <= 1 then
		return
	end

	local ok, _ = pcall(require, 'cokeline.mappings')
	if not ok then
		print("cokeline is not installed. Please install 'willothy/nvim-cokeline' to use this cycle function.")
		return
	end

	if direction == 1 then
		require('cokeline.mappings').by_step("focus", -1)
	elseif direction == 2 then
		require('cokeline.mappings').by_step("focus", 1)
	else
		error("Invalid direction for cycling mode, must be 1 (left) or 2 (right).")
	end
end

local function skippable_window(winid)
	local buf = vim.api.nvim_win_get_buf(winid)
	local filetype = vim.bo[buf].filetype

	return filetype == "minimap"
end

function M.record_window_jump(from_win, to_win)
	if not skippable_window(from_win) and vim.api.nvim_win_is_valid(from_win) then
		data.window_jump_history[to_win] = from_win
	end
end

function M.toggle_window()
	local cwin = vim.api.nvim_get_current_win()

	local previous_win = data.window_jump_history[cwin]

	if
		previous_win and
		vim.api.nvim_win_is_valid(previous_win) and
		not (skippable_window(previous_win))
	then
		M.record_window_jump(cwin, previous_win)
		vim.api.nvim_set_current_win(previous_win)
	else
		vim.notify("No valid previous window to toggle to.", vim.log.levels.WARN)
	end
end

function M.get_the_previous_window_traverse_chain(cwin)
	local window = require('cavediver.domains.window')
	if not cwin then
		vim.notify("No current window to trace.", vim.log.levels.WARN)
		return
	end

	local visited = {}
	local check_win = cwin

	while check_win and not visited[check_win] do
		visited[check_win] = true
		local previous_win = data.window_jump_history[check_win]
		if previous_win and vim.api.nvim_win_is_valid(previous_win) then
			local buf = vim.api.nvim_win_get_buf(previous_win)
			if history.get_hash_from_buffer(buf) then
				window.data.last_valid_window = previous_win
				return previous_win  -- Found tracked window
			end
			check_win = previous_win
		else
			break
		end
	end
	return nil
end

function M.find_most_recent_tracked_window()
	local window = require('cavediver.domains.window')
	local cwin = window.data.current_window

	if cwin == window.data.last_valid_window then
		return window.data.last_valid_window
	elseif window.get_triquetra(cwin) then
		window.data.last_valid_window = cwin
		return cwin
	elseif window.get_triquetra(window.data.last_valid_window) then
		return window.data.last_valid_window
	end

	return M.get_the_previous_window_traverse_chain(cwin)
end

return M
