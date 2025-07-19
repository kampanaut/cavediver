---Window domain hooks for extending the history state machine.
---
---The window domain extends the history state machine with hooks that manage
---per-window buffer relationships. These hooks run after the history domain
---hooks to ensure proper execution order.

local history = require('cavediver.domains.history')
local navigation = require("cavediver.domains.navigation")

local states = require('cavediver.domains.window.states')

local windowSM = require('cavediver.domains.window.sm')
local routines = require('cavediver.domains.window.routines')
local data = require('cavediver.domains.window.data')

history.sm:on("*", "*", "ensure_curwin_crux", function(context, _, _)
	local winid = context.winid or vim.api.nvim_get_current_win()
	local triquetra = data.get_window_triquetra(winid) -- creates triquetra for us, or not will return nil instead. 
	if not triquetra then
		context.window = nil
	end
end, 1, true, history.states.mode.UPDATE)

history.sm:on("*", "*", "cleanup_triquetras", function(context, _, _)
	-- the filepath-hash registry is the source of truth. If it don't exist, then it shouldn't be in the triquetra.
	-- It's an close empty noname buffer. And We don't really want this to be tracked when it's closed.
	routines.cleanup_triquetras()
end, 1.8, true)

history.sm:on(history.states.ATTACHED, history.states.ATTACHED, "displacement_mangement", function(context, _, _)
	if context.history_modified == nil then
		error("history_modified is nil in displacement_mangement hook")
	elseif context.history_modified == false then
		return -- skip if history didn't update anything.
	end
	local winid = vim.api.nvim_get_current_win()
	local new_bufnr = context.buf
	local new_filehash = history.get_hash_from_buffer(new_bufnr)

	if not new_filehash then return end -- Skip unregistered buffers

	local triquetra = data.crux[winid]
	if not triquetra then
		return
	end
	-- happens when you are dealing with an empty ternary slot and it's just an ordinary 
	-- swap with the secondary slot.
	if triquetra.secondary_slot == new_filehash then
		triquetra.secondary_slot = triquetra.current_slot
		triquetra.current_slot = new_filehash
	elseif triquetra.current_slot ~= new_filehash then
		-- Only create displacement mapping if NOT in cycling mode
		-- and the new bufnr is not the current alternative slot.
		if navigation.sm:state() == navigation.states.NORMAL then
			if
				triquetra.secondary_slot and
				triquetra.ternary_slot and
				triquetra.secondary_slot == triquetra.ternary_slot
			then
				error("Duplicates detected in current triquetra")
			end
			if triquetra.ternary_slot and new_filehash ~= triquetra.ternary_slot then
				triquetra.displacement_ternary_map[triquetra.current_slot.."-swap"] = nil
				triquetra.displacement_ternary_map[triquetra.current_slot] = triquetra.ternary_slot
			end

			if triquetra.current_slot == triquetra.displacement_ternary_map[new_filehash] then
				if triquetra.ternary_slot == new_filehash then
					vim.notify(
						"The stored ternary of the new buffer is already the ternary, switching with the pre-jump stored ternary.",
						vim.log.levels.WARN
					)
					triquetra.displacement_ternary_map[new_filehash] = triquetra.displacement_ternary_map[triquetra.current_slot]
				else
					vim.notify(
						"The stored ternary of the new buffer is already the ternary, switching with the pre-jump ternary.",
						vim.log.levels.WARN
					)
					triquetra.displacement_ternary_map[new_filehash] = triquetra.ternary_slot
				end
			end
		end
		-- so that we don't update with bad information. This is bad information, 
		-- it doesn't provide anything outside the current ternary relationship.
		-- We are tracking for buffers outside, that were ternary slots.

		-- Always update slots
		triquetra.ternary_slot = triquetra.current_slot
		triquetra.current_slot = new_filehash
	end
end, 2, true, history.states.mode.UPDATE)

history.sm:on(history.states.DETACHED, history.states.ATTACHED, "reconcile_triquetra", function(context, _, _)
	if context.history_modified == nil then
		error("history_modified is nil in reconcile_triquetra hook")
	elseif context.history_modified == false then
		return -- skip if history didn't update anything.
	end
	if context.buf == nil then
		error("context.buf is nil in reconcile_triquetra hook")
	end
	routines.reconcile_triquetra(vim.api.nvim_get_current_win(), context.buf)
end, 2, true, history.states.mode.UPDATE)

-- no displacement
history.sm:on(history.states.DETACHED, history.states.DETACHED, "nondisplacement_management", function(context)
	local winid = context.winid
	local new_filehash = history.get_hash_from_buffer(context.buf)

	if winid == nil or new_filehash == nil then
		return
	end

	local triquetra = data.crux[winid]
	if triquetra and triquetra.current_slot ~= new_filehash then
		triquetra.current_slot = new_filehash
	end

end, 2, true, history.states.mode.UPDATE)

navigation.sm:on("*", "*", "winenter_track_current_window", function(context)
	local last_valid_window = vim.api.nvim_get_current_win()
	if data.crux[last_valid_window] then
		data.last_valid_window = last_valid_window
	end
end, 2, true, navigation.states.mode.WINENTER)

vim.api.nvim_create_autocmd("WinClosed", {
	callback = function(args)
		data.crux[tonumber(args.file)] = nil
	end,
})
