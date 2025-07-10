-- Navigation state constants for the cavediver state machine system.
---
-- The navigation state machine provides the root context that determines all system behavior.
-- All other state machines (window, domain-specific) extend this navigation context.
---@class NavigationStates
---@field NORMAL "normal" Standard navigation mode with history tracking enabled
---@field CYCLING "cycling" Cycling mode with history detached for buffer browsing
---@field FILE_PICKER "file_picker" File picker mode where explorer controls navigation
local navigation_state = {
	NORMAL = "normal",
	CYCLING = "cycling",
	FILE_PICKER = "file_picker",
	mode = {
		CYCLE = "cycle",       -- Mode for cycling through buffers, history detached
		WINENTER = "winenter"  -- Mode for entering a window, typically reattaching history
	}
}

---@class NavigationModule
---@field state NavigationStates The navigation state constants
return navigation_state

