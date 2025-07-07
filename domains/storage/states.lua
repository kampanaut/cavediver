---Storage state constants for session data management.
---
---The storage domain manages saving and loading of complete system state
---across all domains. It handles session persistence, auto-save functionality,
---and data serialization/deserialization.
---
---@class StorageStates
---@field IDLE "idle" Storage system is ready for operations
---@field SAVING "saving" Currently saving session data to disk
---@field LOADING "loading" Currently loading session data from disk
---@field ERROR "error" Storage operation failed, system in error state
---@field AUTO_SAVING "auto_saving" Background auto-save operation in progress
---@field BARE "bare" Uninitialized storage state, no data loaded
local storage_states = {
    IDLE = "idle",
    SAVING = "saving",
    LOADING = "loading",
    ERROR = "error",
    AUTO_SAVING = "auto_saving",
	BARE = "bare"
}

---@class StorageModule
---@field state StorageStates The storage state constants
return storage_states
