---UI domain state machine creation and configuration.
---
---This module creates and configures multiple independent state machines
---for different UI components (bufferline, winbar, indicators, loop).

local states = require('cavediver.domains.ui.states')
local SMFactory = require('cavediver.engine')

-- Create or get multiple independent UI state machines
local bufferlineSM = SMFactory:get("ui_bufferline") or SMFactory:create("ui_bufferline")
local indicatorsSM = SMFactory:get("ui_indicators") or SMFactory:create("ui_indicators")
local loopSM = SMFactory:get("ui_loop") or SMFactory:create("ui_loop")

-- Register bufferline states
bufferlineSM:register_state(states.BUFFERLINE.VISIBLE)
bufferlineSM:register_state(states.BUFFERLINE.HIDDEN)
bufferlineSM.current_state = states.BUFFERLINE.VISIBLE

-- Register indicators states
indicatorsSM:register_state(states.INDICATORS.ON)
indicatorsSM:register_state(states.INDICATORS.OFF)
indicatorsSM.current_state = states.INDICATORS.ON

-- Register loop state (single state that transitions to itself)
loopSM:register_state(states.LOOP.SELF)
loopSM.current_state = states.LOOP.SELF

-- Configure loop self-transition for UI updates
loopSM:on(states.LOOP.SELF, states.LOOP.SELF, "update_ui", function(context, from, to)
    -- TODO: Call update_bufferline_state() here
    -- This will be filled in by user
end, 1, true)

return {
    bufferline = bufferlineSM,
    indicators = indicatorsSM,
    loop = loopSM,
}
