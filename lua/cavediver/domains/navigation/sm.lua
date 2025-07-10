---Navigation domain state machine creation and configuration.
---
---This module creates and configures the navigation state machine with all
---necessary states and transitions for buffer navigation coordination.

local states = require("cavediver.domains.navigation.states")
local SMFactory = require('cavediver.engine')

local NavigationSM

-- Try to get existing navigation state machine
NavigationSM = SMFactory:get("navigation")

if NavigationSM ~= nil then
	return NavigationSM
end

-- Create new navigation state machine if none exists
NavigationSM = SMFactory:create("navigation")

-- Register all navigation states
NavigationSM:register_state(states.NORMAL)
NavigationSM:register_state(states.CYCLING)
NavigationSM:register_state(states.FILE_PICKER)

-- Set initial state
NavigationSM.current_state = states.NORMAL

NavigationSM:register_mode(states.mode.CYCLE)
NavigationSM:register_mode(states.mode.WINENTER)

return NavigationSM
