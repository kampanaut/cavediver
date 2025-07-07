---UI domain initialization, extension hooks, and API layer.
---
---The UI domain manages visual interface components like bufferlines, winbars,
---and status indicators. This module provides the API layer and loads extension
---hooks that integrate with other domains' state machines.

local states = require('domains.ui.states')
local data = require('domains.ui.data')
local routines = require('domains.ui.routines')
local history = require('domains.history')

local bufferline_state = data.bufferline_state

local configs = require("configs")

-- Load hooks to extend other domains' state machines
require('domains.ui.hooks')

-- Get UI state machines for domain coordination
local ui_machines = require('domains.ui.sm')

-- The UI domain provides multiple independent state machines for different components

local M = {
	sm = ui_machines, -- Multiple UI state machines
	states = states,  -- State constants
	data = data,      -- Domain data structures
	routines = routines, -- Domain business logic
}

---Initiate the winbar highlight groups.
---@return nil
function M.init_winbar_highlights()
	-- This is where we completely define the winbar highlight groups.
	vim.api.nvim_set_hl(0, "WinbarBase", { fg = configs.colors.base.focused.fg, bg = configs.colors.base.focused.bg, bold = true })
	vim.api.nvim_set_hl(0, "WinbarBaseNC", { fg = configs.colors.base.unfocused.fg, bg = configs.colors.base.unfocused.bg })
	vim.api.nvim_set_hl(0, "WinbarFilenameCurrent", { fg = configs.colors.current.focused.filename, bg = configs.colors.base.focused.bg, bold = true, underline = true })      -- Green filename
	vim.api.nvim_set_hl(0, "WinbarFilenameSecondary", { fg = configs.colors.secondary.focused.filename, bg = configs.colors.base.focused.bg, bold = true })      -- Green filename
	vim.api.nvim_set_hl(0, "WinbarFilenameTernary", { fg = configs.colors.ternary.focused.filename, bg = configs.colors.base.focused.bg, bold = true })      -- Green filename
	vim.api.nvim_set_hl(0, "WinbarFilenameCurrentNC", { fg = configs.colors.current.unfocused.filename, bg = configs.colors.base.unfocused.bg, bold = true })    -- Gray filename (inactive)
	vim.api.nvim_set_hl(0, "WinbarFilenameSecondaryNC", { fg = configs.colors.secondary.unfocused.filename, bg = configs.colors.base.unfocused.bg, bold = true })    -- Gray filename (inactive)
	vim.api.nvim_set_hl(0, "WinbarFilenameTernaryNC", { fg = configs.colors.ternary.unfocused.filename, bg = configs.colors.base.unfocused.bg, bold = true })    -- Gray filename (inactive)
	vim.api.nvim_set_hl(0, "WinbarBufnrCurrent", { fg = configs.colors.current.focused.bufnr, bg = configs.colors.base.focused.bg, bold = true })                      -- Amber buffer ID
	vim.api.nvim_set_hl(0, "WinbarBufnrSecondary", { fg = configs.colors.secondary.focused.bufnr, bg = configs.colors.base.focused.bg })                      -- Amber buffer ID
	vim.api.nvim_set_hl(0, "WinbarBufnrTernary", { fg = configs.colors.ternary.focused.bufnr, bg = configs.colors.base.focused.bg, bold = true })      -- Green filename
	vim.api.nvim_set_hl(0, "WinbarBufnrPrimary", { fg = configs.colors.primary.active, bg =  configs.colors.base.focused.bg })                      -- Amber buffer ID
	vim.api.nvim_set_hl(0, "WinbarBufnrPrimaryDisabled", { fg = configs.colors.primary.inactive, bg = configs.colors.base.focused.bg })                      -- Amber buffer ID
	vim.api.nvim_set_hl(0, "WinbarBufnrPrimaryNC", { fg = configs.colors.primary.unfocused, bg = configs.colors.base.unfocused.bg})                      -- Amber buffer ID
	vim.api.nvim_set_hl(0, "WinbarBufnrCurrentNC", { fg = configs.colors.current.unfocused.bufnr, bg = configs.colors.base.unfocused.bg, bold = true })    -- Gray filename (inactive)
	vim.api.nvim_set_hl(0, "WinbarBufnrSecondaryNC", { fg = configs.colors.secondary.unfocused.bufnr, bg = configs.colors.base.unfocused.bg, bold = true })    -- Gray filename (inactive)
	vim.api.nvim_set_hl(0, "WinbarBufnrTernaryNC", { fg = configs.colors.ternary.unfocused.bufnr, bg = configs.colors.base.unfocused.bg, bold = true })    -- Gray filename (inactive)
	vim.api.nvim_set_hl(0, "BothWayNerdArrow", { fg = configs.colors.both_way_arrow.focused, bg = configs.colors.base.focused.bg})                      -- Amber buffer ID
	vim.api.nvim_set_hl(0, "BothWayNerdArrowNC", { fg = configs.colors.both_way_arrow.unfocused, bg = configs.colors.base.unfocused.bg})                      -- Amber buffer ID
end

---Initiate UI Timers (cleanup and winbar refresh)
---@return nil
function M.init_refresh_timer(refresh_interval)
	local periodic_timer = vim.loop:new_timer()

	if not periodic_timer then
		error("Timer creation failed")
	end

	periodic_timer:start(
		0,
		configs.winbar_refresh_interval,
		vim.schedule_wrap(function()
			routines.debounced_update()
		end)
	)
end

---Get current bufferline cache state.
---
---@return BufferlineCache cache The current bufferline performance cache
function M.get_bufferline_cache()
	return data.bufferline_state
end

---Hide bufferline component.
---
---@return nil
function M.hide_bufferline()
	ui_machines.bufferline:to(states.BUFFERLINE.HIDDEN)
end

---Show bufferline component.
---
---@return nil
function M.show_bufferline()
	ui_machines.bufferline:to(states.BUFFERLINE.VISIBLE)
end

---Hide winbar component.
---
---@return nil
function M.hide_winbar()
	ui_machines.winbar:to(states.WINBAR.MINIMAL)
end

---Show winbar component.
---
---@return nil
function M.show_winbar()
	ui_machines.winbar:to(states.WINBAR.ACTIVE)
end

---Turn off indicators.
---
---@return nil
function M.hide_indicators()
	ui_machines.indicators:to(states.INDICATORS.OFF)
end

---Turn on indicators.
---
---@return nil
function M.show_indicators()
	ui_machines.indicators:to(states.INDICATORS.ON)
end

---Trigger UI update loop.
---
---@return nil
function M.update_ui()
	ui_machines.loop:to(states.LOOP.SELF)
end

---Check if a UI component is currently hidden.
---
---@param component string Component name ("bufferline", "winbar", "indicators")
---@return boolean hidden True if component is hidden
function M.is_hidden(component)
	if component == "bufferline" then
		return ui_machines.bufferline:state() == states.BUFFERLINE.HIDDEN
	elseif component == "winbar" then
		return ui_machines.winbar:state() == states.WINBAR.MINIMAL
	elseif component == "indicators" then
		return ui_machines.indicators:state() == states.INDICATORS.OFF
	end
	return false
end

---Clean up UI data when needed.
---
---@return nil
function M.cleanup()
	data.clear_bufferline_cache()
end

M.bufferline = {}

---Check if bufferline should be visible.
---@return boolean visible
function M.bufferline.is_bufferline_visible()
	return ui_machines.bufferline:state() == states.BUFFERLINE.VISIBLE
end

---@param bufnr Bufnr Buffer number to check
---@return boolean is_registered True if buffer should be displayed in bufferline
function M.bufferline.bufnr_is_displayed(bufnr)
	return M.bufferline.is_bufferline_visible() and bufferline_state.recent_buffers[bufnr]
end

---Determine if buffer a ranks higher than. Otherwise b ranks higher.
---@param buffer_a Bufnr
---@param buffer_b Bufnr
function M.bufferline.compare_buffers(buffer_a, buffer_b)
	return (bufferline_state.buffer_ranking[buffer_a] or 0) >
		(bufferline_state.buffer_ranking[buffer_b] or 0)
end

---Get buffer's triquetra role for current window
---@param bufnr Bufnr Buffer to check relationships for
---@return table relationships Buffer relationship info
function M.bufferline.get_buffer_relationships(bufnr)
	local triquetra = bufferline_state.current_window_triquetra

	if not triquetra then return {} end

	local is_current, is_primary, is_secondary, is_ternary

	is_current = bufnr == triquetra.current_bufnr
	is_primary = bufnr == triquetra.primary_bufnr
	is_secondary = bufnr == triquetra.secondary_bufnr
	is_ternary = bufnr == triquetra.ternary_bufnr

	local has_true = false
	if is_current then
		has_true = true
	end

	if is_primary then
		if has_true then
			error("A buffer cannot have more than one role")
		end
		has_true = true
	end

	if is_secondary then
		if has_true then
			error("A buffer cannot have more than one role")
		end
		has_true = true
	end

	if is_ternary then
		if has_true then
			error("A buffer cannot have more than one role")
		end
		has_true = true
	end

	return {
		is_current = is_current,
		is_primary = is_primary,
		is_secondary = is_secondary,
		is_ternary = is_ternary
	}
end

---Check if buffer is harpooned
---@param bufnr Bufnr
---@return boolean is_harpooned
function M.bufferline.is_harpooned(bufnr)
	return bufferline_state.harpooned_buffers[bufnr] or false
end

---Get harpoon index for buffer
---@param bufnr Bufnr
---@return number|nil index Harpoon index if harpooned
function M.bufferline.get_harpoon_index(bufnr)
	return bufferline_state.harpooned_lookup[bufnr]
end

---Get buffer foreground theme color.
---@param bufnr Bufnr
---@param is_focused boolean
---@return HexColor color Hex color code for buffer
function M.bufferline.get_theme_fg_color(bufnr, is_focused)
	local ctriquetra = bufferline_state.current_window_triquetra
	if not ctriquetra then
		error("This should not happen: No current triquetra found.")
	end
	if bufnr == ctriquetra.primary_bufnr then
		return configs.colors.current.focused.bufnr
	elseif bufnr == ctriquetra.secondary_bufnr then
		return configs.colors.secondary.focused.bufnr
	elseif bufnr == ctriquetra.current_bufnr then
		return configs.colors.current.focused.bufnr
	elseif bufnr == ctriquetra.ternary_bufnr then
		return configs.colors.ternary.focused.bufnr
	elseif is_focused then
		return configs.colors.cokeline.fg.focused
	elseif bufferline_state.harpooned_buffers[bufnr] then
		return configs.colors.harpooned.unfocused.fg
	else
		return configs.colors.cokeline.fg.unfocused
	end
end

---Get buffer background theme color.
---@param is_focused boolean
---@return HexColor
function M.bufferline.get_theme_bg_color(is_focused)
	local ctriquetra = bufferline_state.current_window_triquetra
	if not ctriquetra then
		error("This should not happen: No current triquetra found.")
	end
	if history.is_detached() then
		if is_focused then
			return configs.colors.cokeline.bg.detached.focused
		else
			return configs.colors.cokeline.bg.detached.unfocused
		end
	else
		return configs.colors.cokeline.bg.attached
	end
end

---Get buffer foreground theme color by buffer slot.
---@param bufnr Bufnr
---@return HexColor
local function get_theme_fg_by_slot(bufnr)
	local ctriquetra = bufferline_state.current_window_triquetra
	if not ctriquetra then
		error("This should not happen: No current triquetra found.")
	end
	if bufnr == ctriquetra.secondary_bufnr then
		return configs.colors.secondary.focused.bufnr
	elseif bufnr == ctriquetra.primary_bufnr and bufnr == ctriquetra.current_bufnr then
		return configs.colors.primary.focused.bufnr
	elseif bufnr == ctriquetra.current_bufnr then
		return configs.colors.current.focused.bufnr
	elseif bufnr == ctriquetra.ternary_bufnr then
		return configs.colors.ternary.focused.bufnr
	elseif bufferline_state.harpooned_buffers[bufnr] then
		return configs.colors.harpooned.unfocused.fg
	else
		return configs.colors.cokeline.fg.unfocused
	end
end

---Get buffer bold state
---@param bufnr Bufnr Buffer number
---@return boolean bold Whether text should be bold
function M.bufferline.get_buffer_bold(bufnr)
	local ctriquetra = bufferline_state.current_window_triquetra
	if not ctriquetra then
		error("This should not happen: No current triquetra found.")
	end
	return bufnr == ctriquetra.current_bufnr
end

M.set_cache_from_window_triquetra = routines.set_cache_from_window_triquetra

M.bufferline.cokeline = {}

---Return a constructed cokeline buffer components.
---@return table components
function M.bufferline.cokeline.create_buffer_components()
	local colors = require('configs').colors
	local ok, mappings = pcall(require, 'cokeline.mappings')
	if not ok then
		error("cokeline is not installed. Please install 'willothy/nvim-cokeline' to use this function.")
	end
	local get_hex = require('cokeline.hlgroups').get_hl_attr
	local comment = get_hex('Comment', 'fg')
	local diagnostic_errors = get_hex('DiagnosticError', 'fg')
	local diagnostic_warnings = get_hex('DiagnosticWarn', 'fg')
	local diagnostic_infos = get_hex('DiagnosticInfo', 'fg')
	local diagnostic_hints = get_hex('DiagnosticHint', 'fg')
	local components = {
		space = {
			text = ' ',
			truncation = { priority = 1 }
		},
		two_spaces = {
			text = '  ',
			truncation = { priority = 1 },
		},
		separator = {
			text = function(buffer)
				return buffer.index ~= 1 and '│' or ''
			end,
			fg = colors.base.focused.fg,
			truncation = { priority = 1 }
		},
		separator_for_last = {
			text = function(buffer)
				return buffer.is_last and '│' or ''
			end,
			fg = colors.base.focused.fg,
			truncation = { priority = 1 }
		},
		devicon = {
			text = function(buffer)
				return
					(mappings.is_picking_focus() or mappings.is_picking_close())
					and buffer.pick_letter .. " "
					or buffer.devicon.icon
			end,
			fg = function(buffer)
				if mappings.is_picking_close() then
					return "#a05959"
				elseif mappings.is_picking_focus() then
					return "#d7d7a5"
				else
					return get_theme_fg_by_slot(buffer.number)
				end
			end,
			truncation = { priority = 1 }
		},
		index = {
			text = function(buffer)
				local ctriquetra = bufferline_state.current_window_triquetra
				if not ctriquetra then return ' ' end -- Graceful fallback

				local string
				local harpooned = bufferline_state.harpooned_buffers[buffer.number]
				local bufnr = buffer.number
				if bufnr == ctriquetra.primary_bufnr or bufnr == ctriquetra.ternary_bufnr then
					string = "⦉" .. bufnr .. "⦊"
				elseif bufnr == ctriquetra.secondary_bufnr then
					string = "⟦" .. bufnr .. "⟧"
				elseif bufnr == ctriquetra.current_bufnr then
					string = "[" .. bufnr .. "]"
				else
					if harpooned then
						return "󰛢  "
					else
						return ' '
					end
				end

				if harpooned then
					string = string .. " 󰛢"
				end

				return string .. "  "
			end,
			bold = function(buffer)
				if buffer.is_focused then
					return true
				else
					return false
				end
			end,
			fg = function(buffer)
				local ctriquetra = bufferline_state.current_window_triquetra
				if not ctriquetra then return ' ' end -- Graceful fallback
				if
					buffer.number == ctriquetra.primary_bufnr and
					ctriquetra.has_primary == false
				then
					return comment
				else
					return nil
				end
			end,
			truncation = { priority = 1 }
		},
		unique_prefix = {
			text = function(buffer)
				return buffer.unique_prefix
			end,
			fg = comment,
			style = 'italic',
			truncation = {
				priority = 1,
				direction = 'left',
			},
		},
		filename = {
			fg = function(buffer)
				return get_theme_fg_by_slot(buffer.number)
			end,
			text = function(buffer)
				if bufferline_state.harpooned_buffers[buffer.number] then
					return buffer.filename .. " ⥤ {" .. bufferline_state.harpooned_lookup[buffer.number] .. "}"
				else
					return buffer.filename
				end
			end,
			bold = function(buffer)
				if buffer.is_focused then
					return true
				else
					return false
				end
			end,
			underline = function(buffer)
				if buffer.is_focused then
					return true
				else
					return false
				end
			end,
			truncation = {
				priority = 1,
				direction = 'left',
			},
		},
		diagnostics = {
			text = function(buffer)
				local number
				if buffer.diagnostics.errors ~= 0 then
					number = buffer.diagnostics.errors
				elseif buffer.diagnostics.warnings ~= 0 then
					number = buffer.diagnostics.warnings
				elseif buffer.diagnostics.infos ~= 0 then
					number = buffer.diagnostics.infos
				elseif buffer.diagnostics.hints ~= 0 then
					number = buffer.diagnostics.hints
				else
					return ''
				end
				return " ❬" .. number .. "❭"
			end,
			fg = function(buffer)
				if buffer.diagnostics.errors ~= 0 then
					return diagnostic_errors
				elseif buffer.diagnostics.warnings ~= 0 then
					local ctriquetra = bufferline_state.current_window_triquetra
					if not ctriquetra then return ' ' end -- Graceful fallback
					local bufnr = buffer.number
					if bufnr == ctriquetra.secondary_bufnr then
						return colors.primary.active
					else
						return diagnostic_warnings
					end
				elseif buffer.diagnostics.infos ~= 0 then
					return diagnostic_infos
				elseif buffer.diagnostics.hints ~= 0 then
					return diagnostic_hints
				else
					return nil
				end
			end,
			truncation = { priority = 1 },
		},
		close_or_unsaved = {
			text = function(buffer)
				return buffer.is_modified and '●' or '󰅖'
			end,
			fg = function (buffer)
				return get_theme_fg_by_slot(buffer.number)
			end,
			delete_buffer_on_left_click = true,
			truncation = { priority = 1 },
		},
	}
	return {
		components.separator,
		components.two_spaces,
		components.space,
		components.index,
		components.devicon,
		components.unique_prefix,
		components.filename,
		components.diagnostics,
		components.space,
		components.two_spaces,
		components.close_or_unsaved,
		components.two_spaces,
		components.separator_for_last,
	}
end

---Return a constructed cokeline tab components.
function M.bufferline.cokeline.create_tab_components()
	local components = {
		separator = {
			text = '│',
			fg = "#d5c4a1",
			truncation = { priority = 1 }
		},
		separator_for_last = {
			text = function(buffer)
				return buffer.is_last and '│ ' or ''
			end,
			fg = configs.colors.base.focused.fg,
			truncation = { priority = 1 }
		},
		tabnr = {
			text = function(tab)
				return "⟨" .. tab.number .. "⟩"
			end,
			fg = function(tab)
				if tab.is_active then
					return configs.colors.current.focused.bufnr
				else
					return configs.colors.current.unfocused.bufnr
				end
			end,
		},
		space = {
			text = ' ',
			truncation = { priority = 1 }
		},
		two_spaces = {
			text = '  ',
			truncation = { priority = 1 },
		},
	}
	return {
		components.separator,
		components.space,
		components.tabnr,
		components.space,
		components.separator_for_last
	}
end

return M
