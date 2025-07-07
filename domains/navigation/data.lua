local states = require('domains.navigation.states')
---@alias Tabnr number

---Navigation domain data structures and state management.
---
---@class NavigationState Navigation coordination state
---@field current_mode string Current navigation mode for coordination context
---@field state_transition_history string[] History of navigation transitions
---@field window_jump_history table<Tabnr, table<WinId, WinId>> Per-tab, current window -> previous window mapping

-- Current coordination mode for other domains to reference
local current_mode = states.NORMAL

-- History of navigation state transitions for debugging
local transition_history = {}

---Add transition to history log.
---
---@param from string Source state
---@param to string Destination state
---@return nil
local function log_transition(from, to)
    table.insert(transition_history, from .. "->" .. to)
    
    -- Keep only last 10 transitions
    if #transition_history > 10 then
        table.remove(transition_history, 1)
    end
end

---Clear transition history.
---
---@return nil
local function clear_history()
    transition_history = {}
end

return {
    current_mode = current_mode,
    transition_history = transition_history,
	window_jump_history = {},
    log_transition = log_transition,
    clear_history = clear_history,
}
