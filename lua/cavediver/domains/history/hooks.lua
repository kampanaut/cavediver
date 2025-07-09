local historySM = require("cavediver.domains.history.sm")

local states = require('cavediver.domains.history.states')
local data = require('cavediver.domains.history.data')


local routines = require("cavediver.domains.history.routines")

historySM:on("*", states.ATTACHED, "attach_history_update", function(context, _, _)
	-- Pure history domain logic - always attach core history tracking
	-- print("nandito ako")
	if not context.buf then
		error("context.buf is nil in attach_history hook")
	end

	if context.mode == states.mode.DELETE then
		routines.update_buffer_history_ordered()
		routines.update_buffer_history_ordered_nonharpooned()
	elseif context.mode == states.mode.UPDATE then
		local history_modified = routines.update_buffer_history(context.buf) -- the buffer where you currently at.
		if history_modified then
			routines.update_buffer_history_ordered()
			routines.update_buffer_history_ordered_nonharpooned()
		end
		context.history_modified = history_modified
	end
	-- print_table(data.hash_buffer_registry)
end, 1, true)
-- this runs regardless of mode, so we can track history in all modes.
-- It needs to update for deletes

historySM:on(states.ATTACHED, states.DETACHED, "detach_history", function(context, _, _)
	if context.window and context.window.current_crux then
		routines.snapshot_origin(context.window.current_crux)
	end
end, 2, true)


historySM:on("*", "*", "handle_deletion", function(context, from, to)
	-- Handle deletion immediately, regardless of state
	-- print("FUCK")
	if not context.buf then
		error("context.buf is nil in attach_history hook")
	end
	-- print("I'm fucking here. Delete ", context.buf)
	-- print("SHEEESH")
	local filehash = routines.get_hash_from_buffer(context.buf)
	if filehash then -- if it's registered, then we untrack it. Ignore the untegistered, because they are unrecongised by BufEnter.
		routines.track_closing_filehash(filehash)
		routines.untrack_buffer(context.buf)
		routines.unregister_buffer(context.buf)
	end
end, 0, true, states.mode.DELETE)

-- What happens when a buffer is deleted?
vim.api.nvim_create_autocmd("BufDelete", {
	callback = function(args)
		-- print("HOOOY")
		-- print_table(args)
		-- print("BufDelete"..args.buf .. " - "..vim.api.nvim_buf_get_name(args.buf))
		historySM:to(historySM:state(), { buf = args.buf }, states.mode.DELETE)
	end,
})

-- What happens when we enter a buffer?
vim.api.nvim_create_autocmd("BufEnter", {
	callback = function(args)
		-- print("BufEnter"..args.buf .. " - "..vim.api.nvim_buf_get_name(args.buf))
		historySM:to(historySM:state(), { buf = args.buf }, states.mode.UPDATE)
	end,
})

-- BufFilePre: Clean up old identity
vim.api.nvim_create_autocmd("BufFilePre", {
	callback = function(args)
		-- print("rename pre")
		-- print(vim.bo[args.buf].buftype)
		-- print(args.file)
		historySM:to(historySM:state(), { buf = args.buf }, states.mode.DELETE)
	end
})

-- BufFilePost: Re-register new identity
vim.api.nvim_create_autocmd("BufFilePost", {
	callback = function(args)
		-- print("rename post")
		-- print(vim.bo[args.buf].buftype)
		-- print(args.file)
		historySM:to(historySM:state(), { buf = args.buf }, states.mode.UPDATE)
	end
})


-- BufFilePre: Clean up old identity
vim.api.nvim_create_autocmd("WinEnter", {
	callback = function(args)
		routines.construct_crux(require("cavediver.domains.navigation").routines.find_most_recent_tracked_window())
	end
})
