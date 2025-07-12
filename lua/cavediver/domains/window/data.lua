---Window domain data structures and state management.
---@alias WinId number -- Window ID type alias
---
---@class WindowState Per-window buffer relationship data
---@field altbufs table<WinId, WindowTriquetra> Window ID to buffer relationships mapping
---@field current_window number Currently active window ID

---@class WindowTriquetra Triquetra buffer relationships for a single window
---@field current_slot Filehash The current slot filename. Whatever is currently shown in the window.
---@field secondary_slot Filehash|nil User-controlled "waiting" slot, user can store what buffer is in the secondary slot.
---@field ternary_slot Filehash|nil Auto-populated waiting slot, the "previous" current.
---@field primary_buffer Filehash|nil The file buffer which can take its place in one of the three at a time.
---@field primary_enabled boolean Whether the primary buffer is enabled in this triquetra.
---@field displacement_ternary_map table<Filehash, Filehash> -- This is filename's ternary before it got displaced.
---@field displacement_secondary_map table<Filehash, Filehash> -- This is filename's secondary before it got displaced.

---@type table<number, WindowTriquetra>
local crux = {}

---Create a new empty window buffer relationship.
---
---@param winid number Window ID to create the relationship for
local function create_empty_window_buffer_relationship(winid)
	local history = require('cavediver.domains.history')
	local current_slot = history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid))
	if not current_slot then
		error("Cannot create empty window buffer relationship: The window has an unregistered buffer.")
	end
    crux[winid] = {
		current_slot = current_slot,
		secondary_slot = nil,
		ternary_slot = nil,
		primary_buffer = nil,
		displacement_ternary_map = {},
		displacement_secondary_map = {},
		primary_enabled = false,
    }
end

---Get or create window buffer relationships for a window.
---
---@param winid number Window ID to get relationships for
---@return WindowTriquetra|nil relationship The window's buffer relationships
local function get_window_relationships(winid)
    if not crux[winid] then
		if require('cavediver.domains.history').get_hash_from_buffer(vim.api.nvim_get_current_buf()) then 
			-- print("Made triquetra for window " .. winid)
			create_empty_window_buffer_relationship(winid)
		else
			return nil
		end
    end
    return crux[winid]
end

---Rename a hash to a new hash across all window triquetras.
---
---Updates all references to old_hash in triquetra slots and displacement maps.
---
---@param old_hash Filehash The hash to be renamed
---@param new_hash Filehash The new hash to replace it with
local function rename_hash_in_triquetras(old_hash, new_hash)
    for _, triquetra in pairs(crux) do
        -- Update slots
        if triquetra.current_slot == old_hash then
            triquetra.current_slot = new_hash
        end
        if triquetra.secondary_slot == old_hash then
            triquetra.secondary_slot = new_hash
        end
        if triquetra.ternary_slot == old_hash then
            triquetra.ternary_slot = new_hash
        end
        if triquetra.primary_buffer == old_hash then
            triquetra.primary_buffer = new_hash
        end
        
        -- Update displacement maps (keys)
        if triquetra.displacement_ternary_map[old_hash] then
            local displaced_value = triquetra.displacement_ternary_map[old_hash]
            triquetra.displacement_ternary_map[old_hash] = nil
            triquetra.displacement_ternary_map[new_hash] = displaced_value
        end
		if triquetra.displacement_ternary_map[old_hash.."-swap"] then
            local displaced_value = triquetra.displacement_ternary_map[old_hash.."-swap"]
            triquetra.displacement_ternary_map[old_hash.."-swap"] = nil
            triquetra.displacement_ternary_map[new_hash.."-swap"] = displaced_value
		end
        if triquetra.displacement_secondary_map[old_hash] then
            local displaced_value = triquetra.displacement_secondary_map[old_hash]
            triquetra.displacement_secondary_map[old_hash] = nil
            triquetra.displacement_secondary_map[new_hash] = displaced_value
        end

        -- Update displacement maps (values)
        for hash, displaced_hash in pairs(triquetra.displacement_ternary_map) do
            if displaced_hash == old_hash then
                triquetra.displacement_ternary_map[hash] = new_hash
            end
        end
        for hash, displaced_hash in pairs(triquetra.displacement_secondary_map) do
            if displaced_hash == old_hash then
                triquetra.displacement_secondary_map[hash] = new_hash
            end
        end
    end
end

return {
    crux = crux,
    current_window = vim.api.nvim_get_current_win(),
    create_empty_window_buffer_relationship = create_empty_window_buffer_relationship,
    get_window_triquetra = get_window_relationships,
    rename_hash_in_triquetras = rename_hash_in_triquetras,
}
