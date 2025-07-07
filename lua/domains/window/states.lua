---Window state constants for per-window buffer relationship tracking.
---
---The window domain manages buffer relationships within individual windows.
---Each window maintains its own triquetra (three-way) buffer relationships
---independent of other windows and global history.
---
---@class WindowStates  
---@field SHOWING_PRIMARY "showing_primary" Displaying the user-designated main buffer
---@field SHOWING_SECONDARY "showing_secondary" Displaying the most recent previous buffer
---@field SHOWING_TERNARY "showing_ternary" Displaying the third buffer in rotation
---@field SHOWING_OTHER "showing_other" Displaying a buffer outside the triquetra relationship

local window_states = {
    SHOWING_PRIMARY = "showing_primary",
    SHOWING_SECONDARY = "showing_secondary",
    SHOWING_TERNARY = "showing_ternary",
    SHOWING_OTHER = "showing_other",
}

---@class WindowModule
---@field state WindowStates The window state constants
return window_states
