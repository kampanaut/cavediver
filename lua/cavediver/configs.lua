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
				fg = "#B7B5AC", -- base-300
				bg = "#151515", -- your bg
			},
			unfocused = {
				fg = "#575653", -- base-700
				bg = "#151515"
			},
		},
		current = {
			focused = {
				filename = "#879A39", -- green-400
				bufnr = "#879A39",
			},
			unfocused = {
				filename = "#575653",
				bufnr = "#575653",
			}
		},
		secondary = {
			focused = {
				filename = "#879A39",
				bufnr = "#DA702C" -- orange-400
			},
			unfocused = {
				filename = "#575653",
				bufnr = "#575653",
			},
		},
		ternary = {
			focused = {
				filename = "#9F9D96", -- base-400
				bufnr = "#9F9D96"
			},
			unfocused = {
				filename = "#575653",
				bufnr = "#575653",
			},
		},
		primary = {
			active = "#D0A215", -- yellow-400
			inactive = "#575653",
			unfocused = "#575653"
		},
		harpooned = {
			unfocused = {
				fg = "#8B7EC8", -- purple-400
			}
		},
		both_way_arrow = {
			focused = "#4385BE", -- blue-400
			unfocused = "#4385BE"
		},
		cokeline = {
			is_picking_close = "#D14D41", -- red-400
			is_picking_focus = "#D0A215", -- yellow-400
			bg = {
				detached = {
					focused = "#282726", -- base-900
					unfocused = "#100F0F", -- black
				},
				attached = "#151515"
			},
			fg = {
				focused = "#878580", -- base-500
				unfocused = "#6F6E69" -- base-600
			},
			diagnostics = {
				error = "#D14D41", -- red-400
				warning = "#D0A215", -- yellow-400
				info = "#3AA99F", -- cyan-400
				hint = "#879A39" -- green-400
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
	cleanup_interval = 4000,              -- seconds
	winbar_refresh_interval = 140         -- milliseconds
}

return defaults
