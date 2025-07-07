---Storage domain initialization and API.
---
---The storage domain manages session persistence across all domains,
---providing save/load functionality and automatic state preservation.

local states = require('domains.storage.states')
local data = require('domains.storage.data')
local routines = require('domains.storage.routines')
local storageSM = require('domains.storage.sm')

require('domains.storage.hooks')

local M = {
	states = states,
	data = data,
	routines = routines,
	sm = storageSM,
}

---Save current session to file.
---
---@param cwd string|nil
---@return nil
function M.save_session(cwd)
	if cwd then
		storageSM:to(states.SAVING, { cwd = cwd })
		storageSM:to(states.IDLE, { cwd = cwd })
	else
		error("CWD is required to save session")
	end
end

---Load session from file.
---
---@param cwd string|nil
---@return nil
function M.load_session(cwd)
	if cwd then
		storageSM:to(states.LOADING, { cwd = cwd })
		storageSM:to(states.IDLE, { cwd = cwd })
	else
		error("CWD is required to save session")
	end
end

return M
