---@class CavediverKeymaps
---@field reopen_last_closed string Reopen last closed buffer
---@field toggle_secondary string Current ↔ Secondary toggle
---@field toggle_ternary string Current ↔ Ternary toggle
---@field jump_to_primary string Bring primary to current
---@field restore_ternary string Restore ternary relationship
---@field restore_secondary string Restore secondary relationship
---@field cycle_left string Cycle left during cycling mode
---@field cycle_right string Cycle right during cycling mode
---@field cycle_select string Toggle current buffer as primary
---@field toggle_primary string Toggle current buffer as primary
---@field set_primary string Set current buffer as primary
---@field close_buffer string Unregister and delete current buffer
---@field toggle_window string Jump between previous windows
---@field open_primary_buffer_history string Open primary buffer history window


---Default configuration
---@class CavediverConfig
local defaults = {
	session_dir = vim.fn.stdpath("data") .. "/cavediver/sessions/",
	bufferline = {
		history_view = "global" -- "global" | "window"
	},
	primary_buffer_history_popup = {
		height = 0.2, -- can be a ratio or a whole number
		width = 0.7, -- can be a ratio or a whole number
	},
	colors = {
		base = {
			focused = {
				fg = "#D5C4A1",
				bg = "#151515",
			},
			unfocused = {
				fg = "#504945",
				bg = "#151515"
			},
		},
		current = {
			focused = {
				filename = "#A9B665",
				bufnr = "#A9B665",
			},
			unfocused = {
				filename = "#504945",
				bufnr = "#504945",
			}
		},
		secondary = {
			focused = {
				filename = "#A9B665",
				bufnr = "#D8A657"
			},
			unfocused = {
				filename = "#504945",
				bufnr = "#504945",
			},
		},
		ternary = {
			focused = {
				filename = "#8d965e",
				bufnr = "#8d965e"
			},
			unfocused = {
				filename = "#504945",
				bufnr = "#504945",
			},
		},
		primary = {
			active = "#FFAF00",
			inactive = "#504945",
			unfocused = "#504945"
		},
		harpooned = {
			unfocused = {
				fg = "#5d6699",
			}
		},
		both_way_arrow = {
			focused = "#5F87AF",
			unfocused = "#5F87AF"
		},
		cokeline = {
			is_picking_close = "#a05959",
			is_picking_focus = "#d7d7a5",
			bg = {
				detached = {
					focused = "#2B2A33",
					unfocused = "#020202",
				},
				attached = "#151515"
			},
			fg = {
				focused = "#988E75",
				unfocused = "#6c6c6c"
			},
			diagnostics = {
				error = "#b75956",
				warning = "#d6ae40",
				info = "#b9eae9",
				hint = "#a1e276"
			}
		}
	},
	keymaps = {
		-- Buffer lifecycle
		reopen_last_closed = "<M-S-w>",

		-- Core triquetra operations
		toggle_secondary = "<M-f>", -- Current ↔ Secondary toggle
		toggle_ternary = "<M-S-f>", -- Current ↔ Ternary toggle
		jump_to_primary = "<M-;><M-f>", -- Bring primary to current
		restore_ternary = "<M-;><M-r>", -- Restore ternary relationship
		restore_secondary = "<M-;><M-t>", -- Restore secondary relationship

		-- Window navigation
		toggle_window = "<M-,>", -- Toggle between current and previous window

		-- Cycling mode navigation
		cycle_left = "<M-n>", -- During cycling mode
		cycle_right = "<M-m>", -- During cycling mode
		cycle_select = "<M-v>", -- Quit cycling mode and attach history with cycling buffer

		-- Primary buffer management
		toggle_primary = "<M-;><M-x>", -- Toggle current buffer as primary
		set_primary = "<M-;><M-c>",
		close_buffer = "<M-.>",

		open_primary_buffer_history = "<M-;>F", -- Open primary buffer history
	},
	cleanup_interval = 4000,    -- seconds
	winbar_refresh_interval = 140 -- milliseconds
}

return defaults
