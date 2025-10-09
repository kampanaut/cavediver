---@alias HexColor string

---UI domain data structures for visual component state management.
---
---@class UIState Visual interface component state
---@field bufferline_state BufferlineCache Pre-computed data for bufferline performance
---@field hidden_components table<string, boolean> Which UI components are currently hidden
---@field display_settings UIDisplaySettings Current visual display configuration

---@class BufferlineCache Pre-computed buffer state for performance optimization
---@field harpooned_buffers table<number, boolean> Buffer number to harpoon status mapping
---@field harpooned_lookup table<string|number, number> Path/buffer to harpoon position mapping  
---@field recent_buffers table<number, boolean> Buffer number to recent status mapping
---@field buffer_ranking table<number, number> Buffer number to ranking/access time mapping
---@field current_buf number|nil Currently active buffer number
---@field current_window_triquetra UIWindowTriquetra|nil Current window's buffer relationships for display
---@field initialized boolean Whether the cache has been populated
---@field history_detached boolean Whether history tracking is detached (affects display)

---@class SlotMasks
---@field secondary boolean Whether secondary slot is on or off
---@field ternary boolean Whether ternary slot is on or off

---@class UIWindowTriquetra Display-optimized window buffer relationships
---@field winid number Window ID
---@field current_bufnr number|nil Current buffer number (resolved from hash)
---@field current_display_name string|nil Current buffer display name
---@field secondary_bufnr number|nil Secondary buffer number (resolved from hash)
---@field secondary_display_name string|nil Secondary buffer display name
---@field ternary_bufnr number|nil Ternary buffer number (resolved from hash)
---@field ternary_display_name string|nil Ternary buffer display name
---@field primary_bufnr number|nil Primary buffer number (resolved from hash)
---@field primary_display_name string|nil Primary buffer display name
---@field has_secondary boolean Whether secondary slot is populated
---@field has_ternary boolean Whether ternary slot is populated
---@field has_primary boolean Whether primary buffer is set
---@field loaded_slots SlotMasks Which slots reference valid buffers
---@field deleted_slots SlotMasks Which slots reference deleted files

---@class UITriquetraTheme Triquetra theme configuration
---@field base "WinbarBase"|"WinbarBaseNC" Base highlight group for active/inactive winbar
---@field both_way_arrow "BothWayNerdArrow"|"BothWayNerdArrowNC"|"WinbarBase"
---@field current_slot_filename "WinbarBase"|"WinbarBaseNC"|"WinbarFilenameCurrent"|"WinbarFilenameCurrentNC"
---@field secondary_slot_filename "WinbarBase"|"WinbarFilenameSecondary"|"WinbarFilenameSecondaryNC"
---@field ternary_slot_filename "WinbarBase"|"WinbarFilenameTernary"|"WinbarFilenameTernaryNC"
---@field primary_bufnr "WinbarBase"|"WinbarBufnrPrimary"|"WinbarBufnrPrimaryNC"|"WinbarBufnrPrimaryDisabled"
---@field current_slot_bufnr "WinbarBase"|"WinbarBaseNC"|"WinbarBufnrCurrent"|"WinbarBufnrCurrentNC"|"WinbarBufnrPrimary"|"WinbarBufnrPrimaryNC"|"WinbarBufnrPrimaryDisabled"
---@field secondary_slot_bufnr "WinbarBase"|"WinbarBufnrSecondary"|"WinbarBufnrSecondaryNC"|"WinbarBufnrPrimary"|"WinbarBufnrPrimaryNC"|"WinbarBufnrPrimaryDisabled"
---@field ternary_slot_bufnr "WinbarBase"|"WinbarBufnrTernary"|"WinbarBufnrTernaryNC"|"WinbarBufnrPrimary"|"WinbarBufnrPrimaryNC"|"WinbarBufnrPrimaryDisabled"

---@class UIDisplaySettings Current UI component display configuration
---@field bufferline_enabled boolean Whether bufferline should be shown
---@field winbar_enabled boolean Whether winbars should be shown
---@field indicators_enabled boolean Whether buffer indicators should be shown

local M = {}

-- Pre-computed bufferline state for performance (migrated from buffers.lua)
---@type BufferlineCache
local bufferline_state = {
    harpooned_buffers = {},
    harpooned_lookup = {},
    recent_buffers = {},
    buffer_ranking = {},
    current_buf = nil,
    current_window_triquetra = nil,
    initialized = false,
    history_detached = false,
}

---@type table<string, UITriquetraTheme>
local winbar_themes = {
	focused = {
		base = "WinbarBase",
		both_way_arrow = "BothWayNerdArrow",
		primary_bufnr = "WinbarBufnrPrimary",
		current_slot_filename = "WinbarFilenameCurrent",
		secondary_slot_filename = "WinbarFilenameSecondary",
		ternary_slot_filename = "WinbarFilenameTernary",
		current_slot_bufnr = "WinbarBufnrCurrent",
		secondary_slot_bufnr = "WinbarBufnrSecondary",
		ternary_slot_bufnr = "WinbarBufnrTernary"
	},
	unfocused = {
		base = "WinbarBaseNC",
		both_way_arrow = "BothWayNerdArrowNC",
		primary_bufnr = "WinbarBufnrPrimaryNC",
		current_slot_filename = "WinbarFilenameCurrentNC",
		secondary_slot_filename = "WinbarFilenameSecondaryNC",
		ternary_slot_filename = "WinbarFilenameTernaryNC",
		current_slot_bufnr = "WinbarBufnrCurrentNC",
		secondary_slot_bufnr = "WinbarBufnrSecondaryNC",
		ternary_slot_bufnr = "WinbarBufnrTernaryNC"
	},
	topwin_overlapped = {
		base = "WinbarBase",
		both_way_arrow = "WinbarBase",
		primary_bufnr = "WinbarBase",
		current_slot_filename = "WinbarBase",
		secondary_slot_filename = "WinbarBase",
		ternary_slot_filename = "WinbarBase",
		current_slot_bufnr = "WinbarBase",
		secondary_slot_bufnr = "WinbarBase",
		ternary_slot_bufnr = "WinbarBase"
	}
}

-- Per-window display cache for UI-optimized triquetra data
---@type table<WinId, UIWindowTriquetra>
local window_display_cache = {}

-- Component visibility state
local hidden_components = {
    bufferline = false,
    winbar = false,
    indicators = false,
}

-- Display configuration
local display_settings = {
    bufferline_enabled = true,
    winbar_enabled = true, 
    indicators_enabled = true,
}

---@type string[]
local excluded_filetypes = {
	"neo-tree-popup",
	"neo-tree",
	"notify",
	"neominimap",
	"Avante",
	"AvanteInput",
	"dropbar_menu",
	"dropbar_menu_fzf",
	"DressingInput",
	"cmp_docs",
	"cmp_menu",
	"noice",
	"prompt",
	"TelescopePrompt",
	"blink_menu",
	"blink_docs",
}

-- Simple basename display cache - cleared on buffer changes
---@type table<Filehash, Filepath>
local display_name_cache = {}

---Reset bufferline cache to empty state.
---
---@return nil
function M.clear_bufferline_cache()
    bufferline_state = {
        harpooned_buffers = {},
        harpooned_lookup = {},
        recent_buffers = {},
        buffer_ranking = {},
        current_buf = nil,
        current_window_triquetra = nil,
        initialized = false,
        history_detached = false,
    }
end

---Check if a UI component is currently hidden.
---
---@param component string Component name ("bufferline", "winbar", "indicators")
---@return boolean hidden True if component is hidden
function M.is_component_hidden(component)
    return hidden_components[component] or false
end

---Set the visibility state of a UI component.
---
---@param component string Component name ("bufferline", "winbar", "indicators")  
---@param hidden boolean Whether the component should be hidden
---@return nil
function M.set_component_visibility(component, hidden)
    hidden_components[component] = hidden
end

---Clear the display name cache (called on buffer changes).
---
---@return nil
function M.clear_display_name_cache()
    M.display_name_cache = {}
end

---Get or create empty UI window triquetra for a window.
---
---@param winid number Window ID
---@return UIWindowTriquetra triquetra Empty triquetra structure
function M.get_or_create_window_display_cache(winid)
    if not window_display_cache[winid] then
        window_display_cache[winid] = {
            winid = winid,
            current_bufnr = nil,
            current_display_name = nil,
            secondary_bufnr = nil,
            secondary_display_name = nil,
            ternary_bufnr = nil,
            ternary_display_name = nil,
            primary_bufnr = nil,
            primary_display_name = nil,
            has_secondary = false,
            has_ternary = false,
            has_primary = false,
            loaded_slots = {
                secondary = false,
                ternary = false,
            },
			deleted_slots = {
				secondary = false,
				ternary = false,
			}
        }
    end
    return window_display_cache[winid]
end

---Clear window display cache for a specific window.
---
---@param winid number Window ID to clear cache for
---@return nil
function M.clear_window_display_cache(winid)
    window_display_cache[winid] = nil
end

M.bufferline_state = bufferline_state

M.hidden_components = hidden_components

M.display_settings = display_settings

M.display_name_cache = display_name_cache

M.window_display_cache = window_display_cache

M.winbar_themes = winbar_themes

M.excluded_filetypes = excluded_filetypes

return M
