---UI state constants for visual component management.
---
---The UI domain manages the visual state of interface components using
---multiple independent state machines for different UI components.

---@class BufferlineStates
---@field VISIBLE "bufferline_visible" Bufferline is displayed and updated
---@field HIDDEN "bufferline_hidden" Bufferline is hidden during cycling/focus modes

---@class WinbarStates  
---@field ACTIVE "winbar_active" Window bars showing buffer relationships
---@field MINIMAL "winbar_minimal" Minimal window bar display

---@class IndicatorStates
---@field ON "indicators_on" Buffer status indicators are visible
---@field OFF "indicators_off" Buffer status indicators are hidden

---@class LoopStates
---@field UPDATING "updating" Continuous update loop state for UI refresh

local ui_states = {
    BUFFERLINE = {
        VISIBLE = "bufferline_visible",
        HIDDEN = "bufferline_hidden",
    },
    WINBAR = {
        ACTIVE = "winbar_active", 
        MINIMAL = "winbar_minimal",
    },
    INDICATORS = {
        ON = "indicators_on",
        OFF = "indicators_off",
    },
    LOOP = {
        SELF = "self",
    },
}

---@class UIModule
---@field state UIStates The UI state constants
return ui_states
