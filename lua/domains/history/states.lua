---History state constants for the cavediver history domain state machine.
---
---The history domain manages when buffer history tracking is active or suspended.
---History is typically detached during buffer cycling to prevent interference
---with the cycling process, then reattached when returning to normal navigation.

---@class HistoryModes
---@field DELETE "delete" The mode for deleting buffers, history will be detached
---@field UPDATE "update" The mode for updating history, typically when entering a buffer
---
---@class HistoryStates
---@field ATTACHED "attached" History tracking is active - buffer access times are recorded
---@field DETACHED "detached" History tracking is suspended - no updates during cycling
---@field mode HistoryModes
local states = {
	ATTACHED = "attached",
	DETACHED = "detached",
	mode = {
		DELETE = "delete",
		UPDATE = "update"
	}
}

return states
