---History domain initialization, extension hooks, and API layer.
---
---The history domain manages global buffer access history and tracking state.
---This module provides the API layer and loads extension hooks that integrate
---with other domains' state machines.

local states = require('cavediver.domains.history.states')
local data = require('cavediver.domains.history.data')
local routines = require('cavediver.domains.history.routines')

local configs = require('cavediver.configs')

-- Load hooks to extend other domains' state machines
require('cavediver.domains.history.hooks')

-- Get history state machine for domain coordination
local HistorySM = require('cavediver.domains.history.sm')

local M = {
	sm = HistorySM,      -- The history state machine
	states = states,     -- State constants
	data = data,         -- Domain data structures
	routines = routines, -- Domain business logic (sync functions)
}

M.register_buffer = routines.register_buffer

M.register_filepath = routines.register_filepath

M.track_buffer = routines.track_buffer

M.reopen_last_closed = routines.reopen_last_closed

---Initiate the history cleanup timer.
---@return nil
function M.init_cleanup_timer()
	local cleanup_timer = vim.loop:new_timer()
	if cleanup_timer then
		cleanup_timer:start(0, configs.cleanup_interval, vim.schedule_wrap(function()
			local report = routines.cleanup_system()

			-- Only notify about significant cleanup
			local total_cleaned = report.orphaned_history + report.invalid_closed_buffers + report.stale_hash_entries
			if total_cleaned > 0 then
				local output = { "CAVEDIVER CLEANUP REPORT:" }
				table.insert(output, string.format("  Total cleaned: %d", total_cleaned))
				
				if #report.orphaned_hashes > 0 then
					table.insert(output, "  Orphaned files:")
					for _, hash in ipairs(report.orphaned_hashes) do
						local path = data.hash_filepath_registry.filepaths[hash] or hash
						table.insert(output, "    - " .. path)
					end
				end
				
				if #report.invalid_closed_hashes > 0 then
					table.insert(output, "  Invalid closed files:")
					for _, hash in ipairs(report.invalid_closed_hashes) do
						local path = data.hash_filepath_registry.filepaths[hash] or hash
						table.insert(output, "    - " .. path)
					end
				end
				
				if #report.stale_hashes > 0 then
					table.insert(output, "  Stale files:")
					for _, hash in ipairs(report.stale_hashes) do
						local path = data.hash_filepath_registry.filepaths[hash] or hash
						table.insert(output, "    - " .. path)
					end
				end
				
				vim.notify(table.concat(output, "\n"), vim.log.levels.INFO)
			end
		end))
	end
end

---Check if history tracking is currently detached.
---
---@return boolean detached True if history tracking is detached
function M.is_detached()
	return HistorySM:state() == states.DETACHED
end

---Get current buffer access history.
---
---@return table<string, number> history File hash to access time mapping
function M.get_buffer_history()
	return data.crux
end

---Get the stack of closed buffer filenames.
---
---@return string[] closed_buffers Array of closed buffer filenames that can be reopened
function M.get_closed_buffers()
	return data.closed_buffers
end

---Get ordered buffer list by recency.
---
---@param include_harpooned boolean|nil Whether to include harpooned buffers
---@return BufferHistoryItem[] ordered Buffers ordered by recency
function M.get_ordered_buffers(include_harpooned)
	if include_harpooned == false then
		return data.ordered.nonharpooned
	else
		return data.ordered.crux
	end
end

M.get_buffer_from_hash = routines.get_buffer_from_hash
M.get_hash_from_buffer = routines.get_hash_from_buffer
M.get_filepath_from_hash = routines.get_filepath_from_hash
M.get_filepath_from_buffer = routines.get_filepath_from_buffer
M.get_hash_from_filepath = routines.get_hash_from_filepath

M.repopulate_history = routines.repopulate_history

---@param filehash Filehash
---@return boolean True if the filehash is registered as closed
function M.filehash_is_closed(filehash)
	return vim.tbl_contains(data.closed_buffers, filehash)
end

function M.clear_closed_buffers()
	data.closed_buffers = {}
end

M.reopen_filehash = routines.reopen_filehash

---Get the triquetra (window snapshot) for a specific window.
---@param winid WinId
---@return WindowTriquetra
function M.get_cycling_origins(winid)
	return data.cycling_origins[winid] or nil
end

M.delete_buffer = routines.delete_buffer

-- Cleanup functions
M.cleanup_system = routines.cleanup_system

return M
