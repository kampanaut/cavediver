local data = require("cavediver.domains.history.data")
local configs = require("cavediver.configs")

local M = {}

local function is_no_name_buffer(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)

	return vim.bo[bufnr].buftype == ""  -- Normal buffer (not terminal, help, etc.)
		and (not filename:match("://"))
		and filename == ""              -- No filename set
		and vim.api.nvim_buf_is_loaded(bufnr) -- Buffer is loaded
end

---Generate a file hash from filename for buffer tracking.
---
---Creates a 16-character SHA256 hash prefix from the filename for use as
---a unique identifier in the buffer history system.
---
---@param filename string Full path to the file
---@return string filehash 16-character hash prefix
function M.get_filehash(filename)
	local filehash = string.sub(
		vim.fn.system('echo "' .. filename .. '" | sha256sum'),
		1,
		16
	)
	return filehash
end

---Register a buffer in the hash-to-buffer mapping system.
---
---Creates bidirectional mapping between file hash and buffer number for
---efficient buffer lookup and validation.
---
---@param bufnr number Buffer number to register
---@return Filehash filehash
function M.register_buffer(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if vim.bo[bufnr].buftype ~= "" and vim.bo[bufnr].buftype == "image_nvim" then
		error("I don't want to track non-file buffers.")
	end
	if filepath == "" then
		filepath = tostring("NONAME_" .. tostring(bufnr))
	end
	local filehash = M.get_filehash(filepath)

	if data.hash_buffer_registry.buffers[filehash] then
		-- print("Oh yes I did.")
		data.hash_buffer_registry.hashes[data.hash_buffer_registry.buffers[filehash]] = nil
	end

	-- skip if for filepath is already registered. It's already one-to-one.

	data.hash_buffer_registry.buffers[filehash] = bufnr
	data.hash_buffer_registry.hashes[bufnr] = filehash
	data.hash_filepath_registry.filepaths[filehash] = filepath
	data.hash_filepath_registry.hashes[filepath] = filehash

	return filehash
end

---Register a filepath in the hash-to-filepath mapping system.
---
---@param filepath Filepath
---@return nil
function M.register_filepath(filepath)
	if filepath == "" then
		error("Cannot register an empty filepath.")
	end

	local filehash = M.get_filehash(filepath)

	data.hash_filepath_registry.hashes[filepath] = filehash
	data.hash_filepath_registry.filepaths[filehash] = filepath
end

---Unregister a buffer from the regietry
---
---Removes the buffer from the hash-to-buffer mapping system.
---@param bufnr number Buffer number to unregister
function M.unregister_buffer(bufnr)
	local filehash = data.hash_buffer_registry.hashes[bufnr]
	if filehash == nil then return end

	data.hash_buffer_registry.hashes[bufnr] = nil
	data.hash_buffer_registry.buffers[filehash] = nil
end

---unregister a filepath from the registry
---@param filepath Filepath
function M.unregister_filepath(filepath)
	local filehash = data.hash_filepath_registry.hashes[filepath]

	if filehash == nil then return end

	data.hash_filepath_registry.hashes[filepath] = nil
	data.hash_filepath_registry.filepaths[filehash] = nil
end

---Initialize the history crux and internal crux structures.
---
---@param crux_internals BufferCruxInternals
---@return nil
function M.initialise_crux_internals(crux_internals)
	local starting_windows = {}

	data.crux_internals.window = {}

	-- get valid windows
	for _, winid in pairs(vim.api.nvim_list_wins()) do
		local cbufnr = vim.api.nvim_win_get_buf(winid)
		if
			vim.bo[cbufnr].buftype == "" and (not vim.api.nvim_buf_get_name(cbufnr):match("://"))
		then
			table.insert(starting_windows, winid)
		end
	end

	for index, window_crux_serialised in ipairs(crux_internals.window) do
		local actual_winid = starting_windows[index]
		data.crux_internals.window[actual_winid] = window_crux_serialised
	end
	data.crux_internals.global = crux_internals.global
	M.construct_crux(vim.api.nvim_get_current_win())
end

---Construct the crux from the internal cruxes, from the global and
---a window specific crux, if winid is provided. Otherwise it will
---construct the crux with only the global crux.
---
---This function merges the global crux with the window-specific crux
---
---@param winid WinId|nil
function M.construct_crux(winid)
	local global_copy = vim.fn.deepcopy(data.crux_internals.global)
	if not winid or configs.bufferline.history_view == "global" then
		data.crux = global_copy
		return
	end

	if data.crux_internals.window[winid] == nil or next(data.crux_internals.window[winid]) == nil then
		data.crux_internals.window[winid] = {}
		data.crux = global_copy
		return
	end

	local window_buffers = {}
	for key, value in pairs(data.crux_internals.window[winid]) do
		table.insert(window_buffers, { hash = key, time = value })
	end
	table.sort(window_buffers, function(a, b) return a.time > b.time end)

	data.history_index = data.history_index + #window_buffers - 1
	-- Assign increments based on rank
	for rank, buffer in ipairs(window_buffers) do
		global_copy[buffer.hash] = data.history_index - rank + 1
	end

	data.crux = global_copy
end

---Track buffer access in the history timeline.
---
---Adds or updates buffer access time in the history crux. If no time is provided,
---uses current history index and increments it. Used for both new access tracking
---and restoring saved session data.
---
---@param filehash Filehash File hash of the buffer to track
---@param time number|nil Access time index (nil = use current index)
function M.track_buffer(filehash, time)
	if time == nil then
		data.crux[filehash] = data.history_index
		data.crux_internals.global[filehash] = data.history_index
		data.history_index = data.history_index + 1
	else
		data.crux[filehash] = time
		data.crux_internals.global[filehash] = data.history_index
		if data.history_index <= time then
			data.history_index = time + 1
		end
	end

	local winid = require("cavediver.domains.navigation.routines").find_most_recent_tracked_window()
	if winid then
		if data.crux_internals.window[winid] == nil then
			data.crux_internals.window[winid] = {}
		end
		data.crux_internals.window[winid][filehash] = data.history_index - 1
	end
end

---Untrack the buffer access in the history crux.
---
---Removes the buffer from the history crux, effectively
---@param bufnr Bufnr File hash of the buffer to untrack
function M.untrack_buffer(bufnr)
	local filehash = data.hash_buffer_registry.hashes[bufnr]
	if data.crux[filehash] ~= nil then
		data.crux[filehash] = nil
	end

	if data.crux_internals.global[filehash] ~= nil then
		data.crux_internals.global[filehash] = nil
	end

	for winid, _ in pairs(data.crux_internals.window) do
		if filehash ~= nil then 
			data.crux_internals.window[winid][filehash] = nil
		end
	end

	M.update_buffer_history_ordered()
	M.update_buffer_history_ordered_nonharpooned()
end

---Update buffer history with the current access time for regular file buffers.
---
---Records buffer access in the history system if it's a valid file buffer.
---Only tracks normal file buffers and image_nvim buffers that are readable files.
---
---@param cbufnr number|nil Buffer number (defaults to current buffer)
---@return boolean history_modified True if the buffer was successfully registered and tracked
function M.update_buffer_history(cbufnr)
	cbufnr = cbufnr or vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(cbufnr)

	-- Check if the buffer is a "normal" file buffer
	---@type Filehash
	local filehash = data.hash_buffer_registry.hashes[cbufnr]
	if filehash == nil then
		if vim.bo[cbufnr].buftype == "" and (not filename:match("://")) then
			filehash = M.register_buffer(cbufnr)
		else
			return false
		end
	else
		if is_no_name_buffer(cbufnr) then
			filehash = M.get_filehash("NONAME_" .. tostring(cbufnr))
		elseif
			vim.fn.filereadable(filename) == 1
			and vim.fn.isdirectory(filename) == 0
		then
			filehash = M.get_filehash(filename)
		else
			M.untrack_buffer(cbufnr)
			M.unregister_buffer(cbufnr) -- clean this up. this buffer evolved into something we don't like.
			M.unregister_filepath(filename)
			return false
		end
	end

	M.track_buffer(filehash, nil)
	return true
end

---Update ordered buffer history list sorted by recency.
---
---Rebuilds the ordered buffer list from the current history crux.
---Validates buffer hash mappings and removes invalid entries.
---
---@return BufferHistoryItem[] ordered Buffers ordered by recency (most recent first)
function M.update_buffer_history_ordered()
	data.ordered.crux = {}
	for filehash, access_time in pairs(data.crux) do
		-- print_table(filehash_to_bufnr)
		if not data.hash_buffer_registry.buffers[filehash] then
			data.crux[filehash] = nil -- Remove invalid buffer from history
			goto continue
		end
		table.insert(
			data.ordered.crux,
			{ buf = data.hash_buffer_registry.buffers[filehash], time = access_time }
		)
		::continue::
	end
	table.sort(data.ordered.crux, function(a, b)
		return a.time > b.time
	end)
	return data.ordered.crux
end

---Check if a bufnr is harpooned mark.
---
---@param bufnr Bufnr
---@return boolean
local function is_harpooned(bufnr)
	local harpoon = require("harpoon")
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		return vim.tbl_contains(
			harpoon:list():display(),
			vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
		)
	else
		return false
	end
end

---Update ordered non-harpooned buffer history list.
---
---Rebuilds the non-harpooned buffer list by filtering out harpooned buffers
---from the main ordered list. Updates the harpooned buffer count.
---
---@return BufferHistoryItem[] ordered Non-harpooned buffers ordered by recency
function M.update_buffer_history_ordered_nonharpooned()
	data.ordered.nonharpooned = {}
	for _, item in pairs(data.ordered.crux) do
		-- print_table(item)
		-- Only consider buffers that are valid and loaded
		if not is_harpooned(item.buf) then
			table.insert(
				data.ordered.nonharpooned,
				{ buf = item.buf, time = item.time }
			)
		end
	end
	table.sort(data.ordered.nonharpooned, function(a, b)
		return a.time > b.time
	end)
	return data.ordered.nonharpooned
end

---Take a snapshot of window's buffer relationships before cycling.
---
---Captures the current window's triquetra state for restoration after cycling.
---Stores a deep copy of the window relationships for later restoration.
---
---@param winid number Window ID to snapshot
function M.snapshot_origin(winid)
	-- window's data.crux[winid] is ensured to be non-nil.
	local get_smart_basename = require('cavediver.domains.ui.routines').get_smart_basename
	data.cycling_origins[winid] = require('cavediver.domains.window').get_triquetra(winid)

	local current_slot = data.hash_buffer_registry.hashes[vim.api.nvim_win_get_buf(winid)]
	local secondary_slot = data.cycling_origins[winid].secondary_slot
	local sslot_display_string

	if current_slot == nil then
		error("This is impossible: current buffer is not registered.")
	end

	if secondary_slot == nil then
		sslot_display_string = "Unfilled"
	else
		sslot_display_string = get_smart_basename(secondary_slot)
	end

	data.cycling_origins[winid].current_slot = current_slot

	vim.notify(
		"Checkpoint saved: \n" ..
		get_smart_basename(current_slot) ..
		" -> " ..
		sslot_display_string
	)
end

---Reopen a filepath derived from a file hash. The file hash
---must be registered during this session.
---
---@param filehash Filehash
---@return Bufnr|nil bufnr Buffer number if hash is registered, nil if not found
function M.reopen_filehash(filehash)
	local filepath = data.hash_filepath_registry.filepaths[filehash]
	if filepath == nil then
		return nil
	end

	for i = #data.closed_buffers, 1, -1 do
		if data.closed_buffers[i] == filehash then
			table.remove(data.closed_buffers, i)
			break
		end
	end
	local bufnr
	if filepath:match("^NONAME_") then
		local cache = data.noname_content[filehash]
		bufnr = vim.api.nvim_create_buf(true, false)

		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, cache.lines)
		vim.bo[bufnr].filetype = cache.filetype
		vim.bo[bufnr].buftype = ""
		vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), cache.cursor)
		M.register_buffer(bufnr)
		M.track_buffer(filehash)
		data.noname_content[filehash] = nil
		if M.get_filepath_from_buffer(bufnr) ~= filepath then
			M.unregister_filepath(filepath) -- This NONAME_ buffer is now irrelevant, we don't want to track it anymore.
		end
	elseif filepath and vim.fn.filereadable(filepath) == 1 then
		bufnr = vim.fn.bufadd(filepath)
		vim.fn.bufload(bufnr)
		vim.bo[bufnr].buflisted = true
		M.register_buffer(bufnr)
		M.track_buffer(filehash)
	end

	if bufnr then
		M.update_buffer_history(bufnr)
		M.update_buffer_history_ordered()
		M.update_buffer_history_ordered_nonharpooned()
		return bufnr
	else
		return nil
	end
end

---Track closed filehashes for potential reopening.
---
---The filehash must still be rigistered in the hash_buffer_registry.
---@param filehash Filehash THE FILEHASH MUST BE REGISTERED
---@return boolean success True if the filehash was added to the closed buffers registry
function M.track_closing_filehash(filehash)
	local filepath = data.hash_filepath_registry.filepaths[filehash]
	local bufnr = data.hash_buffer_registry.buffers[filehash]

	if filepath == nil then
		error("This must not happen: Closing filehash is not registered at all.")
	end
	if bufnr == nil then
		error("The closing filehash must be registered in the hash_buffer_registry.")
	end

	if filepath:match("^NONAME_") then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		-- Check if buffer is empty (no lines or single empty line)
		if #lines == 0 or (#lines == 1 and lines[1] == "") then
			M.unregister_filepath(filepath) -- Yes, remove it from the system entirely. We are not interested in empty no name buffers.
			return false           -- Don't track empty [No Name] buffers
		end

		local winid = vim.fn.bufwinid(bufnr)
		data.noname_content[filehash] = {
			lines = lines,
			filetype = vim.bo[bufnr].filetype,
			cursor = winid ~= -1 and vim.api.nvim_win_get_cursor(winid) or { 1, 0 }
		}
	end

	table.insert(data.closed_buffers, filehash)
	return true
end


---Force label a filehash as a closed filehash
---
---BE CAREFUL: 
---    - This will not check if the filehash is registered in the hash_buffer_registry.
---    - This is not designed for NONAME_ buffers as well!
function M.track_closing_filehash_force(filehash)
	if filehash == nil then
		error("This must not happen: Closing filehash is not registered at all.")
	end

	table.insert(data.closed_buffers, filehash)
end


---Reopen last closed buffer
---
---@return Bufnr|nil bufnr Buffer number of the reopened buffer, or nil if no closed buffers exist
function M.reopen_last_closed()
	if #data.closed_buffers == 0 then
		vim.notify("No closed buffers to reopen.", vim.log.levels.WARN)
		return nil
	end

	local filehash = table.remove(data.closed_buffers)
	local bufnr = M.reopen_filehash(filehash)
	if bufnr then
		vim.api.nvim_set_current_buf(bufnr)
	end
end

---Unregister a buffer and delete it from the tracking system
function M.delete_buffer(winid)
	local bufnr = vim.api.nvim_win_get_buf(winid)

	-- Check if buffer has unsaved changes. Avoid deleting unsaved buffers.
	if vim.api.nvim_buf_get_name(bufnr) ~= "" and vim.bo[bufnr].modified then
		vim.notify("Buffer has unsaved changes", vim.log.levels.WARN)
		return false
	end

	-- Check if buffer is shown in multiple windows
	local buffer_usage_count = 0
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == bufnr then
			buffer_usage_count = buffer_usage_count + 1
		end
	end

	if buffer_usage_count > 1 then
		vim.notify("Can't delete buffer because it's shown in another window.", vim.log.levels.WARN)
		return false
	end

	-- Check if it's the only buffer left
	local total_buffers = 0
	for _ in pairs(data.crux) do
		total_buffers = total_buffers + 1
	end

	if total_buffers <= 1 then
		vim.notify("Can't delete buffer because it's the only one left", vim.log.levels.WARN)
		return false
	end

	-- Find next buffer in ordered history list
	local ordered_buffers = data.ordered.crux
	local current_index = nil

	-- Find current buffer's position in ordered list
	for i, entry in ipairs(ordered_buffers) do
		if entry.buf == bufnr then
			current_index = i
			break
		end
	end

	local next_bufnr
	if current_index then
		if current_index == 1 and #ordered_buffers >= 2 then
			-- If deleting most recent, go to second most recent
			next_bufnr = ordered_buffers[2].buf
		elseif current_index > 1 then
			-- Otherwise go to most recent (first in list)
			next_bufnr = ordered_buffers[((current_index) % #ordered_buffers) + 1].buf
		end
	else
		error("This is impossible: Current buffer not found in ordered history.")
	end

	-- Switch to next buffer before deletion
	if next_bufnr and vim.api.nvim_buf_is_valid(next_bufnr) then
		vim.api.nvim_set_current_buf(next_bufnr)
	end

	-- Delete the buffer
	vim.cmd("bw! " .. bufnr)
	-- Our own BufDelete hook handles the untracking and wrapup

	return true
end

---Get buffer number from file hash.
---
---@param hash Filehash File hash
---@return Bufnr|nil bufnr Buffer number or nil if not found
function M.get_buffer_from_hash(hash)
	if hash == nil then
		return nil
	end
	return data.hash_buffer_registry.buffers[hash]
end

---Get file hash from buffer number.
---
---@param bufnr Bufnr Buffer number
---@return Filehash|nil hash File hash or nil if not found
function M.get_hash_from_buffer(bufnr)
	if bufnr == nil then
		return nil
	end
	return data.hash_buffer_registry.hashes[bufnr]
end

---Get filepath from file hash
---
---@param hash Filehash File hash
---@return Filepath|nil filepath File path or nil if not found
function M.get_filepath_from_hash(hash)
	if hash == nil then
		return nil
	end
	return data.hash_filepath_registry.filepaths[hash]
end

---Get filepath from buffer number
---
---@param bufnr Bufnr File hash
---@return Filepath|nil filepath File path or nil if not found
function M.get_filepath_from_buffer(bufnr)
	local filehash = data.hash_buffer_registry.hashes[bufnr]
	if bufnr == nil or filehash == nil then
		return nil
	end
	return data.hash_filepath_registry.filepaths[filehash]
end

---Get filepath from buffer number
---
---@param filepath Filehash File hash
---@return Filehash|nil filepath File hash or nil if not found
function M.get_hash_from_filepath(filepath)
	if filepath == nil then
		return nil
	end
	return data.hash_filepath_registry.hashes[filepath]
end

---Comprehensive system cleanup and validation.
---
---Removes orphaned entries, validates registries, and ensures data consistency.
---Should be called periodically and before critical operations like saving.
---
---@return table cleanup_report Summary of what was cleaned up
function M.cleanup_system()
	local report = {
		orphaned_history = 0,
		orphaned_hashes = {},
		invalid_closed_buffers = 0,
		invalid_closed_hashes = {},
		stale_hash_entries = 0,
		stale_hashes = {},
		invalid_triquetra_refs = 0,
		updated_lists = false
	}

	-- 1. Clean orphaned history entries (filehashes in crux without buffer registration)
	local orphaned_hashes = {}
	for filehash, _ in pairs(data.crux) do
		if not data.hash_buffer_registry.buffers[filehash] then
			table.insert(orphaned_hashes, filehash)
		end
	end

	for _, filehash in ipairs(orphaned_hashes) do
		data.crux[filehash] = nil
		data.crux_internals.global[filehash] = nil
		for winid, _ in pairs(data.crux_internals.window) do
			if data.crux_internals.window[winid][filehash] then
				 data.crux_internals.window[winid][filehash] = nil
			end
		end
		table.insert(report.orphaned_hashes, filehash)
		report.orphaned_history = report.orphaned_history + 1
	end

	-- 2. Clean invalid closed buffers (files that no longer exist)
	local invalid_closed = {}
	for i, filehash in ipairs(data.closed_buffers) do
		local filepath = data.hash_filepath_registry.filepaths[filehash]
		local match_status = filepath:match("^NONAME_")
		if
			(not filepath) or
			(
				match_status and
				(not vim.tbl_contains(data.closed_buffers, filehash))
			) or
			(
				not match_status and
				vim.fn.filereadable(filepath) == 0
			) or
			(
				data.hash_buffer_registry.buffers[filehash] ~= nil
			)
		then
			table.insert(invalid_closed, i)
		end
	end

	-- Remove invalid closed buffers (reverse order to maintain indices)
	for i = #invalid_closed, 1, -1 do
		local filehash = data.closed_buffers[invalid_closed[i]]
		table.insert(report.invalid_closed_hashes, filehash)
		table.remove(data.closed_buffers, invalid_closed[i])
		report.invalid_closed_buffers = report.invalid_closed_buffers + 1
	end

	-- 3. Clean stale hash registry entries (buffers that no longer exist)
	local stale_bufnrs = {}
	for filehash, bufnr in pairs(data.hash_buffer_registry.buffers) do
		if not vim.api.nvim_buf_is_valid(bufnr) then
			table.insert(stale_bufnrs, { filehash, bufnr })
		end
	end

	for _, entry in ipairs(stale_bufnrs) do
		local filehash, bufnr = entry[1], entry[2]
		table.insert(report.stale_hashes, filehash)
		data.hash_buffer_registry.buffers[filehash] = nil
		data.hash_buffer_registry.hashes[bufnr] = nil
		report.stale_hash_entries = report.stale_hash_entries + 1
	end

	-- 4. Validate triquetra references across windows
	local window = require('cavediver.domains.window')
	for winid, triquetra in pairs(window.data.crux) do
		local slots_to_check = { triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot, triquetra
			.primary_buffer[1] }
		for _, slot in ipairs(slots_to_check) do
			if slot and not data.hash_filepath_registry.filepaths[slot] then
				-- Triquetra references invalid filehash
				report.invalid_triquetra_refs = report.invalid_triquetra_refs + 1
			end
		end
	end

	-- 5. Update ordered lists after cleanup
	if report.orphaned_history > 0 or report.stale_hash_entries > 0 then
		M.update_buffer_history_ordered()
		M.update_buffer_history_ordered_nonharpooned()
		report.updated_lists = true
	end

	return report
end

---Force manual cleanup and return report.
---
---Useful for debugging and manual maintenance.
---
---@return table cleanup_report Summary of what was cleaned up
function M.force_cleanup()
	local report = M.cleanup_system()

	local messages = {}
	if report.orphaned_history > 0 then
		table.insert(messages, report.orphaned_history .. " orphaned history entries")
	end
	if report.invalid_closed_buffers > 0 then
		table.insert(messages, report.invalid_closed_buffers .. " invalid closed buffers")
	end
	if report.stale_hash_entries > 0 then
		table.insert(messages, report.stale_hash_entries .. " stale hash entries")
	end
	if report.invalid_triquetra_refs > 0 then
		table.insert(messages, report.invalid_triquetra_refs .. " invalid triquetra references")
	end

	if #messages > 0 then
		local output = { "Cleanup completed: " .. table.concat(messages, ", ") }
		
		if #report.orphaned_hashes > 0 then
			table.insert(output, "Orphaned files:")
			for _, hash in ipairs(report.orphaned_hashes) do
				local path = data.hash_filepath_registry.filepaths[hash] or hash
				table.insert(output, "  - " .. path)
			end
		end
		
		if #report.invalid_closed_hashes > 0 then
			table.insert(output, "Invalid closed files:")
			for _, hash in ipairs(report.invalid_closed_hashes) do
				local path = data.hash_filepath_registry.filepaths[hash] or hash
				table.insert(output, "  - " .. path)
			end
		end
		
		if #report.stale_hashes > 0 then
			table.insert(output, "Stale files:")
			for _, hash in ipairs(report.stale_hashes) do
				local path = data.hash_filepath_registry.filepaths[hash] or hash
				table.insert(output, "  - " .. path)
			end
		end
		
		vim.notify(table.concat(output, "\n"), vim.log.levels.INFO)
	else
		vim.notify("System cleanup completed - no issues found", vim.log.levels.INFO)
	end

	return report
end

-- Fucking reset everything.
function M.repopulate_history()
	data.crux = {}
	data.hash_buffer_registry.buffers = {}
	data.hash_buffer_registry.hashes = {}
	data.hash_filepath_registry.hashes = {}
	data.hash_filepath_registry.filepaths = {}
	data.history_index = 1
	data.cycling_origins = {}
	data.closed_buffers = {}
	data.noname_content = {}

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			M.update_buffer_history(bufnr)
		end
	end
	M.update_buffer_history_ordered()
	M.update_buffer_history_ordered_nonharpooned()
end

return M
