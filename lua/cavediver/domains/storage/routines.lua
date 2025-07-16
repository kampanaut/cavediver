---Storage domain core routines for session persistence.
---
---This module contains the main business logic for saving and loading
---complete system state across all domains, including serialization
---and file management operations.
---
---Buffer access history data structure (from buffers.lua M.sequence_buffer_history())
---Maps filehash (16-char SHA256 prefix) to access time (monotonically increasing index)
---Example: { ["a1b2c3d4e5f6g7h8"] = 42, ["z9y8x7w6v5u4t3s2"] = 43 }
---@class BufferHistoryData: table<string, number>
---
---@class WindowTriquetraSerialised
---@field [1] string Current buffer filename (window's active buffer)
---@field [2] string|vim.NIL Secondary filename (optional)
---@field [3] string|vim.NIL Primary filename (optional, mobile buffer)
---@field [4] string|vim.NIL Ternary filename (optional)
---
---Window buffer relationships data structure (from buffers.lua M.sequence_window_buffers())
---Maps window index to triquetra buffer relationship arrays
---Example: { [1] = { "/path/to/secondary.lua", "/path/to/primary.lua", vim.NIL } }
---@class WindowBufferData: table<number, WindowTriquetraSerialised>
---
---Closed buffer history data structure (from buffers.lua M.closed_buffers())
---Array of filenames that were closed and can be reopened
---Example: { "/path/to/closed1.lua", "/path/to/closed2.lua" }
---@class ClosedBufferData: string[]

local data = require('cavediver.domains.storage.data')
local history = require('cavediver.domains.history')
local historyState = require('cavediver.domains.history.states')
local window = require('cavediver.domains.window')

local M = {}


local function repeat_key(key, length)
	if #key >= length then
		return key:sub(1, length)
	end

	local times = math.floor(length / #key)
	local remain = length % #key

	local result = ''

	for i = 1, times do
		result = result .. key
	end

	if remain > 0 then
		result = result .. key:sub(1, remain)
	end

	return result
end

---Create a one-pass xor cipher for text encryption.
---@param text string
---@param key string
---@return string ciphered Base64-encoded XOR result
local function xor_cipher(text, key)
	local rkey = repeat_key(key, #text)

	local result = ''

	for i = 1, #text do
		local k_char = rkey:sub(i, i)
		local m_char = text:sub(i, i)

		local k_byte = k_char:byte()
		local m_byte = m_char:byte()

		local xor_byte = bit.bxor(m_byte, k_byte)

		local xor_char = string.char(xor_byte)

		result = result .. xor_char
	end

	-- Base64 encode the result to make it JSON-safe
	return vim.base64.encode(result)
end

---Create a one-pass xor decipher for text decryption.
---@param encoded_text string Base64-encoded XOR result
---@param key string
---@return string deciphered Original text
local function xor_decipher(encoded_text, key)
	-- Base64 decode first
	local text = vim.base64.decode(encoded_text)
	local rkey = repeat_key(key, #text)

	local result = ''

	for i = 1, #text do
		local k_char = rkey:sub(i, i)
		local m_char = text:sub(i, i)

		local k_byte = k_char:byte()
		local m_byte = m_char:byte()

		local xor_byte = bit.bxor(m_byte, k_byte)

		local xor_char = string.char(xor_byte)

		result = result .. xor_char
	end

	return result
end

---This is the main seralisers of the hashes. It adds a layer of privacy kekeburichi laputa.
---@param filehash Filehash Full file path
---@param cwd string Current working directory
---@return string|nil compressed_path Compressed path or original if no benefit
local function obfuscate_filehash_if_needed(filehash, cwd)
	local is_registered = history.get_buffer_from_hash(filehash)
	if is_registered == nil then -- this must be a closed buffer
		local filepath = history.get_filepath_from_hash(filehash)
		if filepath == nil then
			error("This must not be possible. You put a filehash not found on filepath and buffer registry?")
		end
		return xor_cipher(filepath, cwd)
	else
		return filehash
	end
end

---Decompress filepath by replacing hash prefix with actual CWD
---@param filehash string Potentially compressed file path
---@param cwd string Current working directory
---@return string decompressed_path Original file path
local function unobfuscate_filehash_if_needed(filehash, cwd)
	-- Check if this looks like a compressed path (32-char hash prefix)
	local is_registered = history.get_buffer_from_hash(filehash)
	if is_registered == nil then
		return xor_decipher(filehash, cwd)
	else
		local output = history.get_filepath_from_hash(filehash)
		if not output then
			error("This must not be possible. You put a filehash not found on filepath and buffer registry?")
		end
		return output
	end
end


---Loads buffer access history data.
---
---Rebuilds buffer hash mappings for all valid buffers currently open,
---then restores saved buffer access history with original timestamps.
---Corresponds to buffers.lua M.load_buffer_history().
---
---@param buffers BufferCruxInternals Buffer history from buffers.lua M.sequence_buffer_history()
---@return nil
local function load_buffer_history(buffers)
	---TODO: Loading [No Name] buffers with content.
	-- resession doesn't save no name buffers. So after load hook, I should scour all of the
	-- windows, and try to all the windows that has NONAME_ buffer, and try to load from a noname_content,
	-- that was also updated, in pre_save, where cavediver also tried to save for all NONAME buffers. Or is there
	-- a setting in resession to save no name buffers? I don't know.
	for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_valid(bufnr)
			and vim.api.nvim_buf_is_loaded(bufnr)
			and (
				vim.bo[bufnr].buftype == ""
				or vim.bo[bufnr].filetype == "image_nvim"
			)
			and (not vim.api.nvim_buf_get_name(bufnr):match("://"))
		then
			history.register_buffer(bufnr)
		end
	end

	for saved_filehash, time in pairs(buffers.global) do
		history.track_buffer(saved_filehash, time)
	end

	history.routines.initialise_crux_internals(buffers)
end


---Loads window buffer relationship data.
---
---Restores per-window triquetra relationships (primary/secondary/ternary buffers)
---for all valid windows. Maps window indices to buffer filename arrays.
---
---@param window_buffer WindowBufferData Window relationships from buffers.lua M.sequence_window_buffers()
---@param cwd string
---@return nil
local function load_window_buffer_relationships(window_buffer, cwd)
	if cwd == nil then
		error("Current working directory is not set.")
	end
	local starting_windows = {}
	local set_cache_from_window_triquetra = require('cavediver').set_cache_from_window_triquetra

	-- get valid windows
	for _, winid in pairs(vim.api.nvim_list_wins()) do
		local cbufnr = vim.api.nvim_win_get_buf(winid)
		if
			vim.bo[cbufnr].buftype == "" and (not vim.api.nvim_buf_get_name(cbufnr):match("://"))
		then
			table.insert(starting_windows, winid)
		end
	end

	for index, triquetra_serialised in pairs(window_buffer) do
		local actual_winid = starting_windows[index]
		if not (
				triquetra_serialised
				and triquetra_serialised ~= vim.NIL
				and starting_windows[index]
			)
		then
			goto continue
		end

		---@type Filehash|nil
		local cfilehash, sfilehash, tfilehash

		---@type Filehash[]|nil
		local pfilehashes = {}

		-- print_table(history.data)
		-- Current buffer [1] - try to restore or use window's current buffer
		if triquetra_serialised[1] ~= vim.NIL then
			local current_filepath = unobfuscate_filehash_if_needed(triquetra_serialised[1], cwd)
			history.register_filepath(current_filepath)
			cfilehash = history.get_hash_from_filepath(current_filepath)
			if cfilehash == nil then
				error("State Corruption: Cannot load window buffer relationship: The window has an unregistered buffer.")
			end
			if current_filepath:match("^NONAME_") then
				-- [No Name] buffer - try to restore from content
				local saved_hash = history.get_hash_from_filepath(current_filepath)
				if saved_hash and history.data.noname_content[current_filepath] then
					-- Restore [No Name] buffer
					local restored_bufnr = history.reopen_filehash(saved_hash)
					if restored_bufnr then
						vim.api.nvim_win_set_buf(actual_winid, restored_bufnr)
					end
				end
				cfilehash = history.get_hash_from_filepath(current_filepath)
			end
			-- print("current_filepath: " .. cfilehash)
		end

		-- Use actual current buffer if restoration failed
		local current_slot = cfilehash or history.get_hash_from_buffer(vim.api.nvim_win_get_buf(actual_winid))

		-- Secondary slot [2]
		if triquetra_serialised[2] ~= vim.NIL then
			sfilehash = history.get_hash_from_filepath(unobfuscate_filehash_if_needed(triquetra_serialised[2], cwd))
		end

		-- Primary buffer [3] - an array
		if #triquetra_serialised[3] > 0 then
			pfilehashes = vim.tbl_map(function (hash) return history.get_hash_from_filepath(unobfuscate_filehash_if_needed(hash, cwd)) end, triquetra_serialised[3]) or {}
		end

		-- Ternary slot [4]
		if triquetra_serialised[4] ~= vim.NIL then
			tfilehash = history.get_hash_from_filepath(unobfuscate_filehash_if_needed(triquetra_serialised[4], cwd))
		end

		if current_slot == nil then
			error("Cannot load window buffer relationship: The window has an unregistered buffer.")
		end

		-- print("=== DEBUG: Raw triquetra_serialised ===")
		-- print_table(triquetra_serialised)
		-- print("=== DEBUG: After unobfuscation ===")
		-- print("cfilehash: " .. (cfilehash or "nil"))
		-- print("pfilehash: " .. (pfilehash or "nil"))
		-- print("sfilehash: " .. (sfilehash or "nil"))
		-- print("tfilehash: " .. (tfilehash or "nil"))

		window.set_buffer_relationship(
			actual_winid,
			{
				current_slot = current_slot,
				secondary_slot = sfilehash,
				ternary_slot = tfilehash,
				primary_buffer = pfilehashes,
				displacement_ternary_map = {},
				displacement_secondary_map = {},
				primary_enabled = (pfilehashes and #pfilehashes and true) or false
			}
		)
		set_cache_from_window_triquetra(actual_winid)
		::continue::
	end
end

---Populate fresh buffer history from currently open buffers.
---
---Registers and tracks all valid buffers currently open in Neovim.
---Used when no saved session data exists to create initial history state.
---
---@return nil
local function populate_history()
	history.repopulate_history()
	window.repopulate_window_relationships()
end

---Serialize buffer access history for session saving.
---
---Creates a copy of the current buffer access history that can be
---safely serialized to JSON. Maps filehash to access timestamps.
---
---@return BufferCruxInternalsSerialised crux_serialised Serializable copy of buffer history
local function serialise_buffer_history()
	---@type table<string, table<Filehash, integer>>
	local serialised_window_cruxes = {}

	local compressed_index = 1
	for _, winid in pairs(vim.api.nvim_list_wins()) do
		if window.data.crux[winid] ~= nil then -- yes, a direct existence check sorry for breaking encapsulation
			local wbufnr = vim.api.nvim_win_get_buf(winid)

			local triquetra = window.get_triquetra(winid)
			if
				not (
					vim.bo[wbufnr].buftype == "" or
					(vim.api.nvim_buf_get_name(wbufnr):match("://") and triquetra and vim.bo[wbufnr].filetype ~= "cavediver-primary-buffer-history") or -- track a window with current buffer that is not tracked but with the current shown bufferr as a not regular file
					vim.bo[wbufnr].filetype == "image_nvim"
				)
			then
				goto continue
			end

			serialised_window_cruxes[compressed_index] = history.data.crux_internals.window[winid]
			compressed_index = compressed_index + 1
			::continue::
		end
	end
	return {
		window = serialised_window_cruxes,
		global = history.data.crux_internals.global
	}
end

---Serialize window buffer relationships for session saving.
---
---Creates a compressed representation of all window triquetra relationships
---that can be safely serialized to JSON. Maps window indices to filename arrays.
---
---@return WindowBufferData compressed Serializable window relationship data
---@param cwd string
local function serialise_window_relationships(cwd)
	if cwd == nil then
		error("Current working directory is not set.")
	end

	local compressed = {}

	local function get_keys(tbl)
		local keys = {}
		for k, _ in pairs(tbl) do
			table.insert(keys, k)
		end
		return keys
	end

	---@type Filehash[]
	local bufnr_list = get_keys(history.get_buffer_history())
	table.sort(bufnr_list)

	---@type WinId[]>
	local winid_list = get_keys(window.get_window_relationships())
	table.sort(winid_list)

	---@type table<WinId, boolean>

	local compressed_index = 1
	for _, winid in pairs(vim.api.nvim_list_wins()) do
		if window.data.crux[winid] ~= nil then -- yes, a direct existence check sorry for breaking encapsulation
			local wbufnr = vim.api.nvim_win_get_buf(winid)

			local triquetra = window.get_triquetra(winid)
			if
				not (
					vim.bo[wbufnr].buftype == "" or
					(vim.api.nvim_buf_get_name(wbufnr):match("://") and triquetra and vim.bo[wbufnr].filetype ~= "cavediver-primary-buffer-history") or -- track a window with current buffer that is not tracked but with the current shown bufferr as a not regular file
					vim.bo[wbufnr].filetype == "image_nvim"
				)
			then
				goto continue
			end

			local cfilehash, sfilehash, pfilehashes, tfilehash

			if not triquetra then
				error("This is impossible. The window triquetra must exist.")
			end

			-- Current buffer (window's active buffer)
			cfilehash = triquetra.current_slot
			sfilehash = triquetra.secondary_slot
			pfilehashes = triquetra.primary_buffer
			tfilehash = triquetra.ternary_slot

			local cfilepath = history.get_filepath_from_hash(cfilehash)

			if
				cfilepath and
				cfilepath:match("^NONAME_") and
				not vim.tbl_contains(history.data.closed_buffers, cfilehash)
			then
				if pfilehashes ~= nil and #pfilehashes > 0 then
					cfilehash = pfilehashes[1]
					pfilehashes = nil
				elseif tfilehash ~= nil then
					cfilehash = tfilehash
					tfilehash = nil
				elseif sfilehash ~= nil then
					cfilehash = sfilehash
					sfilehash = nil
				else
					cfilehash = "FUCKING BAD"
				end
			end

			if cfilehash == nil then
				cfilehash = vim.NIL
			else
				cfilehash = obfuscate_filehash_if_needed(cfilehash, cwd) or vim.NIL
			end

			-- Secondary slot
			if sfilehash == nil then
				sfilehash = vim.NIL
			else
				sfilehash = obfuscate_filehash_if_needed(sfilehash, cwd) or vim.NIL
			end

			-- Primary buffer (mobile)
			if pfilehashes == nil then
				pfilehashes = vim.NIL
			else
				pfilehashes = vim.tbl_map(function(hash) return obfuscate_filehash_if_needed(hash, cwd) end, pfilehashes)
			end

			-- Ternary slot
			if tfilehash == nil then
				tfilehash = vim.NIL
			else
				tfilehash = obfuscate_filehash_if_needed(tfilehash, cwd) or vim.NIL
			end

			compressed[compressed_index] = {
				[1] = cfilehash, -- Current buffer
				[2] = sfilehash, -- Secondary slot
				[3] = pfilehashes, -- Primary buffer
				[4] = tfilehash -- Ternary slot
			}
			compressed_index = compressed_index + 1
			::continue::
		end
	end
	return compressed
end

---Serialize closed buffer list for session saving.
---
---Creates a copy of the closed buffer filenames that can be safely
---serialized to JSON. Preserves the stack of reopenable files.
---
---@return ClosedBufferData copy Serializable copy of closed buffer list
---@param cwd string Current working directory
local function serialise_closed_buffers(cwd)
	local copy = {}
	if cwd == nil then
		error("Current working directory is not set.")
	end
	for k, v in pairs(history.get_closed_buffers()) do
		copy[k] = obfuscate_filehash_if_needed(v, cwd)
	end
	return copy
end

---Serialize [No Name] buffer content for session saving.
---
---Creates a copy of the [No Name] buffer content mapping that can be safely
---serialized to JSON. Preserves content, filetype, and cursor position.
---
---@return table<Filepath, NoNameBufferContent> copy Serializable copy of [No Name] content
---@param cwd string Current working directory
local function serialise_noname_content(cwd)
	local copy = {}
	if cwd == nil then
		error("Current working directory is not set.")
	end
	for identifier, content in pairs(history.data.noname_content) do
		-- print("identifier: " .. identifier)
		copy[obfuscate_filehash_if_needed(identifier, cwd)] = {
			lines = vim.tbl_map(function(line) return xor_cipher(line, cwd) end, content.lines),
			filetype = content.filetype,
			cursor = content.cursor
		}
	end
	return copy
end

---Loads closed buffer history data.
---
---Restores the stack of closed buffer filenames that can be reopened.
---Validates that files still exist before adding to the reopenable stack.
---
---@param closed_buffers ClosedBufferData Closed buffer list from buffers.lua M.closed_buffers()
---@param noname_content table<Filepath, NoNameBufferContent> [No Name] content from session
---@param cwd string
---@return nil
local function load_closed_buffers(closed_buffers, noname_content, cwd)
	if cwd == nil then
		error("Current working directory is not set.")
	end
	history.clear_closed_buffers()

	-- TODO: Open closed no name buffers with their content.
	if closed_buffers == nil then
		return
	end

	for _, obf_filehash in pairs(closed_buffers) do
		local filepath = unobfuscate_filehash_if_needed(obf_filehash, cwd) -- return: either closed filepath or NONAME_<x>
		history.register_filepath(filepath)
		local filehash = history.get_hash_from_filepath(filepath)
		if not filehash then
			error("What the fuck. This is impossible.")
		end
		if filepath:match("^NONAME_") then
			if history.data.noname_content[filehash] == nil then
				local content = noname_content[obf_filehash]
				if content == nil then
					error("This is impossible. Noname content must be created for this closed No Name buffer.")
				end
				history.data.noname_content[filehash] = {
					lines = vim.tbl_map(function(line) return xor_decipher(line, cwd) end, content.lines),
					filetype = content.filetype,
					cursor = content.cursor
				}
			else
				error("This is impossible. The closed buffer must not already exist in noname_content.")
			end
		else
			if vim.fn.bufexists(filepath) ~= 0 then
				error("This is impossible. The closed buffer must not already show in view. What the fuck.")
			end
		end
		table.insert(history.data.closed_buffers, history.get_hash_from_filepath(filepath))
	end
	-- print_table(history.data.closed_buffers)
end

---Helper function to get project hash from project path.
---@param pwd string Project path
---@return string project_hash Project hash derived from the project path
local function get_session_filepath(pwd)
	if not pwd then
		error("No pwd provided to get_project_hash")
	end

	local dir_hash = string.sub(
		vim.fn.system('echo "' .. pwd .. '" | sha256sum'),
		1, 32 -- Use 32 chars for better collision resistance
	)

	-- TODO: implement configurable path for session storage
	local session_dir = vim.fn.stdpath("data") .. "/cavediver/sessions/"
	local project_filepath = session_dir .. dir_hash .. '.json'

	vim.fn.mkdir(session_dir, "p")

	return project_filepath
end

---Load complete session history data.
---
---Main entry point for restoring all buffer and window state from saved session.
---Coordinates loading of buffer history, window relationships, and closed buffers.
---
---@param cwd string current working directory
---@return nil
function M.load_history(cwd)
	if not cwd then
		error("Invalid current working directory.")
	end
	local file_path = get_session_filepath(cwd)

	-- Try to load existing session data
	local saved_data = nil
	if vim.loop.fs_stat(file_path) then
		local success, file_content = pcall(vim.fn.readfile, file_path)
		if success then
			local json_success, json_data = pcall(vim.fn.json_decode, file_content)
			if json_success and json_data then
				if json_data.buffers and json_data.windows then
					saved_data = json_data
				end
			end
		end
	end

	if saved_data then
		-- Restore from saved session
		load_buffer_history(saved_data.buffers)
		if saved_data.closed then
			load_closed_buffers(saved_data.closed, saved_data.noname_content or {}, cwd)
		end
		load_window_buffer_relationships(saved_data.windows, cwd)
	else
		populate_history()
	end

	-- Run cleanup after loading to handle any inconsistencies
	history.cleanup_system()

	history.sm:to(historyState.ATTACHED, { buf = vim.api.nvim_get_current_buf() }, history.states.mode.UPDATE)
	-- print_table(history.data)
	-- print_table(window.data)
end

---Save complete session history data to persistent storage.
---
---Serializes all buffer history, window relationships, and closed buffers
---to a JSON file organized by current working directory for per-project sessions.
---
---@param cwd string Current working directory to save session data for
---@return nil
function M.save_history(cwd)
	if not cwd then
		error("Invalid current working directory.")
	end

	-- Run cleanup before saving to ensure clean state
	history.cleanup_system()

	local file_path = get_session_filepath(cwd)

	-- Create empty JSON file if it doesn't exist
	---@diagnostic disable-next-line: undefined-field
	if vim.loop.fs_stat(file_path) == nil then
		vim.fn.writefile({ "{}" }, file_path)
	end

	local storage = {
		buffers = serialise_buffer_history(),
		windows = serialise_window_relationships(cwd),
		closed = serialise_closed_buffers(cwd),
		noname_content = serialise_noname_content(cwd),
	}

	-- Write updated data back to file
	local write_success = pcall(vim.fn.writefile, { vim.fn.json_encode(storage) }, file_path)
	if not write_success then
		error("Failed to write session data to file: " .. file_path)
	end
end

return M
