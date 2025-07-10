---Navigation domain initialization, extension hooks, and API layer.
---
---The navigation domain manages buffer navigation modes and coordination context.
---This module provides the API layer and loads extension hooks that coordinate
---with other domains' state machines.

local states = require('cavediver.domains.navigation.states')
local data = require('cavediver.domains.navigation.data')
local routines = require('cavediver.domains.navigation.routines')

-- Load hooks to coordinate with other domains' state machines
require('cavediver.domains.navigation.hooks')

-- Get navigation state machine for domain coordination
local NavigationSM = require('cavediver.domains.navigation.sm')

local M = {
    sm = NavigationSM,      -- The navigation state machine
    states = states,        -- State constants
    data = data,            -- Domain data structures
    routines = routines,    -- Domain business logic
}

---Get current navigation mode.
---
---@return string mode Current navigation mode ("normal", "cycling", "file_picker")
function M.get_mode()
    return NavigationSM:state()
end

---Check if currently in cycling mode.
---
---@return boolean cycling True if in cycling mode
function M.is_cycling()
    return NavigationSM:state() == states.CYCLING
end

---Check if currently in file picker mode.
---
---@return boolean file_picker True if in file picker mode
function M.is_file_picker()
    return NavigationSM:state() == states.FILE_PICKER
end

---Check if currently in normal mode.
---
---@return boolean normal True if in normal mode
function M.is_normal()
    return NavigationSM:state() == states.NORMAL
end

function M.cycle_left()
	NavigationSM:to(states.CYCLING, {
		direction = 1,
		window = {
			current_crux = vim.api.nvim_get_current_win()
		}
	}, states.mode.CYCLE)
end

function M.cycle_right()
	NavigationSM:to(states.CYCLING, {
		direction = 2,
		window = {
			current_crux = vim.api.nvim_get_current_win()
		}
	}, states.mode.CYCLE)
end

function M.select_buffer()
	NavigationSM:to(states.NORMAL, {
		history = {
			cbufnr = vim.api.nvim_get_current_buf()
		}
	}, states.mode.CYCLE)
end

M.toggle_window = routines.toggle_window

return M
