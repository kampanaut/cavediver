---Navigation domain hooks for coordination with other domains.
---
---The navigation domain provides coordination context through its state changes.
---These hooks coordinate with other domains when navigation mode changes.

local history = require('domains.history')
local routines = require('domains.navigation.routines')
local states = require('domains.navigation.states')
local data = require('domains.navigation.data')
local navigationSM = require('domains.navigation.sm')

navigationSM:on(states.NORMAL, states.CYCLING, "start_cycling", function(context)
	-- When transitioning to cycling mode, notify history domain
	---@cast context transitionContextArg
	history.sm:to(history.states.DETACHED, context or {}, history.states.mode.UPDATE)
	routines.cycle_buffer(context.direction)
end, 1, true)

navigationSM:on(states.CYCLING, states.CYCLING, "keep_cycling", function(context)
	routines.cycle_buffer(context.direction)
end, 1, true)

navigationSM:on(states.CYCLING, states.NORMAL, "stop_cycling", function(context)
	local ui = require('domains.ui')
	---@cast context transitionContextArg
	history.sm:to(history.states.ATTACHED, { buf = context.history.cbufnr }, history.states.mode.UPDATE)
	ui.sm.loop:to(ui.states.LOOP.SELF)
end, 1, true)

vim.api.nvim_create_autocmd("WinEnter", {
	callback = function()
		local current_tab = vim.api.nvim_get_current_tabpage()
		local current_win = vim.api.nvim_get_current_win()
		local previous_win = vim.fn.win_getid(vim.fn.winnr("#"))

		if previous_win and previous_win ~= current_win then
			routines.record_window_jump(current_tab, previous_win, current_win)
		end
	end,
})

vim.api.nvim_create_autocmd({"TabClosed", "WinClosed"}, {
	callback = function(args)
		local tab_id = tonumber(args.file)
		if tab_id and data.window_jump_history[tab_id] then
			data.window_jump_history[tab_id] = nil
		end
	end,
})

