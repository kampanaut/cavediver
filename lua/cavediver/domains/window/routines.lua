---Window domain core routines for buffer relationship management.
---
---This module contains the main business logic for managing triquetra buffer
---relationships within windows, including the complex reconciliation logic
---that was previously in sync_detached_history().

local data = require('cavediver.domains.window.data')

local history = require('cavediver.domains.history')
local loop_sm = require('cavediver.domains.ui.sm').loop
local loop_states = require('cavediver.domains.ui.states').LOOP

local M = {}

---Remove buffer from closed buffers list by filehash.
---@param filehash Filehash The filehash to remove from closed buffers
local function remove_from_closed_buffers(filehash)
	for i, closed_filehash in ipairs(history.data.closed_buffers) do
		if closed_filehash == filehash then
			table.remove(history.data.closed_buffers, i)
			break
		end
	end
end

---A function used to handle conflicts of slot allocations in the triquetra.
---@param winid WinId
---@param new_bufnr Bufnr
function M.reconcile_triquetra(winid, new_bufnr)
	local new_filehash = history.get_hash_from_buffer(new_bufnr)

	if not new_bufnr then error("Bufnr must be provided.") end

	if not new_filehash then
		error("What the fuck.")
	end -- Skip unregistered buffers

	local triquetra = data.crux[winid]
	local temp, proc
	if triquetra and triquetra.current_slot ~= new_filehash then
		-- Reconcile the triquetra slots if we selected a buffer part of the relationship
		if triquetra.ternary_slot == new_filehash then
			triquetra.displacement_ternary_map[triquetra.current_slot.."-swap"] = triquetra.ternary_slot
			temp = triquetra.current_slot
			triquetra.current_slot = triquetra.ternary_slot
			triquetra.ternary_slot = temp
			proc = true
		end
		if triquetra.secondary_slot == new_filehash then
			if proc then
				error("Duplicates detected in triquetra slots")
			end
			temp = triquetra.current_slot
			triquetra.current_slot = triquetra.secondary_slot
			triquetra.secondary_slot = temp
		end

		if not proc then
			if triquetra.displacement_ternary_map[triquetra.ternary_slot] == new_filehash then
				triquetra.displacement_ternary_map[triquetra.ternary_slot] = triquetra.current_slot
				vim.notify(
					"Avoided conflict of ternary's remembered relationship becoming current. Remembered relationship has been changed to remember pre-jump current buffer instead: ["
					.. (history.get_buffer_from_hash(triquetra.ternary_slot) or "")
					.. "] -> ["
					.. (history.get_buffer_from_hash(triquetra.current_slot) or "")
					.. "]", vim.log.levels.WARN)
			end
			triquetra.current_slot = new_filehash
		end
	end
end

---Cleanup all the triquetras. Remove any triquetra that references
---to unregistered buffers.
---
---@return nil
function M.cleanup_triquetras()
	local clear_window_display_cache = require("cavediver.domains.ui").data.clear_window_display_cache
	local set_cache_from_window_triquetra = require("cavediver").ui.routines.set_cache_from_window_triquetra
	for winid, triquetra in pairs(data.crux) do
		local current_bufnr = history.get_buffer_from_hash(triquetra.current_slot)
		local filepath
		if not current_bufnr then -- this is a special case. we can't have an unregistered
			-- hash in the current slot. doesn't make sense.
			local current_slot_candidate = history.get_hash_from_buffer(vim.api.nvim_get_current_buf())
			if current_slot_candidate then
				vim.notify("Healed the triquetra of window " ..
					winid .. " with current slot: " .. vim.api.nvim_get_current_buf())
				triquetra.current_slot = current_slot_candidate
				if triquetra.current_slot == triquetra.secondary_slot then
					triquetra.secondary_slot = nil
				elseif triquetra.current_slot == triquetra.ternary_slot then
					triquetra.ternary_slot = nil
				elseif vim.fn.index(triquetra.primary_buffer, triquetra.current_slot) ~= -1 then
					table.remove(triquetra.primary_buffer, vim.fn.index(triquetra.primary_buffer, triquetra.current_slot) + 1)
				end
			else
				-- yes if the noname buffer turns evolved into a terminal, we don't want to track it.
				--
				-- but there is a catch, what if the buffer's file was just deleted along the way? Then
				-- we just remove that current slot from the triquetra, and replace it with ternary, then
				-- secondary, then primary, then most recent buffer, if the tracked is more than 1.
				-- print("(2) Deleted window triquetra of bufnr: " .. index)
				local cbufnr, cbufhash
				if vim.api.nvim_win_is_valid(winid) then
					cbufnr = vim.api.nvim_win_get_buf(winid)
					cbufhash = history.routines.get_filehash(vim.api.nvim_buf_get_name(cbufnr))
				else
					-- yes, this line of code appears three times in this condition branch.
					-- we delete triquetras associated to windows that are not "regular" windows.
					data.crux[winid] = nil
					clear_window_display_cache(winid)
					goto continue
				end
				if cbufhash == triquetra.current_slot or vim.bo[cbufnr].buftype == "acwrite" then -- it means that the buffer didn't evolved to anything new. it was still deleted, so we fallback.
					local candidate_bufnr

					-- Part 1: Try Heal triquetra with self
					---@type boolean If true then we skip to jumping to the resolved buffer.
					local resolved = false
					local bufnr
					if triquetra.ternary_slot and history.get_buffer_from_hash(triquetra.ternary_slot) then
						triquetra.current_slot = triquetra.ternary_slot
						triquetra.ternary_slot = nil
						bufnr = history.get_buffer_from_hash(triquetra.current_slot)
						resolved = history.routines.update_buffer_history(bufnr)
						if not resolved then
							vim.cmd("bw! "..bufnr)
						end
					end
					if not resolved and triquetra.secondary_slot and history.get_buffer_from_hash(triquetra.secondary_slot) then
						triquetra.current_slot = triquetra.secondary_slot
						triquetra.secondary_slot = nil
						bufnr = history.get_buffer_from_hash(triquetra.current_slot)
						resolved = history.routines.update_buffer_history(bufnr)
						if not resolved then
							vim.cmd("bw! "..bufnr)
						end
					end
					if not resolved and triquetra.primary_buffer[1] and history.get_buffer_from_hash(triquetra.primary_buffer[1]) then
						triquetra.current_slot = triquetra.primary_buffer[1]
						bufnr = history.get_buffer_from_hash(triquetra.current_slot)
						resolved = history.routines.update_buffer_history(bufnr)
						if not resolved then
							vim.cmd("bw! "..bufnr)
						end
					end

					if resolved then -- I know this is fucking stupid, but I don't want to change the structure of this function.
						history.routines.update_buffer_history_ordered()
						history.routines.update_buffer_history_ordered_nonharpooned()
						goto apply
					end

					-- Part 2: This is when we can't heal it straightforward anymore.
					if history.get_filepath_from_hash(triquetra.current_slot) ~= nil then
						-- if it has a filepath mapping then it was registered before. If it was registered
						-- before and we ended up at this point, it means that this buffer is stale. Something
						-- must have went wrong. Otherwise, if it's not registered, i.e. empty filepath
						-- output then that means that we should never consider this in the first place, so
						-- no errors thrown. [edit: no errors thrown as well for the stale window triquetra.]

						-- this comes before healing with ordered history or creating a new NO_NAME buffer since
						-- it is quite destructive to the triquetra tracking to replace a window triquetra's current slot,
						-- which the triquetra itself is now considered stale, with a heuristic replacement buffer.
						-- The implication of this is the stale triquetra SHOULD be removed, as the window it is associated
						-- with is not a "regular" buffer anymore.
						--
						-- This is now an unregular window, because we can't heal it properly anymore and turns out the 
						-- tracked current_slot buffer was unloaded. So unloaded buffer and no possible healing, that is 
						-- what we proved in this condition branch. So we just need to nuke this triquetra, since there 
						-- is no appropriate buffer to set it to without destructively replacing the current slot, since 
						-- this window is not a "regular" window anymore.

						-- error("Impossible: current_slot is nil and no buffer is available to set it. " ..
						-- 	(triquetra.current_slot or "") .. " - " .. winid .. " - " .. vim.api.nvim_get_current_buf() .. " - " .. vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
						vim.notify("Cleaning up triquetra of now unregular window" .. winid ..
							" with current slot: " .. triquetra.current_slot .. " - " ..
							vim.api.nvim_get_current_buf() .. " - (" .. vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()) .. ")",
							vim.log.levels.INFO)
						data.crux[winid] = nil
						clear_window_display_cache(winid)
						goto continue
					elseif #history.get_ordered_buffers() > 0 then
						local candidate_hash = history.get_hash_from_buffer(history.get_ordered_buffers()[1].buf)
						if candidate_hash then
							triquetra.current_slot = candidate_hash
						else
							error(
								"This is impossible. Ordered history buffers should always have a hash associated with it.")
						end
					else
						vim.cmd("enew") -- create a new buffer if nothing is available.
						goto continue
					end
					if vim.bo[cbufnr].buftype == "acwrite" then -- we skip oil buffers, since they are not file buffers.
						goto continue
					end
					::apply::
					candidate_bufnr = history.get_buffer_from_hash(triquetra.current_slot)
					if candidate_bufnr then
						vim.api.nvim_set_current_buf(candidate_bufnr)
						vim.defer_fn(function()
							if vim.api.nvim_buf_is_valid(cbufnr) and vim.api.nvim_buf_is_loaded(cbufnr) then
								vim.cmd("bw! " .. cbufnr)
							end
						end, 100)
					else
						error("This is impossible. Like how the fuck did the current slot become nil???")
					end
				else -- it evolved, just delete it.
					data.crux[winid] = nil
					clear_window_display_cache(winid)
				end
				goto continue
			end
		end

		filepath = history.get_filepath_from_hash(triquetra.secondary_slot)
		if filepath then
			if not filepath:match("^NONAME_") and vim.fn.filereadable(filepath) == 0 then
				triquetra.secondary_slot = nil
			end
		else
			triquetra.secondary_slot = nil
		end

		filepath = history.get_filepath_from_hash(triquetra.ternary_slot)
		if filepath then
			if not filepath:match("^NONAME_") and vim.fn.filereadable(filepath) == 0 then
				triquetra.ternary_slot = nil
			end
		else
			triquetra.ternary_slot = nil
		end

		local pfilehash
		for index = #(triquetra.primary_buffer or {}), 1, -1 do
			pfilehash = triquetra.primary_buffer[index]
			filepath = history.get_filepath_from_hash(pfilehash)

			if filepath then
				if not filepath:match("^NONAME_") and vim.fn.filereadable(filepath) == 0 then
					table.remove(triquetra.primary_buffer, index)
				end
			else
				table.remove(triquetra.primary_buffer, index)
			end
		end
		set_cache_from_window_triquetra(winid)
		::continue::
	end
end

---Swap with secondary buffer in the target window. It actually just jumps to the secondary buffer. 
---
---The BufEnter autocmd does the swapping dynamically, so this function is just a jump.
---
---@param winid WinId The target window ID
---@return nil
function M.swap_with_secondary(winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return
	end

	local cbufnr = history.get_buffer_from_hash(triquetra.current_slot)

	-- check if the current buffer of the window is the triquetra current. If not,
	-- then we just jump to the triquetra current window.
	if cbufnr and cbufnr ~= vim.api.nvim_win_get_buf(winid) then
		vim.notify("Jumped back to windows current buffer.", vim.log.levels.INFO)
		vim.api.nvim_set_current_buf(cbufnr)
		return -- we just jump.
	end

	if triquetra.secondary_slot == nil then
		cbufnr = history.get_buffer_from_hash(triquetra.current_slot)
		if triquetra.ternary_slot ~= nil then
			triquetra.secondary_slot = triquetra.ternary_slot
			triquetra.displacement_secondary_map[triquetra.secondary_slot] =
				triquetra.displacement_ternary_map[triquetra.secondary_slot]
			triquetra.ternary_slot = nil
			vim.notify("Secondary buffer set to ternary slot. Ternary slot graduated.", vim.log.levels.INFO)
		elseif #history.data.ordered.crux >= 2 then
			triquetra.secondary_slot = history.get_hash_from_buffer(history.data.ordered.crux[2].buf)
			vim.notify("Secondary buffer populated from history.", vim.log.levels.INFO)
		else
			vim.notify("Cannot populate secondary slot - insufficent history.", vim.log.levels.WARN)
		end
	else
		if triquetra.current_slot then
			triquetra.displacement_secondary_map[triquetra.current_slot] = triquetra.secondary_slot
			if triquetra.ternary_slot then
				triquetra.displacement_ternary_map[triquetra.current_slot.."-swap"] = triquetra.ternary_slot
			end
		else
			error("It's not okay to have a secondary slot without a current slot.")
		end
		cbufnr = history.get_buffer_from_hash(triquetra.secondary_slot)
		if cbufnr == nil then
			cbufnr = history.reopen_filehash(triquetra.secondary_slot)
			local ui_get_basename = require('cavediver.domains.ui').routines.get_smart_basename
			if cbufnr == nil then
				vim.notify(
					"Removed secondary file not found in filesystem: " .. ui_get_basename(triquetra.secondary_slot),
					vim.log.levels.WARN)
				triquetra.secondary_slot = nil
				loop_sm:to(loop_states.SELF)
				return
			else
				remove_from_closed_buffers(triquetra.secondary_slot)
				vim.notify("File reopened for secondary slot: " .. ui_get_basename(triquetra.secondary_slot),
					vim.log.levels.INFO)
			end
		end
		local cfilehash = history.get_hash_from_buffer(cbufnr)
		if not cfilehash then
			error("This is impossible. Ternary slot should always have a buffer associated with it.")
		end

		local filepath = history.get_filepath_from_hash(cfilehash)

		if filepath and filepath:match("^NONAME_") then
			data.rename_hash_in_triquetras(triquetra.secondary_slot, cfilehash)
		end

		M.reconcile_triquetra(winid, cbufnr)

		vim.api.nvim_set_current_buf(cbufnr)
	end

	loop_sm:to(loop_states.SELF)
end

---Swap with ternary buffer in the target window. It actually just jumps to the ternary buffer.
---
---The BufEnter autocmd does the swapping dynamically, so this function is just a jump.
---
---@param winid WinId The target window ID
---@return nil
function M.swap_with_ternary(winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return
	end

	local cbufnr = history.get_buffer_from_hash(triquetra.current_slot)

	-- check if the current buffer of the window is the triquetra current. If not,
	-- then we just jump to the triquetra current window.
	if cbufnr and cbufnr ~= vim.api.nvim_win_get_buf(winid) then
		vim.notify("Jumped back to windows current buffer.", vim.log.levels.INFO)
		vim.api.nvim_set_current_buf(cbufnr)
		return -- we just jump.
	end


	if triquetra.ternary_slot == nil then
		vim.notify("No ternary buffer to swap with.", vim.log.levels.WARN)
		return
	end

	cbufnr = history.get_buffer_from_hash(triquetra.ternary_slot)
	if cbufnr == nil then
		cbufnr = history.reopen_filehash(triquetra.ternary_slot)
		local ui_get_basename = require('cavediver.domains.ui').routines.get_smart_basename
		if cbufnr == nil then
			vim.notify("Removed ternary file not found in filesystem: " .. ui_get_basename(triquetra.ternary_slot),
				vim.log.levels.WARN)
			triquetra.ternary_slot = nil
			loop_sm:to(loop_states.SELF)
			return
		else
			remove_from_closed_buffers(triquetra.ternary_slot)
			vim.notify("File reopened for ternary slot: " .. ui_get_basename(triquetra.ternary_slot), vim.log.levels
				.INFO)
		end
	end
	local cfilehash = history.get_hash_from_buffer(cbufnr)
	if cfilehash then
		data.rename_hash_in_triquetras(triquetra.ternary_slot, cfilehash)
	else
		error("This is impossible. Ternary slot should always have a buffer associated with it.")
	end
	M.reconcile_triquetra(winid, cbufnr)

	vim.api.nvim_set_current_buf(cbufnr)

	loop_sm:to(loop_states.SELF)
end

---Jump to the target window's primary buffer.
---
---@param winid WinId The target window ID
---@return nil
function M.jump_to_primary(winid)
	local navigation = require("cavediver.domains.navigation")
	local triquetra = data.get_window_triquetra(winid)
	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return
	end
	if navigation.is_cycling() then
		local cycling_origins = history.get_cycling_origins(winid)
		local ui_get_basename = require('cavediver.domains.ui').routines.get_smart_basename

		if not cycling_origins then
			error("This should not happen. Cycling origins not found for window: " .. winid)
		end

		local origin_bufnr = history.get_buffer_from_hash(cycling_origins.current_slot)

		if not origin_bufnr then
			error("This should not happen. Origin buffer not found for current slot: " .. cycling_origins.current_slot)
		end

		vim.api.nvim_set_current_buf(origin_bufnr)
		triquetra.current_slot = cycling_origins.current_slot
		vim.notify("Returned to cycling origin buffer: " .. ui_get_basename(cycling_origins.current_slot),
			vim.log.levels.INFO)
		return
	end
	if (triquetra.primary_buffer[1] == nil) or (not triquetra.primary_enabled) or triquetra.secondary_slot == triquetra.primary_buffer[1] then
		M.swap_with_secondary(winid)
		return
	end

	local cbufnr = history.get_buffer_from_hash(triquetra.primary_buffer[1])
	if cbufnr == nil then
		cbufnr = history.reopen_filehash(triquetra.primary_buffer[1])
		if cbufnr == nil then
			error("Primary buffer not found in filesystem: " .. history.get_filepath_from_hash(triquetra.primary_buffer[1]))
		else
			remove_from_closed_buffers(triquetra.primary_buffer[1])
		end
	end
	if triquetra.current_slot ~= triquetra.primary_buffer[1] then -- We only do displacment if we are not already in the primary buffer.
		triquetra.displacement_ternary_map[triquetra.current_slot.."-swap"] = triquetra.ternary_slot
		triquetra.ternary_slot = triquetra.current_slot
		triquetra.current_slot = triquetra.primary_buffer[1]
	else
		vim.notify("Already in primary buffer, no displacement performed.", vim.log.levels.INFO)
	end

	M.reconcile_triquetra(winid, cbufnr)
	vim.api.nvim_set_current_buf(cbufnr)
end

---Toggle the primary buffer in the target window.
---
---@param winid WinId The target window ID
---@return nil
function M.toggle_primary_buffer(winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		return
	end

	if #triquetra.primary_buffer == 0 then
		triquetra.primary_buffer[1] = triquetra.current_slot
	end
	triquetra.primary_enabled = not triquetra.primary_enabled
	loop_sm:to(loop_states.SELF)
end

---Overwrite the primary buffer in the target window with the current slot.
---
---@param winid WinId The target window ID
---@return nil
function M.set_primary_buffer(winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		return
	end

	if triquetra.primary_buffer[1] == nil then
		triquetra.primary_buffer[1] = triquetra.current_slot
	elseif triquetra.primary_buffer[1] ~= triquetra.current_slot then
		local existing_index = vim.fn.index(triquetra.primary_buffer, triquetra.current_slot)
		if existing_index ~= -1 then
			table.remove(triquetra.primary_buffer, existing_index + 1)
		end
		table.insert(triquetra.primary_buffer, 1, triquetra.current_slot)
		triquetra.primary_enabled = true
	else
		triquetra.primary_enabled = not triquetra.primary_enabled
	end
	loop_sm:to(loop_states.SELF)
end

---A general function to restore from a displacement map.
---
---@param type "ternary"|"secondary" The type of displacement map to restore from
---@param triquetra WindowTriquetra
local function restore_from_displacement_map(type, triquetra)
	local current_relationship = triquetra[type .. "_slot"]
	local remembered_mapping = triquetra["displacement_" .. type .. "_map"]

	local remembered_relationship = remembered_mapping[triquetra.current_slot.."-swap"]

	if remembered_relationship == nil or remembered_relationship == triquetra.ternary_slot then
		remembered_relationship = remembered_mapping[triquetra.current_slot]
	end

	if (remembered_relationship ~= nil) and (history.get_filepath_from_hash(remembered_relationship) ~= nil) and (remembered_relationship ~= current_relationship) then
		if type == "ternary" then
			if remembered_relationship == triquetra.secondary_slot then
				triquetra.secondary_slot = triquetra.ternary_slot
				triquetra.ternary_slot = remembered_relationship
			else
				triquetra.ternary_slot = remembered_relationship
			end
			vim.notify("Restored " .. type .. " slot to: " .. remembered_relationship, vim.log.levels.INFO)
		elseif type == "secondary" then
			if remembered_relationship == triquetra.ternary_slot then
				triquetra.ternary_slot = triquetra.secondary_slot
				triquetra.secondary_slot = remembered_relationship
			else
				triquetra.secondary_slot = remembered_relationship
			end
			vim.notify("Restored " .. type .. " slot to: " .. remembered_relationship, vim.log.levels.INFO)
		end
		triquetra["displacement_" .. type .. "_map"][triquetra.current_slot] = current_relationship
	elseif (remembered_relationship == nil) then
		vim.notify(
			"No " ..
			type ..
			" relationship found for restoration. It means you hadn't displaced a current buffer yet to the " ..
			type .. " slot.", vim.log.levels.WARN)
	elseif history.get_filepath_from_hash(remembered_relationship) == nil then
		error("This impossible error should never happen. Remembered " .. type .. " is not registered in history.")
	else
		error("This is impossible. Remembered " ..
			type .. " is the same as current " .. type .. ". It should be different for flip flop.")
	end
	loop_sm:to(loop_states.SELF)
end


---Restore to the ternary of the current buffer before being displaced into ternary slot.
---
---@param winid WinId The target window ID
---@return nil
function M.restore_triquetra_ternary(winid)
	local triquetra = data.get_window_triquetra(winid)
	if triquetra then
		restore_from_displacement_map("ternary", triquetra)
	end
end

---Restore to the secondary of the current buffer before being displaced into ternary slot.
---
---@param winid WinId The target window ID
---@return nil
function M.restore_triquetra_secondary(winid)
	local triquetra = data.get_window_triquetra(winid)
	if triquetra then
		restore_from_displacement_map("secondary", triquetra)
	end
end

function M.repopulate_window_relationships()
	local set_cache_from_window_triquetra = require("cavediver.domains.ui").set_cache_from_window_triquetra
	data.crux = {}
	data.current_window = {}

	for _, winid in pairs(vim.api.nvim_list_wins()) do
		local current_slot = history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid))
		if current_slot == nil then
			vim.notify("skipping window " .. winid .. " because it has no registered buffer.", vim.log.levels.INFO)
			goto continue
		end

		data.crux[winid] = {
			current_slot = current_slot,
			secondary_slot = nil,
			ternary_slot = nil,
			primary_buffer = {},
			displacement_secondary_map = {},
			displacement_ternary_map = {},
			primary_enabled = false,
		}
		set_cache_from_window_triquetra(winid)
		::continue::
	end
end

return M
