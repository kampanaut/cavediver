---StateMachine factory for creating and managing multiple state machine instances.
---
---This module provides a factory pattern for creating independent state machine instances
---with clean initialization and instance management. Each instance gets its own state,
---transitions, hooks, and history while sharing the same StateMachine class methods.
---
---@class StateMachineFactory
---@field private instances table<string, StateMachine> Registry of created state machine instances

local StateMachine = require('cavediver.engine.state-machine')

local StateMachineFactory = {}
local instances = {}

---Create a new state machine instance with the given name.
---
---Creates a fresh state machine instance using metatable inheritance from the StateMachine class.
---Each instance has its own independent state, transitions, hooks, and history.
---Instance names must be unique across the factory.
---
---@param name string Unique name for the state machine instance
---@return StateMachine instance The newly created state machine instance
---@error "StateMachine already exists" if name is already in use
function StateMachineFactory:create(name)
	if instances[name] then
		error("StateMachine '" .. name .. "' already exists")
	end

	local instance = setmetatable({
		name = name,
		current_state = {},
		states = {},
		transitions = {},
		bindings = {},
		hooks = {},
		general_hooks = {},
		history = {},
	}, { __index = StateMachine })


	instances[name] = instance
	return instance
end

---Retrieve an existing state machine instance by name.
---
---Returns the state machine instance that was previously created with the given name.
---Returns nil if no instance exists with that name.
---
---@param name string Name of the state machine instance to retrieve
---@return StateMachine|nil instance The state machine instance, or nil if not found
function StateMachineFactory:get(name)
	return instances[name]
end

---Get a list of all registered state machine instance names.
---
---Returns an array of strings containing the names of all state machine instances
---that have been created and are currently registered with the factory.
---
---@return string[] names Array of state machine instance names
function StateMachineFactory:list()
	return vim.tbl_keys(instances)
end

return StateMachineFactory
