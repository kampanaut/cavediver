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
local navigation = require('cavediver.domains.navigation')

uiMachines.loop:on("*", states.LOOP.SELF, "update_ui_state", function()
	local navigation = require('cavediver.domains.navigation')
	local tracked_winid = navigation.routines.find_most_recent_tracked_window()

	if tracked_winid then
		routines.refresh_ui(tracked_winid) -- Use tracked window as fake current
		routines.show_ui()           -- This still uses real current window for display
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

navigation.sm:on("*", "*", "winenter_update_ui", function(context)
	uiMachines.loop:to(states.LOOP.SELF)
end, 2, true, navigation.states.mode.WINENTER)


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

vim.api.nvim_create_autocmd({ "BufModifiedSet" }, {
	callback = function()
		uiMachines.loop:to(states.LOOP.SELF)
	end
})

vim.api.nvim_create_autocmd("Filetype", {
	pattern = "cavediver-primary-buffer-history",
	callback = function(args)
		local function close_window()
			vim.cmd("write!")
			local dwin = vim.b[args.buf].display_window

			vim.api.nvim_win_close(dwin, true)
			vim.defer_fn(function()
				if vim.api.nvim_buf_is_loaded(args.buf) then
					vim.api.nvim_buf_delete(args.buf, { force = true })
				end
			end, 100)
		end

		local function promote_to_primary_and_quit()
			local dwin = vim.b[args.buf].display_window
			local dbuf = args.buf
			local cursor_line = vim.api.nvim_win_get_cursor(dwin)[1]
			local lines = vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)

			if cursor_line > #lines then return end

			local selected_filepath = vim.trim(lines[cursor_line])

			if selected_filepath == "" then
				vim.notify("No filepath selected", vim.log.levels.WARN)
				return
			end

			table.remove(lines, cursor_line)
			table.insert(lines, 1, selected_filepath)

			vim.api.nvim_buf_set_lines(dbuf, 0, -1, false, lines)

			close_window()
		end


		-- Quick save
		vim.keymap.set("n", "<C-s>", "<cmd>write<cr>", { buffer = args.buf, desc = "Save queue" })

		-- Close without saving
		vim.keymap.set("n", "<C-c>", close_window, { buffer = args.buf, desc = "Close without saving" })

		vim.keymap.set("n", "q", close_window, { buffer = args.buf, desc = "Close without saving" })

		vim.keymap.set("n", "<cr>", promote_to_primary_and_quit, { buffer = args.buf, desc = "Promote file under cursor and quit floating window"})
	end
})

-- WinClosed - only happens once, should be removed
vim.api.nvim_create_autocmd("WinClosed", {
	once = true, -- Automatically removes after first execution
	callback = function(args)
		if not args.file then
			return
		end
		local winid = tonumber(args.file)
		if not winid then
			return
		end
		local bufnr = vim.api.nvim_win_get_buf(winid)

		if vim.bo[bufnr].filetype ~= "cavediver-primary-buffer-history" then
			return
		end

		vim.api.nvim_buf_delete(bufnr, { force = true })
	end
})
