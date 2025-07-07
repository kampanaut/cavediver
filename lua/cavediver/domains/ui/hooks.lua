---UI domain hooks for extending other domains' state machines.
---
---The UI domain extends navigation and history state machines with hooks that manage
---visual component state. These hooks ensure UI components adapt appropriately to
---different coordination modes and buffer state changes.

local uiMachines = require('cavediver.domains.ui.sm')
local history = require('cavediver.domains.history')
local states = require('cavediver.domains.ui.states')
local data = require('cavediver.domains.ui.data')
local routines = require('cavediver.domains.ui.routines')

uiMachines.loop:on("*", states.LOOP.SELF, "update_ui_state", function()
	local navigation = require('cavediver.domains.navigation')
	local tracked_winid = navigation.routines.find_most_recent_tracked_window()
	
	if tracked_winid then
		routines.refresh_ui(tracked_winid)  -- Use tracked window as fake current
		routines.show_ui()  -- This still uses real current window for display
	end
end, 1, true)

history.sm:on("*", history.states.ATTACHED, "refresh_ui_attached", function(context, from_state, to_state)
	if context.history_modified == nil then
		error("history_modified is nil in refresh_ui_attached hook")
	elseif context.history_modified == false then
		return -- skip if history didn't update anything.
	end
	uiMachines.loop:to(states.LOOP.SELF)
end, 3, true, history.states.mode.UPDATE)

history.sm:on(history.states.DETACHED, history.states.DETACHED, "refresh_ui_detached", function(context, _, _)
	uiMachines.loop:to(states.LOOP.SELF)
end, 3, true, history.states.mode.UPDATE)


-- Clear display name cache on buffer changes for accurate basename display
vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufFilePost", "BufWritePost" }, {
	callback = function()
		data.clear_display_name_cache()
	end,
})

vim.api.nvim_create_autocmd({ "VimResized" }, {
	callback = function()
		routines.debounced_update()
	end,
})

vim.api.nvim_create_autocmd({ "WinEnter"}, {
	callback = function ()
		uiMachines.loop:to(states.LOOP.SELF)
	end
})

vim.api.nvim_create_autocmd({ "BufModifiedSet" }, {
	callback = function ()
		uiMachines.loop:to(states.LOOP.SELF)
	end
})
