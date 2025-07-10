---Navigation domain hooks for coordination with other domains.
---
---The navigation domain provides coordination context through its state changes.
---These hooks coordinate with other domains when navigation mode changes.

local history = require('cavediver.domains.history')
local routines = require('cavediver.domains.navigation.routines')
local states = require('cavediver.domains.navigation.states')
local data = require('cavediver.domains.navigation.data')
local navigationSM = require('cavediver.domains.navigation.sm')

navigationSM:on(states.NORMAL, states.CYCLING, "start_cycling", function(context)
	-- When transitioning to cycling mode, notify history domain
	---@cast context transitionContextArg
	history.sm:to(history.states.DETACHED, context or {}, history.states.mode.UPDATE)
	routines.cycle_buffer(context.direction)
end, 1, true, states.mode.CYCLE)

navigationSM:on(states.CYCLING, states.CYCLING, "keep_cycling", function(context)
	routines.cycle_buffer(context.direction)
end, 1, true, states.mode.CYCLE)

navigationSM:on(states.CYCLING, states.NORMAL, "stop_cycling", function(context)
	local ui = require('cavediver.domains.ui')
	---@cast context transitionContextArg
	history.sm:to(history.states.ATTACHED, { buf = context.history.cbufnr }, history.states.mode.UPDATE)
	ui.sm.loop:to(ui.states.LOOP.SELF)
end, 1, true, states.mode.CYCLE)

navigationSM:on("*", "*", "winenter_record_window", function(context)
	local current_tab = vim.api.nvim_get_current_tabpage()
	local current_win = vim.api.nvim_get_current_win()
	local previous_win = vim.fn.win_getid(vim.fn.winnr("#"))

	if previous_win and previous_win ~= current_win then
		routines.record_window_jump(current_tab, previous_win, current_win)
	end
end, 1, true, states.mode.WINENTER)

vim.api.nvim_create_autocmd({"TabClosed", "WinClosed"}, {
	callback = function(args)
		local tab_id = tonumber(args.file)
		if tab_id and data.window_jump_history[tab_id] then
			data.window_jump_history[tab_id] = nil
		end
	end,
})

vim.api.nvim_create_autocmd("WinEnter", {
	callback = function(_)
		navigationSM:to(navigationSM:state(), {}, states.mode.WINENTER)
	end
})
