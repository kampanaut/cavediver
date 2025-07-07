---Window domain initialization and state machine creation.
---
---The window domain manages per-window buffer relationships (triquetra).
---Unlike other domains, it doesn't create its own state machine but extends
---the history state machine with window-specific hooks.

local states = require('cavediver.domains.window.states')
local data = require('cavediver.domains.window.data')
local routines = require('cavediver.domains.window.routines')

-- Load hooks to extend the history state machine
require('cavediver.domains.window.hooks')

-- The window domain extends the history state machine rather than creating its own
-- This is because window buffer relationships are tightly coupled to history attach/detach cycles

local M = {
    states = states,
    data = data,
    routines = routines,
}

---Get current window buffer relationships.
---
---@param winid number|nil Window ID (defaults to current window)
---@return WindowTriquetra|nil relationships The window's triquetra relationships
function M.get_triquetra(winid)
    winid = winid or vim.api.nvim_get_current_win()
    return data.get_window_triquetra(winid)
end

---Clean up window data when a window is closed.
---
---@param winid number Window ID that was closed
function M.cleanup_window(winid)
    data.crux[winid] = nil
end

---Set a window's buffer relationship from a complete relationship table.
---
---Validates and sets the buffer relationship data for a window.
---
---@param winid number Window ID to set relationships for
---@param relationship_table WindowTriquetra Complete relationship data
---@return boolean success True if relationships were set successfully
function M.set_buffer_relationship(winid, relationship_table)
    -- Validate window exists
    if not winid or not vim.api.nvim_win_is_valid(winid) then
        return false
    end

    -- Validate relationship table
    if not relationship_table or type(relationship_table) ~= "table" then
        return false
    end

    -- Set the relationship data
    data.crux[winid] = {
		current_slot = relationship_table.current_slot,
		secondary_slot = relationship_table.secondary_slot,
		ternary_slot = relationship_table.ternary_slot,
		primary_buffer = relationship_table.primary_buffer,
		displacement_secondary_map = relationship_table.displacement_secondary_map,
		displacement_ternary_map = relationship_table.displacement_ternary_map,
		primary_enabled = relationship_table.primary_buffer ~= nil
    }

	-- print_table(data.crux)

    return true
end

---Get all window buffer relationships.
---
---@return table<number, WindowTriquetra> relationships Window ID to buffer relationships mapping
function M.get_window_relationships()
	return data.crux
end

M.swap_with_secondary = routines.swap_with_secondary
M.swap_with_ternary = routines.swap_with_ternary
M.jump_to_primary = routines.jump_to_primary
M.toggle_primary_buffer = routines.toggle_primary_buffer
M.set_primary_buffer = routines.set_primary_buffer
M.restore_triquetra_secondary = routines.restore_triquetra_secondary
M.restore_triquetra_ternary = routines.restore_triquetra_ternary

M.reconcile_triquetra = routines.reconcile_triquetra

M.repopulate_window_relationships = routines.repopulate_window_relationships

-- TODO: Add window autocmds for automatic cleanup
-- vim.api.nvim_create_autocmd("WinClosed", {
--     callback = function(args)
--         M.cleanup_window(tonumber(args.file))
--     end,
-- })

return M
