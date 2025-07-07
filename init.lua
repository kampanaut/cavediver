---Cavediver - Sophisticated buffer and window management plugin
---
---A state machine-driven buffer management system with triquetra window relationships,
---hash-based buffer tracking, and XOR-obfuscated session persistence.
---
---@class Cavediver
local M = {}

-- Import all domains
local navigation = require('domains.navigation')
local history = require('domains.history')
local window = require('domains.window')
local ui = require('domains.ui')
local storage = require('domains.storage')
local engine = require('engine')

local settings = require('configs')

-- Export domains for direct access (backward compatibility)
M.navigation = navigation
M.history = history
M.window = window
M.ui = ui
M.storage = storage
M.engine = engine

---Setup keymaps for cavediver operations
---@param keymaps CavediverKeymaps Keymap configuration
local function setup_keymaps(keymaps)
	if not keymaps then return end

	-- Buffer lifecycle
	if keymaps.reopen_last_closed then
		vim.keymap.set('n', keymaps.reopen_last_closed, function()
			M.reopen_last_closed()
		end, { desc = "Reopen last closed buffer" })
	end

	-- Core triquetra operations
	if keymaps.toggle_secondary then
		vim.keymap.set('n', keymaps.toggle_secondary, function()
			M.toggle_secondary()
		end, { desc = "Toggle current ↔ secondary buffer" })
	end

	if keymaps.toggle_ternary then
		vim.keymap.set('n', keymaps.toggle_ternary, function()
			M.toggle_ternary()
		end, { desc = "Toggle current ↔ ternary buffer" })
	end

	if keymaps.jump_to_primary then
		vim.keymap.set('n', keymaps.jump_to_primary, function()
			M.jump_to_primary()
		end, { desc = "Bring primary buffer to current" })
	end

	if keymaps.restore_ternary then
		vim.keymap.set('n', keymaps.restore_ternary, function()
			M.restore_ternary()
		end, { desc = "Restore ternary relationship" })
	end

	if keymaps.restore_secondary then
		vim.keymap.set('n', keymaps.restore_secondary, function()
			M.restore_secondary()
		end, { desc = "Restore secondary relationship" })
	end

	-- Cycling mode navigation
	if keymaps.cycle_left then
		vim.keymap.set('n', keymaps.cycle_left, function()
			M.cycle_left()
		end, { desc = "Cycle left during cycling mode" })
	end

	if keymaps.cycle_right then
		vim.keymap.set('n', keymaps.cycle_right, function()
			M.cycle_right()
		end, { desc = "Cycle right during cycling mode" })
	end

	if keymaps.cycle_select then
		vim.keymap.set('n', keymaps.cycle_select, function()
			M.cycle_select()
		end, { desc = "Select cycling buffer and attach history" })
	end

	if keymaps.toggle_window then
		vim.keymap.set('n', keymaps.toggle_window, function()
			M.toggle_window()
		end, { desc = "Toggle between current and previous window" })
	end

	if keymaps.set_primary then
		vim.keymap.set('n', keymaps.set_primary, function()
			M.set_primary()
		end, { desc = "Set current buffer as primary" })
	end

	-- Primary buffer management
	if keymaps.toggle_primary then
		vim.keymap.set('n', keymaps.toggle_primary, function()
			M.toggle_primary()
		end, { desc = "Toggle current buffer as primary" })
	end

	if keymaps.close_buffer then
		vim.keymap.set('n', keymaps.close_buffer, function()
			M.delete_buffer()
		end, { desc = "Toggle current buffer as primary" })
	end
end

---Initialize cavediver plugin with configuration
---@param user_config? CavediverConfig User configuration (merged with defaults)
function M.setup(user_config)
	-- Merge user configuration with defaults
	
	local function deep_merge_into(default, user_config)
		for key, value in pairs(user_config) do
			local type_value = type(value)
			local type_default = type(default[key])
			if type(value) == "table" and type(default[key]) == "table" then 
				deep_merge_into(default[key], value)
			elseif type_value ~= "table" and type_default ~= "table" then
				default[key] = value
			else
				error("Type mismatch for key '" .. key .. "': default is " .. type_default .. ", user config is " .. type_value)
			end
		end
	end

	deep_merge_into(settings, user_config)

	-- Store config for domain access
	M.config = settings
	
	ui.init_winbar_highlights()
	ui.init_refresh_timer()
	history.init_cleanup_timer()

	-- Setup keymaps
	setup_keymaps(settings.keymaps)

	-- Setup cleanup timer if configured
	if settings.cleanup_interval and settings.cleanup_interval > 0 then
		vim.fn.timer_start(settings.cleanup_interval * 1000, function()
			-- TODO: Implement buffer cleanup routine
		end, { ['repeat'] = -1 })
	end
end

---Setup debug commands for inspecting internal state
local function setup_debug_commands()
	-- Command 1: Print Current Window Triquetra
	vim.api.nvim_create_user_command("CavediverTriquetra", function()
		local winid = vim.api.nvim_get_current_win()
		local triquetra = window.get_triquetra(winid)

		if not triquetra then
			print("No triquetra data for window " .. winid)
			return
		end

		print("=== Window " .. winid .. " Triquetra ===")
		print("Current slot:    " .. (triquetra.current_slot or "nil"))
		print("Secondary slot:  " .. (triquetra.secondary_slot or "nil"))
		print("Ternary slot:    " .. (triquetra.ternary_slot or "nil"))
		print("Primary buffer:  " .. (triquetra.primary_buffer or "nil"))
		print("Primary enabled: " .. tostring(triquetra.primary_enabled or false))

		print("\n--- Displacement Maps ---")
		print("Secondary displacement map:")
		for k, v in pairs(triquetra.displacement_secondary_map or {}) do
			print("  " .. k .. " -> " .. v)
		end

		print("Ternary displacement map:")
		for k, v in pairs(triquetra.displacement_ternary_map or {}) do
			print("  " .. k .. " -> " .. v)
		end
	end, { desc = "Print current window triquetra relationships" })

	-- Command 2: Print Registry Mappings
	vim.api.nvim_create_user_command("CavediverRegistry", function()
		print("=== Hash-Buffer Registry ===")
		print("Hash -> Buffer mapping:")
		for hash, bufnr in pairs(history.data.hash_buffer_registry.buffers) do
			local valid = vim.api.nvim_buf_is_valid(bufnr) and "valid" or "invalid"
			print("  " .. hash .. " -> [" .. bufnr .. "] (" .. valid .. ")")
		end

		print("\nBuffer -> Hash mapping:")
		for bufnr, hash in pairs(history.data.hash_buffer_registry.hashes) do
			local valid = vim.api.nvim_buf_is_valid(bufnr) and "valid" or "invalid"
			print("  [" .. bufnr .. "] -> " .. hash .. " (" .. valid .. ")")
		end

		print("\n=== Hash-Filepath Registry ===")
		print("Hash -> Filepath mapping:")
		for hash, filepath in pairs(history.data.hash_filepath_registry.filepaths) do
			print("  " .. hash .. " -> " .. filepath)
		end

		print("\nFilepath -> Hash mapping:")
		for filepath, hash in pairs(history.data.hash_filepath_registry.hashes) do
			print("  " .. filepath .. " -> " .. hash)
		end

		print("\n=== Closed Buffers ===")
		for i, hash in ipairs(history.data.closed_buffers) do
			local filepath = history.get_filepath_from_hash(hash)
			print("  [" .. i .. "] " .. hash .. " -> " .. (filepath or "unknown"))
		end
	end, { desc = "Print hash-buffer and hash-filepath registry mappings" })

	-- Command 3: Enhanced Triquetra with Filenames
	vim.api.nvim_create_user_command("CavediverTriquetraVerbose", function()
		local winid = vim.api.nvim_get_current_win()
		local triquetra = window.get_triquetra(winid)

		if not triquetra then
			print("No triquetra data for window " .. winid)
			return
		end

		local function hash_to_info(hash)
			if not hash then return "nil" end
			local filepath = history.get_filepath_from_hash(hash)
			local bufnr = history.get_buffer_from_hash(hash)
			local basename = filepath and vim.fn.fnamemodify(filepath, ":t") or "unknown"
			local loaded = bufnr and vim.api.nvim_buf_is_valid(bufnr) and "loaded" or "closed"
			return hash .. " (" .. basename .. " - " .. loaded .. ")"
		end

		print("=== Window " .. winid .. " Triquetra (Verbose) ===")
		print("Current slot:    " .. hash_to_info(triquetra.current_slot))
		print("Secondary slot:  " .. hash_to_info(triquetra.secondary_slot))
		print("Ternary slot:    " .. hash_to_info(triquetra.ternary_slot))
		print("Primary buffer:  " .. hash_to_info(triquetra.primary_buffer))
		print("Primary enabled: " .. tostring(triquetra.primary_enabled or false))
	end, { desc = "Print current window triquetra with filenames" })

	-- Command 4: Print All Triquetra Objects
	vim.api.nvim_create_user_command("CavediverAllTriquetras", function()
		local function hash_to_info(hash)
			if not hash then return "nil" end
			local filepath = history.get_filepath_from_hash(hash)
			local bufnr = history.get_buffer_from_hash(hash)
			local basename = filepath and vim.fn.fnamemodify(filepath, ":t") or "unknown"
			local loaded = bufnr and vim.api.nvim_buf_is_valid(bufnr) and "loaded" or "closed"
			return hash .. " (" .. basename .. " - " .. loaded .. ")"
		end

		print("=== All Window Triquetras ===")

		-- Get all windows with triquetra data
		local windows_with_data = {}
		for winid, triquetra in pairs(window.data.crux) do
			windows_with_data[winid] = true
		end

		-- Also check UI cache for any additional windows
		for winid, _ in pairs(ui.data.window_display_cache) do
			windows_with_data[winid] = true
		end

		if vim.tbl_isempty(windows_with_data) then
			print("No triquetra data found for any windows")
			return
		end

		for winid, _ in pairs(windows_with_data) do
			local win_valid = vim.api.nvim_win_is_valid(winid)
			local triquetra = window.data.crux[winid]
			local ui_cache = ui.data.window_display_cache[winid]

			print("\n--- Window " .. winid .. " (" .. (win_valid and "valid" or "invalid") .. ") ---")

			if triquetra then
				print("Hash-based triquetra:")
				print("  Current slot:    " .. hash_to_info(triquetra.current_slot))
				print("  Secondary slot:  " .. hash_to_info(triquetra.secondary_slot))
				print("  Ternary slot:    " .. hash_to_info(triquetra.ternary_slot))
				print("  Primary buffer:  " .. hash_to_info(triquetra.primary_buffer))
				print("  Primary enabled: " .. tostring(triquetra.primary_enabled or false))

				-- Show displacement maps if they exist
				local has_secondary_displacement = triquetra.displacement_secondary_map and
					not vim.tbl_isempty(triquetra.displacement_secondary_map)
				local has_ternary_displacement = triquetra.displacement_ternary_map and
					not vim.tbl_isempty(triquetra.displacement_ternary_map)

				if has_secondary_displacement or has_ternary_displacement then
					print("  Displacement maps:")
					if has_secondary_displacement then
						print("    Secondary:")
						for from_hash, to_hash in pairs(triquetra.displacement_secondary_map) do
							print("      " .. hash_to_info(from_hash) .. " -> " .. hash_to_info(to_hash))
						end
					end
					if has_ternary_displacement then
						print("    Ternary:")
						for from_hash, to_hash in pairs(triquetra.displacement_ternary_map) do
							print("      " .. hash_to_info(from_hash) .. " -> " .. hash_to_info(to_hash))
						end
					end
				end
			else
				print("  No hash-based triquetra data")
			end

			if ui_cache then
				print("UI display cache:")
				print("  Current:   [" ..
					(ui_cache.current_bufnr or "nil") .. "] " .. (ui_cache.current_display_name or "nil"))
				print("  Secondary: [" ..
					(ui_cache.secondary_bufnr or "nil") ..
					"] " ..
					(ui_cache.secondary_display_name or "nil") ..
					" (has: " .. tostring(ui_cache.has_secondary or false) .. ")")
				print("  Ternary:   [" ..
					(ui_cache.ternary_bufnr or "nil") ..
					"] " ..
					(ui_cache.ternary_display_name or "nil") ..
					" (has: " .. tostring(ui_cache.has_ternary or false) .. ")")
				print("  Primary:   [" ..
					(ui_cache.primary_bufnr or "nil") ..
					"] " ..
					(ui_cache.primary_display_name or "nil") ..
					" (has: " .. tostring(ui_cache.has_primary or false) .. ")")

				if ui_cache.loaded_slots then
					print("  Loaded slots: secondary=" ..
						tostring(ui_cache.loaded_slots.secondary or false) ..
						", ternary=" .. tostring(ui_cache.loaded_slots.ternary or false))
				end
				if ui_cache.deleted_slots then
					print("  Deleted slots: secondary=" ..
						tostring(ui_cache.deleted_slots.secondary or false) ..
						", ternary=" .. tostring(ui_cache.deleted_slots.ternary or false))
				end
			else
				print("  No UI display cache")
			end
		end

		print("\n=== Summary ===")
		print("Total windows with triquetra data: " .. vim.tbl_count(windows_with_data))
		print("Hash-based triquetras: " .. vim.tbl_count(window.data.crux))
		print("UI display caches: " .. vim.tbl_count(ui.data.window_display_cache))
	end, { desc = "Print all window triquetra objects and UI caches" })
end

-- Setup debug commands
setup_debug_commands()

---API Exports - Direct access to domain functionality

-- Session management
M.save_session = storage.save_session
M.load_session = storage.load_session

-- Buffer lifecycle
M.reopen_last_closed = history.reopen_last_closed

-- Triquetra operations (to be implemented in window domain)
M.toggle_secondary = function()
	local winid = vim.api.nvim_get_current_win()
	window.swap_with_secondary(winid)
end

M.toggle_ternary = function()
	local winid = vim.api.nvim_get_current_win()
	window.swap_with_ternary(winid)
end

M.jump_to_primary = function()
	local winid = vim.api.nvim_get_current_win()
	window.jump_to_primary(winid)
end

M.restore_ternary = function()
	local winid = vim.api.nvim_get_current_win()
	window.restore_triquetra_ternary(winid)
end

M.restore_secondary = function()
	local winid = vim.api.nvim_get_current_win()
	window.restore_triquetra_secondary(winid)
end

-- Navigation operations (to be implemented in navigation domain)
M.cycle_left = navigation.cycle_left

M.cycle_right = navigation.cycle_right

M.toggle_window = navigation.toggle_window
M.cycle_select = navigation.select_buffer

-- Primary buffer management (to be implemented in window domain)
M.toggle_primary = function()
	local winid = vim.api.nvim_get_current_win()
	window.toggle_primary_buffer(winid)
end

M.delete_buffer = function()
	local winid = vim.api.nvim_get_current_win()
	history.delete_buffer(winid)
end

M.set_primary = function()
	local winid = vim.api.nvim_get_current_win()
	window.set_primary_buffer(winid)
end

M.get_storage_state = function()
	return storage.sm:state()
end

-- State machine access
M.get_navigation_state = function()
	return navigation.sm:state()
end

M.get_history_state = function()
	return history.sm:state()
end

M.is_cycling = function()
	local nav_states = require('domains.navigation.states')
	return navigation.sm:state() == nav_states.CYCLING
end

M.set_cache_from_window_triquetra = ui.set_cache_from_window_triquetra

-- Utility functions
M.get_buffer_history = history.get_buffer_history
M.get_window_triquetra = window.get_triquetra
M.get_smart_basename = ui.get_smart_basename
M.get_all_triquetras = window.get_window_relationships

M.bufferline = ui.bufferline
return M
