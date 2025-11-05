# Cavediver

## Introduction

This is a **navigation context manager system**. Let me explain what that is: have you ever felt lost after unconsciously jumping to files trying to get around the codebase just because you forgot to be conscious about it? Like some jumps earlier you should have remembered your current filename, but you were too busy thinking about the problem at hand not the filename itself. And also sometimes you don't want to mess up your current jumping setup, like, at some point you have decided to just swap between files A and B, with A being your current file, and now you have to go to C. In traditional neovim, B would have been forgotten, and now you can only jump between A and C. It's fine if you remember the full filename of B, what if you forgot? And now it gets annoying to try remember it and then it just interrupts your flow, trying to go back to only swap between A and B. 

This is the kind of problem this plugin solves for you. We introduce mainly **Triquetra buffer system**. This is the novel part of the project. In a way because of how the triquetra buffers are presented in the UI, this gives you at least a semblance of your current jumping setup. And I have designed this in a way, that you can always restore the secondary buffer and the ternary buffer so you can always get back to what once was. There are other neat features as well, just read the **How to Use** section below.

### Functions

- **Triquetra Buffer System**: Each window maintains current/secondary/ternary buffer relationships with a primary buffer
- **Session Persistence**: Buffer relationships survive restarts through hash-based file identification  
- **Cycling Mode**: Explore buffers without losing your working context
- **Context Preservation**: Remembers where buffers came from for restoration
- **Buffer Lifecycle**: Closed buffers reopen when accessed through relationships
- **Visual Feedback**: Color-coded bufferline and winbar show buffer relationships
- **Per-Window Tracking**: Independent buffer relationships for each window

## New Feature

1. **Multi-version primary buffer**
    You can backtrack now your previous primary buffer. Every time you set a new buffer as a primary, it is put in the first of a queue (primary_buffers). The first one is always the primary, the others are the "previous".
    - You can now then manage it with a window pop-up, it is editable like that in harpoon window. 
        - Delete-yank and then paste it in another place to reorder... 
        - Or just delete, to really remove it.
        - Type up a filereadable filepath and just save.
            - The system validates if it is readable. If it is readable, it registers it.
            - If not, then vim.notify() an error, nothing is saved.
        - If you press enter while under a line (in normal mode), that line will be put on top which will be promoted as the current primary buffer.
    - The default keybind `<m-;><m-f>` will now just always select the first element `primary_buffers[1]`
    - If you disable primary buffer, you can still use the pop-up window to set a primary buffer from the queue, but `<m-;><m-f>` won't do anything at all, until you set it to active again..
    - You can open the popup floating window with `<m-;>F`


## Demo
This is a short demo. It just covers how the triquetra buffers update for all sorts of jumps. The system automatically handles all cases, to make jumps and backtracking consistent. This buffers update only updates at BufEnter and non-cycling mode.

You can also see that the two windows have their own history. You can turn this off. 

![Image](https://github.com/user-attachments/assets/deb30ab4-d049-437d-bbd5-8dfe5c21bd47)

## Requirements

- resession.nvim
- nvim-cokeline
- harpoon (harpoon feature still coupled with the plugin, working on togglable option)
- openssl (system installed, used for hashing file names and  directories)

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
            buf_filter = function(bufnr)
                local buftype = vim.bo[bufnr].buftype
                if vim.bo[bufnr].filetype == "image_nvim" or vim.bo[bufnr].filetype == "oil" then -- if you incorporated oil.nvim for example.
                    return true
                elseif buftype ~= "" then
                    return false
                elseif vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) == false then
                    return false
                else
                    return resession.default_buf_filter(bufnr)
                end
            end,
            -- your configurations....
        })
        resession.add_hook("pre_save", function()
            require('cavediver').save_session(vim.loop.cwd())
        end)

        resession.add_hook("post_load", function()
            require('cavediver').load_session(vim.loop.cwd())
        end)
    end,
    dependencies = {
        "kampanaut/cavediver"
    }
},
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

The cavediver plugin tracks windows showing regular file buffers. When a window switches to a non-regular buffer then it will clean the triquetra associated to that window. Each window has their own tiquetra. 

A window triquetra is a data structure that stores the window's triquetra slots: current buffer, ternary buffer, secondary buffer, and primary buffer. Each type of slot has their own means of updating themselves.

Winbar UI:
```text
⦉32⦊ [7] history/init.lua    ⟦9⟧ window/routines.lua
```

- `⦉32⦊` is the ternary buffer's buffer number.
- `[7] history/init.lua` is the current buffer.
- `⟦9⟧ window/routines.lua` is the secondary buffer.

**Ternary slot**

The ternary slot updates every time you jump to a new buffer. The current buffer you had will now become the ternary buffer time. And the new buffer will become the current buffer. It's your previous buffer, basically. But it won't get modified when you select a buffer dueing cycling mode, via `<m-v>`.

Everytime you jump, if there is a ternary buffer, the system records your current buffer's ternary buffer, before the current buffer is replaced. So when you go back to that current buffer and want to bring back what was once before, you can do it with `<m-;><m-r>`.

**Secondary slot**

The secondary slot only updates when you say so. This is your stow slot. If you have a buffer you want to keep before jumping, this is your way. To jump to the secondary buffer, simply press `<m-f>`. The current buffer will become the secondary buffer.

Every time you jump to secondary the system also records the current buffers, secondary – just the same as ternary's way but with keys `<m-;><m-t>`

**Primary Slot**

The primary buffer is the window's "mark."
So if you have a buffer of interest that you don't want to lose your hands on, then simply make it a primary buffer, so that no matter how much you kept jumping, you can bring it back to your reach with `<m-;><m-f>`

**Notes**

These only works for regular file buffers. The cavediver plugin, only tracks regular file buffers. Makes it easy to deal with cross-session persistence. 

A buffer cannot occur more than once in a window triquetra.

## Bufferline

As you can see the buffers shown in the bufferline are color coded for better experience and it is sorted by buffer visits. The most recent appears on the left. This is really helpful on trying to know how you ended up with your current buffer and not solely depending on the `<c-i>` & `<c-o>`. 

There is an option `bufferline.history_view`, and this dictates whether to sort the buffers with the global visit history or the current window's own visit history. 

**bufferline.history_view = "window"**

Window-specific history is a recent addition and is really nice on seeing the bufferline not being cluttered with your previous window's series of buffer jumps. 

### Cycling

`<m-n>` and `<m-m>` calls cokeline's cycle function and this makes the whole cavediver plugin be put into "cycling" mode. You will see the change of mode with the colors of the triquetra winbar and cokeline bufferline. 

You will notice that no matter how you cycle, the current slot buffer doesn't change. It is because during cycling mode, the cavediver plugin has stopped tracking visits. You need to do `<m-v>` to select the buffer you are currently and quit cycling mode. 

