---Storage domain hooks for coordinating session persistence.
---
---This module contains hooks that extend other domains' state machines
---to trigger auto-save functionality when important state changes occur.

local routines = require('cavediver.domains.storage.routines')
local states = require('cavediver.domains.storage.states')
local storageSM = require('cavediver.domains.storage.sm')

storageSM:on("{idle,bare}", states.SAVING, "save_history_pre_quit", function(context, _, _)
	-- Trigger auto-save when entering SAVING state
	routines.save_history(context.cwd)
end, 1, true)

storageSM:on(states.BARE, states.LOADING, "load_history_pre_start", function(context, _, _)
	-- Load history when entering LOADING state
	routines.load_history(context.cwd)
end, 1, true)

storageSM:on("{bare,saving,loading}", "{idle,saving}", "back_to_idle", function(_, _, _) end, 1, true)


