---UI domain core routines for visual component management.
---
---This module contains the main business logic for managing visual interface
---components, including the bufferline cache optimization that was previously
---in update_bufferline_state() from buffers.lua.

local data = require('cavediver.domains.ui.data')
local history = require('cavediver.domains.history')
local window = require('cavediver.domains.window')
local navigation = require('cavediver.domains.navigation')
local uiMachines = require('cavediver.domains.ui.sm')
local states = require('cavediver.domains.ui.states')

local preserve_winbar_overlap = {} -- Table to track winbar overlap state

local update_timer = vim.loop:new_timer()

local M = {}

---Find buffers with conflicting basenames.
---
---@param basename string The basename to check for conflicts
---@param filehash Filehash Buffer to exclude from conflict check
---@return string[] conflicts List of full paths with same basename
local function find_basename_conflicts(basename, filehash)
	local conflicts = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if (bufnr ~= history.get_buffer_from_hash(filehash)) and (history.get_filepath_from_hash(filehash) ~= nil) then
			local path = vim.api.nvim_buf_get_name(bufnr)
			if path ~= "" and vim.fn.fnamemodify(path, ":t") == basename then
				table.insert(conflicts, path)
			end
		end
	end
	return conflicts
end

---Compute unique suffix to distinguish path from conflicts.
---
---@param path string Full path to make unique
---@param conflicts string[] Conflicting paths with same basename
---@return string suffix Minimal distinguishing suffix
local function compute_unique_suffix(path, conflicts)
	local segments = vim.split(path, "/")

	-- Start with just basename
	for depth = 1, #segments - 1 do
		local suffix = table.concat(segments, "/", #segments - depth + 1)
		local is_unique = true

		for _, conflict in ipairs(conflicts) do
			if conflict:sub(- #suffix) == suffix then
				is_unique = false
				break
			end
		end

		if is_unique then
			return suffix
		end
	end

	-- Fallback to full path if no unique suffix found
	return path
end

---Get smart display name for a buffer with intelligent disambiguation.
---
---Returns just the basename if unique, or adds parent directories as needed
---to distinguish from other buffers with the same basename.
---
---@param filehash Filehash Buffer number to get display name for
---@return string display_name Smart basename with disambiguation
function M.get_smart_basename(filehash)
	local filepath = history.get_filepath_from_hash(filehash)

	if not filepath then
		error("Cannot get smart basename: filehash is nil or invalid")
	end

	local bufnr = history.get_buffer_from_hash(filehash)
	local name

	-- Handle invalid buffers
	if bufnr then
		-- Fast path: return cached if available
		if data.display_name_cache[filehash] then
			return data.display_name_cache[filehash]
		end

		-- Handle special buffer types
		if vim.bo[bufnr].buftype ~= "" then
			local display_name = "[" .. (vim.bo[bufnr].buftype or "No Name") .. "]"
			data.display_name_cache[filehash] = display_name
			return display_name
		end
		name = (vim.api.nvim_buf_is_valid(bufnr) or "") and vim.api.nvim_buf_get_name(bufnr)
	else
		name = filepath
	end

	if name == "" then
		local display_name = "[No Name]"
		data.display_name_cache[filehash] = display_name
		return display_name
	end

	-- Get basename and check for conflicts
	local basename = vim.fn.fnamemodify(name, ":t")
	local conflicts = find_basename_conflicts(basename, filehash)

	local display_name
	if #conflicts == 0 then
		-- No conflicts, just use basename
		display_name = basename
	else
		-- Conflicts exist, compute unique suffix
		display_name = compute_unique_suffix(name, conflicts)
	end

	-- Cache and return
	data.display_name_cache[filehash] = display_name
	return display_name
end

local function derive_cache_from_window_triquetra(winid)
	local window_triquetra = window.get_triquetra(winid)
	if window_triquetra then
		local ui_triquetra = data.get_or_create_window_display_cache(winid)

		-- Helper function to resolve slot data from filehash
		local function resolve_slot(filehash)
			local filepath = history.get_filepath_from_hash(filehash)
			if not filehash or not filepath then
				return nil, nil, false, false, false, false
			end

			local bufnr = history.get_buffer_from_hash(filehash)
			local display_name = M.get_smart_basename(filehash) or nil

			if bufnr ~= nil then
				-- Buffer exists in memory
				local is_loaded = vim.api.nvim_buf_is_loaded(bufnr)
				return bufnr, display_name, true, is_loaded, false
			else
				-- Check if it's a closed buffer
				local is_closed = vim.tbl_contains(history.data.closed_buffers, filehash)
				if is_closed then
					-- Closed buffer - can be reopened
					return nil, display_name, true, false, true -- exists=true, loaded=false
				else
					filepath = history.get_filepath_from_hash(filehash)
					if filepath == nil then
						error("This is unexpected: file " .. display_name .. " has no buffer or closed state. " .. winid)
					elseif vim.fn.filereadable(filepath) == 1 then -- ignore if the file is already deleted.
						error("This is unexpected: file " .. display_name .. " This thing happens? " .. winid)
					end
					return nil, nil, false, false, false
				end
			end
		end

		-- Update all slots using the hash-based WindowTriquetra structure
		ui_triquetra.current_bufnr, ui_triquetra.current_display_name, _, _, _ =
			resolve_slot(window_triquetra.current_slot)
		ui_triquetra.primary_bufnr, ui_triquetra.primary_display_name, ui_triquetra.has_primary, _, _ =
			resolve_slot(window_triquetra.primary_buffer)
		ui_triquetra.secondary_bufnr, ui_triquetra.secondary_display_name, ui_triquetra.has_secondary, ui_triquetra.loaded_slots.secondary, ui_triquetra.deleted_slots.secondary =
			resolve_slot(window_triquetra.secondary_slot)
		ui_triquetra.ternary_bufnr, ui_triquetra.ternary_display_name, ui_triquetra.has_ternary, ui_triquetra.loaded_slots.ternary, ui_triquetra.deleted_slots.ternary =
			resolve_slot(window_triquetra.ternary_slot)

		-- reflect the primary_enabled state.
		ui_triquetra.has_primary = ui_triquetra.has_primary and window_triquetra.primary_enabled

		if ui_triquetra.current_bufnr == nil then
			error("Impossible state: current_bufnr is nil in derive_cache_from_window_triquetra() for winid " .. winid)
		end

		return ui_triquetra
	end
	return nil
end


function M.set_cache_from_window_triquetra(winid)
	data.window_display_cache[winid] = derive_cache_from_window_triquetra(winid)
end

---Update bufferline state cache for performance optimization.
---
---Pre-computes buffer states for the bufferline to avoid expensive calculations
---during rendering. This is the migrated update_bufferline_state() function.
---
---@return nil
-- Function to update the cache state
function M.refresh_ui(cwin)
	local harpoon = require("harpoon")
	local cbuf = vim.api.nvim_win_get_buf(cwin)
	local cache = data.bufferline_state
	-- Update harpooned buffers cache
	local harpooned_list = harpoon:list():display()
	-- Helper function to map keys (from original buffers.lua)
	local function map_keys_trans_bufnr(tbl)
		local return_tbl = {}
		for idx, value in ipairs(tbl) do
			return_tbl[value] = idx
		end
		return return_tbl
	end
	cache.harpooned_lookup = map_keys_trans_bufnr(harpooned_list)
	-- Pre-compute which buffers are harpooned
	cache.harpooned_buffers = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
			cache.harpooned_buffers[bufnr] = cache.harpooned_lookup[path] ~= nil
			if cache.harpooned_buffers[bufnr] then
				cache.harpooned_lookup[bufnr] = cache.harpooned_lookup[path]
				cache.harpooned_lookup[path] = nil
			end
		end
	end
	-- Pre-compute buffer rankings using history domain data
	cache.buffer_ranking = {}
	for filehash, time in pairs(history.data.crux) do
		if filehash and history.data.hash_buffer_registry.buffers[filehash] then
			cache.buffer_ranking[history.data.hash_buffer_registry.buffers[filehash]] = time
		end
	end
	-- Pre-compute recent buffers using history domain data
	cache.recent_buffers = {}
	for i = 1, math.max(#history.data.ordered.crux, 30) do
		if i <= #history.data.ordered.crux then
			local recent = history.data.ordered.crux[i]
			if recent and recent.buf then
				cache.recent_buffers[recent.buf] = true
			end
		end
	end
	cache.current_buf = cbuf
	cache.history_detached = history.is_detached()

	-- Update current window triquetra display cache
	cache.current_window_triquetra = derive_cache_from_window_triquetra(cwin)

	cache.initialized = true
end

local function get_window_column_range(win_id)
	local win_info = vim.fn.getwininfo(win_id)[1]
	return {
		start = win_info.wincol,
		end_ = win_info.wincol + win_info.width,
	}
end

---@param winid1 WinId
---@param winid2 WinId
local function windows_overlap_horizontally(winid1, winid2)
	local range1 = get_window_column_range(winid1)
	local range2 = get_window_column_range(winid2)

	-- Mathematics of intersection reveals hidden connections
	return not (range1.end_ <= range2.start or range2.end_ <= range1.start)
end


---@param winid WinId
---@param theme UITriquetraTheme
local function construct_winbar_string(winid, theme)
	local triquetra = data.get_or_create_window_display_cache(winid)

	if triquetra == nil then
		error("This should never happen, current_window_triquetra is nil")
	end

	local fmt_sbufnr, fmt_cbufnr
	fmt_cbufnr = "[%d]"
	fmt_sbufnr = "⟦%d⟧"


	if navigation.is_cycling() then
		theme.current_slot_filename = theme.base
	end

	if triquetra.has_primary then
		if triquetra.primary_bufnr == triquetra.current_bufnr then
			theme.current_slot_bufnr = theme.primary_bufnr
			fmt_cbufnr = "⦉%d⦊"
		elseif triquetra.primary_bufnr == triquetra.secondary_bufnr then
			theme.secondary_slot_bufnr = theme.primary_bufnr
			fmt_sbufnr = "⦉%d⦊"
		elseif triquetra.primary_bufnr == triquetra.ternary_bufnr then
			theme.ternary_slot_bufnr = theme.primary_bufnr
		end
	else
		if triquetra.primary_bufnr == triquetra.current_bufnr then
			fmt_cbufnr = "⦉%d⦊"
			theme.current_slot_bufnr = "WinbarBufnrPrimaryDisabled"
		elseif triquetra.primary_bufnr == triquetra.secondary_bufnr then
			theme.secondary_slot_bufnr = "WinbarBufnrPrimaryDisabled"
			fmt_sbufnr = "⦉%d⦊"
		elseif triquetra.primary_bufnr == triquetra.ternary_bufnr then
			theme.ternary_slot_bufnr = "WinbarBufnrPrimaryDisabled"
		end
	end

	local display_string = ""
	local display_string_length = 0

	if triquetra.has_ternary then
		if not triquetra.deleted_slots.ternary then
			display_string = display_string .. string.format(
				"%%#%s#⦉%d⦊ ",
				theme.ternary_slot_bufnr, triquetra.ternary_bufnr
			)
			display_string_length = display_string_length + 3 +
				vim.api.nvim_strwidth(tostring(triquetra.ternary_bufnr))
		else
			display_string = display_string .. string.format(
				"%%#%s#⦉ %%#%s# %%#%s# %s ⦊",
				theme.ternary_slot_filename, theme.ternary_slot_bufnr, theme.ternary_slot_filename,
				triquetra.ternary_display_name
			)
			display_string_length = display_string_length +
				8 + vim.api.nvim_strwidth(triquetra.ternary_display_name)
		end
	end

	if triquetra.current_bufnr == nil then
		local window_triquetra = window.get_triquetra(winid)
		local debug_info = {
			winid = winid,
			current_slot = window_triquetra and window_triquetra.current_slot or "nil",
			filepath_exists = window_triquetra and window_triquetra.current_slot and history.get_filepath_from_hash(window_triquetra.current_slot) or "lookup_failed",
			buffer_exists = window_triquetra and window_triquetra.current_slot and history.get_buffer_from_hash(window_triquetra.current_slot) or "lookup_failed",
			actual_winbuf = vim.api.nvim_win_get_buf(winid)
		}
		vim.notify("WINBAR STATE CORRUPTION: current_bufnr is nil | " .. vim.inspect(debug_info), vim.log.levels.ERROR)
		vim.wo[winid].winbar = ""
		return
	end

	if vim.bo[triquetra.current_bufnr].modified then
		display_string = display_string .. string.format(
			"%%#%s#" .. fmt_cbufnr .. " %%#%s#%s%%#%s#  ",
			theme.current_slot_bufnr, triquetra.current_bufnr, theme.current_slot_filename,
			triquetra.current_display_name, theme.secondary_slot_filename
		)
		display_string_length = display_string_length + 6
	else
		display_string = display_string .. string.format(
			"%%#%s#" .. fmt_cbufnr .. " %%#%s#%s%%#%s# ",
			theme.current_slot_bufnr, triquetra.current_bufnr, theme.current_slot_filename,
			triquetra.current_display_name, theme.secondary_slot_filename
		)
		display_string_length = display_string_length + 4
	end

	display_string_length = display_string_length +
		vim.api.nvim_strwidth(triquetra.current_display_name) +
		vim.api.nvim_strwidth(tostring(triquetra.current_bufnr))


	if triquetra.has_secondary then
		if not triquetra.deleted_slots.secondary then
			if vim.bo[triquetra.secondary_bufnr].modified then
				display_string = display_string .. string.format(
					"%%#%s#   %%#%s#" .. fmt_sbufnr .. " %%#%s#%s  ",
					theme.both_way_arrow, theme.secondary_slot_bufnr, triquetra.secondary_bufnr,
					theme.secondary_slot_filename, triquetra.secondary_display_name
				)
				display_string_length = display_string_length + 10
			else
				display_string = display_string .. string.format(
					"%%#%s#   %%#%s#" .. fmt_sbufnr .. " %%#%s#%s ",
					theme.both_way_arrow, theme.secondary_slot_bufnr, triquetra.secondary_bufnr,
					theme.secondary_slot_filename, triquetra.secondary_display_name
				)
				display_string_length = display_string_length + 8
			end
			display_string_length = display_string_length + vim.api.nvim_strwidth(triquetra.secondary_display_name) +
				vim.api.nvim_strwidth(tostring(triquetra.secondary_bufnr))
		else
			display_string = display_string .. string.format(
				"%%#%s#  %%#%s#   %%#%s#%s ",
				theme.both_way_arrow, theme.secondary_slot_bufnr, theme.secondary_slot_filename,
				triquetra.secondary_display_name
			)
			display_string_length = display_string_length + 8
			display_string_length = display_string_length + vim.api.nvim_strwidth(triquetra.secondary_display_name)
		end
	end

	local diff = vim.api.nvim_strwidth(display_string)
	display_string = string.gsub(display_string, "zsh:terminal", "terminal:")
	diff = diff - vim.api.nvim_strwidth(display_string)

	display_string_length = display_string_length - diff

	display_string = string.format("%%#%s#────── ", theme.base) .. display_string
	display_string_length = display_string_length + 7

	local padding_length = vim.api.nvim_win_get_width(winid) - display_string_length
	display_string = display_string .. "%#" .. theme.base .. "#" .. string.rep("─", math.max(0, padding_length))

	vim.wo[winid].winbar = display_string
end


---@param winid WinId
---@param topwin WinId
local function update_topwin_winbar(winid, topwin)
	local winid_is_focused = vim.api.nvim_get_current_win() == winid
	local top_win_is_focused = vim.api.nvim_get_current_win() == topwin
	local cache = data.bufferline_state
	---@type UITriquetraTheme
	local theme

	-- local debug = "top_win: " .. top_win

	-- if this is true that means we don't need to reupdate this top_window's winbar,
	-- because it already found a window that it overlaps to.
	if preserve_winbar_overlap[topwin] then
		return 1
	end

	if windows_overlap_horizontally(winid, topwin) then
		if top_win_is_focused then
			theme = vim.deepcopy(data.winbar_themes.focused)
			preserve_winbar_overlap[topwin] = true
		else
			if winid_is_focused then
				theme = vim.deepcopy(data.winbar_themes.topwin_overlapped)
				preserve_winbar_overlap[topwin] = true
			else
				theme = vim.deepcopy(data.winbar_themes.unfocused)
			end
		end
	else
		theme = vim.deepcopy(data.winbar_themes.unfocused)
	end
	construct_winbar_string(topwin, theme)
end

---@param winid WinId
local function update_win_winbar(winid)
	---@type UITriquetraTheme
	local theme

	local winid_is_focused = vim.api.nvim_get_current_win() == winid
	-- local debug

	-- Determine highlight groups based on focus
	if winid_is_focused then
		theme = vim.deepcopy(data.winbar_themes.focused)
	else
		theme = vim.deepcopy(data.winbar_themes.unfocused)
	end

	construct_winbar_string(winid, theme)
end


function M.is_real_file(bufnr, win_id)
	local buftype = vim.bo[bufnr].buftype
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local filetype = vim.bo[bufnr].filetype
	local win_config = vim.api.nvim_win_get_config(win_id)

	-- Exclude floating/popup windows
	if win_config.relative ~= "" then
		return false
	end

	if
		(
			(
				filetype == "minimap" or
				filetype == "Avante" or
				filetype == "image_nvim"
			) and
			vim.api.nvim_win_get_height(win_id) > 30
		)
	then -- special exceptions
		return true
	end

	-- In the silence between keystrokes, we find truth
	local value = (buftype == "" or buftype == "terminal" or buftype == "acwrite") -- Empty buftype signifies a normal file buffer
		and vim.api.nvim_buf_is_loaded(bufnr)
		and (not vim.api.nvim_buf_get_name(bufnr):match("://") or buftype == "acwrite")
		and not vim.tbl_contains(data.excluded_filetypes, filetype)
		-- Allow no-name buffers for regular windows, exclude for popups
		and (bufname ~= "" or win_config.relative == "")

	return value
end

local function window_touches_top(win_id)
	-- Retrieve precise window coordinates
	-- local win_config = vim.api.nvim_win_get_config(win_id)
	local win_info = vim.fn.getwininfo(win_id)[1]

	-- A window's vertical solitude is measured in its distance from origin
	return win_info.winrow <= 2
end


local function update_all_winbars()
	local top_windows = {}
	local all_windows = {}
	-- local current_win = vim.api.nvim_get_current_win()

	-- First pass: identify windows touching the upper boundary
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if M.is_real_file(buf, win) then
			if window_touches_top(win) then
				table.insert(top_windows, win)
				update_topwin_winbar(win, win)
			else
				table.insert(all_windows, win)
				if vim.bo[buf].buftype ~= "terminal" then -- yes we include this to the logic, but it won't be visually affected.
					update_win_winbar(win)
				end
			end
		end
	end

	-- Second pass: update winbars based on spatial relationships
	for _, top_win in ipairs(top_windows) do
		for _, win in ipairs(all_windows) do
			update_topwin_winbar(win, top_win)
		end
	end
	-- reset the preserve_winbar_overlap state table
	preserve_winbar_overlap = {}
end

---We now need to show the UI Cache.
---
---@return nil
function M.show_ui()
	update_all_winbars()
end

---Debounce UI refresh to avoid exessive updates.
---
---@return nil
function M.debounced_update()
	if not update_timer then
		return
	end

	if update_timer:is_active() then
		update_timer:stop()
	end
	update_timer:start(
		100,
		0,
		vim.schedule_wrap(function()
			uiMachines.loop:to(states.LOOP.SELF)
		end)
	)
end

return M
