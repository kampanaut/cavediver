# Cavediver

## Introduction

This is a navigation plugin. Have you ever jumped so many times, jumping to definitions, across files, and then suddenly you just felt lost? Well... this plugin 
helps you visualise it more easier for yah.

## Requirements

- resession.nvim
- nvim-cokeline
- harpoon (harpoon feature still coupled with the plugin, working on togglable option)

## Installation

This works for all plugin managers.

### lazy.nvim (An example)

```lua
	{
		"kampanaut/cavediver",
		-- dir = "~/Projects/nvim/cavediver",
		config = true

        dependencies = {
			"ThePrimeagen/harpoon",
            -- resession.nvim and nvim-cokeline, requires this plugin.
      }
	}
```

### Resession.nvim setup

You have to add a hook for the session manager, to allow this plugin to have persistence. 
This cavediver plugin saves the session state in your neovim's `data` directory by default.

```lua
{
    "stevearc/resession.nvim",
    lazy = false,
    config = function()
        local resession = require("resession")
        resession.setup( {
            -- your configurations....
        })
        resession.add_hook("pre_save", function()
            require('cavediver').save_session(vim.loop.cwd())
        end)

        resession.add_hook("post_load", function()
            require('cavediver').load_session(vim.loop.cwd())
        end)
    end,
    depenedencies = {
        "kampanaut/cavediver"
    }
},
}
```

### nvim-cokeline setup

The cavediver plugin can work without the bufferline, but it would be nice to visualise the 
visit history of all your browsers in a bufferline, so that you can now how you can end up 
to your current buffer.

```lua 
{
    "willothy/nvim-cokeline",
    config = function()
        -- update_bufferline_state()

        require('cokeline').setup({
            show_if_buffers_are_at_least = 2,
            fill_hl = 'Normal',
            buffers = {
                -- A function to filter out unwanted buffers. Takes a buffer table as a
                -- parameter (see the following section for more infos) and has to return
                -- either `true` or `false`.
                -- default: `false`.
                ---@type false | fun(buf: Buffer):boolean
                filter_valid = function(buffer)
                    return require('cavediver').bufferline.bufnr_is_displayed(buffer.number)
                end,

                -- A looser version of `filter_valid`, use this function if you still
                -- want the `cokeline-{switch,focus}-{prev,next}` mappings to work for
                -- these buffers without displaying them in your bufferline.
                -- default: `false`.
                ---@type false | fun(buf: Buffer):boolean
                filter_visible = false,

                -- Which buffer to focus when a buffer is deleted, `prev` focuses the
                -- buffer to the left of the deleted one while `next` focuses the one the
                -- right.
                -- default: 'next'.
                focus_on_delete = 'prev',

                -- If set to `last` new buffers are added to the end of the bufferline,
                -- if `next` they are added next to the current buffer.
                -- if set to `directory` buffers are sorted by their full path.
                -- if set to `number` buffers are sorted by bufnr, as in default Neovim
                -- default: 'last'.
                ---@type 'last' | 'next' | 'directory' | 'number' | fun(a: Buffer, b: Buffer):boolean
                new_buffers_position = function(buffer_a, buffer_b)
                    local compare = require('cavediver').bufferline.compare_buffers(buffer_a.number, buffer_b.number)
                    return compare
                end,

                -- If true, right clicking a buffer will close it
                -- The close button will still work normally
                -- Default: true
                ---@type boolean
                delete_on_right_click = true,
            },
            mappings = {
                disable_mouse = false,
                cycle_prev_next = true
            },
            pick = {
                use_filename = false,
                letters = "jfkdlsa;bvncmurieowpqyt"
            },
            default_hl = {
                bg = function(buffer)
                    return require('cavediver').bufferline.get_theme_bg_color(buffer.is_focused)
                end,
                fg = function(buffer)
                    return require('cavediver').bufferline.get_theme_fg_color(buffer.number, buffer.is_focused)
                end,
                bold = function(buffer)
                    return require('cavediver').bufferline.get_buffer_bold(buffer.number)
                end,
            },
            history = {
                enabled = false,
            },
            tabs = {
                placement = "right",
                components = require('cavediver').bufferline.cokeline.create_tab_components()
                
            },
            components = require('cavediver').bufferline.cokeline.create_buffer_components()
        })
    end
    dependencies = {
        "nvim-lua/plenary.nvim", -- Required for v0.4.0+
        "nvim-tree/nvim-web-devicons", -- If you want devicons
        "stevearc/resession.nvim", -- Optional, for persistent history
        "kampanaut/cavediver"
    },
}
```

## Configuration Defaults

You can make your own theme as well, make your own color markers for each buffer type.

You can start by just modifying the base colors

```lua
local defaults = {
	session_dir = vim.fn.stdpath("data") .. "/cavediver/sessions/",
	bufferline = {
		history_view = "global" -- "global" | "window"
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
		toggle_primary = "<M-;><M-c>", -- Toggle current buffer as primary
		set_primary = "<M-;><M-x>",
		close_buffer = "<M-.>",
	},
	cleanup_interval = 8000,    -- seconds
	winbar_refresh_interval = 140 -- milliseconds
}
```

## How to use

### Window Triquetras

For each window that is trackable 
