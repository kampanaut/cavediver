---Window domain state machine creation and configuration.
---
---This module creates and configures the window state machine with all
---necessary states and transitions for per-window buffer relationship tracking.

local windowSM
local states = require('domains.window.states')

-- Try to get existing window state machine
windowSM = require('engine'):get("window")

if windowSM ~= nil then
	return windowSM
end

-- Create new window state machine if none exists
windowSM = require('engine'):create("window")

-- Register all window states
windowSM:register_state(states.SHOWING_PRIMARY)
windowSM:register_state(states.SHOWING_SECONDARY)
windowSM:register_state(states.SHOWING_TERNARY)
windowSM:register_state(states.SHOWING_OTHER)

-- Set initial state
windowSM.current_state = states.SHOWING_PRIMARY

return windowSM
