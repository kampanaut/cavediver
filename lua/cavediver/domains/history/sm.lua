---History domain state machine creation and configuration.
---
---This module creates and configures the history state machine with all
---necessary states and transitions for global buffer history tracking.

local historySM
local states = require('cavediver.domains.history.states')

-- Try to get existing history state machine
historySM = require('cavediver.engine'):get("history")

if historySM ~= nil then
	return historySM
end

-- Create new history state machine if none exists
historySM = require('cavediver.engine'):create("history")

-- Register all history states
historySM:register_state(states.ATTACHED)
historySM:register_state(states.DETACHED)

-- Set initial state
historySM.current_state = states.ATTACHED

historySM:register_mode(states.mode.DELETE)
historySM:register_mode(states.mode.UPDATE)

return historySM
