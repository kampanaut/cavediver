local helper = require('engine.helpers')

---State machine implementation for managing states, transitions, and hooks.
---
---This class provides a complete state machine system with:
---- State registration and validation
---- Transition control with wildcard support
---- Hook system for transition callbacks
---- General hooks for all transitions
---- Transition history tracking
---
---@class StateMachine
---@field name string The name of the StateMachine
---@field current_state stateName The current active state
---@field states stateRegistry Registry of registered states with enable/disable status
---@field transitions transitionRegistry Registry of transitions with enable/disable status
---@field bindings transitionBindingsRegistry Maps transition patterns to hook arrays
---@field hooks tHooksRegistry Registry of all transition-specific hooks by name
---@field general_hooks gHooksRegistry Array of hooks that run on all transitions
---@field history transitionName[] History of executed transitions
local StateMachine = {
	-- The starting state of the StateMachine
	---@type stateName
	current_state = "",

	-- We record the states to validate upcoming transitions
	-- `["<state>"] = true | false.`
	-- `true` if it is turned on, `false` otherwise.
	---@type stateRegistry
	states = {},

	-- the transitions are written with `<previous>-><next>`
	-- `["<transition>"] = true | false`
	-- `true` if it is turned on, `false` otherwise.
	---@type transitionRegistry
	transitions = {},

	-- (transitionPattern <-> tHook) pair.
	-- ```lua
	-- ["<previous>-><next>"] = {
	--	{
	--     class = 2,
	--     enabled = true,
	--     name = "some_hook",
	--     function = function()...end
	--	},
	-- },
	-- ["*->tracking"] = {
	--	{
	--     class = 1,
	--     enabled = true,
	--     name = "some_hook_2",
	--     function = function()...end
	--	},
	-- },
	-- ["tracking->*"] = {
	--	{
	--     class = 2,
	--     enabled = true,
	--     name = "some_hook_4",
	--     function = function()...end
	--	},
	--	{...}
	-- },
	-- ```
	-- Can support wildcards as well, e.g. `*->tracking` or `tracking->*`
	---@type transitionBindingsRegistry
	bindings = {},

	-- ```lua
	-- {
	--	["<name1>"] = {
	--		class = 2,
	--		enabled = true,
	--		name = "<name1>",
	--		function = function()...end
	--	},
	--	["<name2>"] = {
	--		class = 1,
	--		enabled = true,
	--		name = "<name2>",
	--		function = function()...end
	--	}
	-- }
	-- ```
	-- Registry of all transition-specific hooks.
	---@type tHooksRegistry
	hooks = {},

	-- ```lua
	-- {
	--	{
	--		class = 4,
	--		enabled = true,
	--		name = "general_hook",
	--		function = function()...and
	--	}
	-- }
	-- ```
	-- Just like `StateMachine.hooks` but goes for all transitions.
	-- Formally it's for transition pattern like this, `*->*`. It executes before or after the
	-- the normal hooks.
	---@type gHooksRegistry
	general_hooks = {},

	-- The history of `transitions`.
	---@type transitionName[]
	history = {},

	---@type table<transitionMode, boolean>
	transition_modes = {}
}


---Get the current active state.
---@return stateName current_state The name of the currently active state
function StateMachine:state()
	return self.current_state
end

---Register a new state in the state machine.
---
---States must be registered before they can be used in transitions.
---State names cannot be "*" (reserved for wildcards) or contain "->" (reserved for transitions).
---
---@param state_name stateName The name of the state to register
---@return nil
function StateMachine:register_state(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if self:is_state_name_valid(state_name) then
		if self.states[state_name] then
			error("State '" .. state_name .. "' is already registered")
		end
		self.states[state_name] = true
	end
end

---Register a new mode for transitions. Modes are optional tags that can be used to filter hooks.
---By default there are no modes, but you can register any number of them at any time as well, since
---hooks store by string patterns. But make sure those pattern contain only registered modes.
---@param mode transitionMode The name of the mode to register
---@return nil
function StateMachine:register_mode(mode)
	self.transition_modes[mode] = true
end

---Unregister a state and cascade delete all related transitions.
---
---Removes the state and automatically cleans up all transitions and bindings
---that reference this state (both as source and destination).
---
---@param state_name stateName The name of the existing state to remove
---@return nil
function StateMachine:unregister_state(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if self.states[state_name] then
		for transition_name, _ in pairs(self.transitions) do
			local previous, next = helper.parse_transition_name(transition_name)

			if previous == state_name then
				self.transitions[transition_name] = nil
			elseif next == state_name then
				self.transitions[transition_name] = nil
			end
		end

		for transition_pattern, _ in pairs(self.bindings) do
			local previous, next = helper.parse_transition_name(transition_pattern)

			if previous == state_name then
				self.bindings[transition_pattern] = nil
			elseif next == state_name then
				self.bindings[transition_pattern] = nil
			end
		end

		self.states[state_name] = nil
	end
end

---Validate if a state name follows the required naming rules.
---
---State names must not be "*" (reserved for wildcards) and cannot contain "->"
---(reserved for transition delimiter). This is called internally during state registration.
---
---@param state_name stateName The name of the state to validate
---@return true is_valid Always returns true if validation passes, otherwise throws error
function StateMachine:is_state_name_valid(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if state_name == "*" then
		error("Cannot register \"*\" as a state name — reserved for wildcards")
	end
	if string.find(state_name, "->") then
		error("State name cannot contain '->' - reserved for transition delimiter")
	end
	return true
end

---Check if a state is registered in the state machine.
---
---Returns true if the state has been registered using register_state(),
---regardless of whether it's currently enabled or disabled.
---
---@param state_name stateName The name of the state to check
---@return boolean is_registered True if the state is registered, false otherwise
function StateMachine:is_state_registered(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if self.states[state_name] == nil then
		return false
	else
		return true
	end
end

---Check if a state is currently enabled.
---
---States can be enabled or disabled after registration. Only enabled states
---can be used as destinations in transitions. This checks both registration
---and enabled status.
---
---@param state_name stateName The name of the state to check
---@return boolean is_enabled True if the state is registered and enabled, false otherwise
function StateMachine:is_state_enabled(state_name)
	helper.validate_state_name_param(state_name, "state_name")
	if not (self.states[state_name] ~= nil and self:is_state_name_valid(state_name)) then
		return false
	else
		return self.states[state_name] == true
	end
end

---Register a hook to execute during state transitions.
---
---Hooks are functions that execute when transitioning between states. If the transition
---doesn't exist, it will be created automatically (if both states are registered).
---Hook names must be unique across the state machine.
---
---@param from_state stateName Source state for the transition (supports wildcards "*")
---@param to_state stateName Destination state for the transition (supports wildcards "*")
---@param name string Unique name for this hook
---@param func hookFunction? Hook function to execute (required for new hooks)
---@param priority number? Priority class for execution order, lower = higher priority (required for new hooks)
---@param enabled boolean? Whether the hook is initially enabled (required for new hooks)
---@param mode_filter transitionModePattern? Optional pattern to filter which modes this hook applies to
---@return boolean success True if hook was registered successfully
function StateMachine:on(from_state, to_state, name, func, priority, enabled, mode_filter)
	-- Validate required parameters
	helper.validate_state_name_param(from_state, "from_state")
	helper.validate_state_name_param(to_state, "to_state")
	helper.validate_param(name, "name", "string", false)
	if name == "" then
		error("Parameter 'name' cannot be empty string")
	end
	-- Validate optional parameters
	helper.validate_param(func, "func", "function", true)
	helper.validate_param(priority, "priority", "number", true)
	helper.validate_param(enabled, "enabled", "boolean", true)
	helper.validate_mode_pattern(mode_filter, self)
	if priority and type(priority) ~= "number" then
		error("Parameter 'priority' must be a number, got " .. type(priority))
	end

	---@type transitionPattern
	local transition_pattern = from_state .. "->" .. to_state

	---@type transitionName[]
	local transition_names = helper.parse_transition_pattern(transition_pattern, self)

	---@type tHook
	local hook
	if self.hooks[name] then
		hook = self.hooks[name]
		if priority then
			hook.class = priority
		end
		if enabled ~= nil then
			hook.enabled = enabled
		end
		if func then
			hook.func = func
		end
		if mode_filter then
			hook.mode_filter = mode_filter
		else
			hook.mode_filter = "*"
		end
	else
		-- For new hooks, all parameters are required
		if not (func and priority and enabled ~= nil) then
			error("For new hooks, 'func', 'priority', 'enabled', and 'mode_filter' parameters are required")
		end

		mode_filter = mode_filter or "*"
		hook = {
			name = name,
			class = priority,
			enabled = enabled,
			func = func,
			mode_filter = mode_filter
		}
	end

	-- loop over the transition names and assign the hook
	for _, transition_name in ipairs(transition_names) do
		from_state, to_state = helper.parse_transition_name(transition_name)
		if self.transitions[transition_name] == nil then
			if
				self:is_state_name_valid(from_state) and self:is_state_name_valid(to_state) and
				self:is_state_registered(from_state) and self:is_state_registered(to_state)
			then
				self.transitions[transition_name] = true
			else
				error("Cannot register hook for invalid transition state endpoints: " .. transition_name)
			end
		end

		if self.bindings[transition_name] == nil then
			self.bindings[transition_name] = {}
		end

		if not vim.tbl_contains(self.bindings[transition_name], hook) then
			table.insert(self.bindings[transition_name], hook)
		end
	end

	if self.hooks[hook.name] == nil then
		self.hooks[hook.name] = hook
	end
	return true
end

---Remove a hook from specific transitions.
---
---Removes the hook from the specified transition pattern but keeps the hook
---registered in the state machine. The hook can still be attached to other transitions.
---Use unregister_hook() to completely remove a hook from the state machine.
---
---@param from_state stateName Source state for the transition (supports wildcards "*")
---@param to_state stateName Destination state for the transition (supports wildcards "*")
---@param name string Name of the hook to remove from these transitions
---@return nil
function StateMachine:off(from_state, to_state, name)
	if self.hooks[name] == nil then
		error("Cannot remove hook with name '" .. name .. "': not found", vim.log.levels.WARN)
	end

	---@type transitionPattern
	local transition_pattern = from_state .. "->" .. to_state

	---@type transitionName[]
	local transition_names = helper.parse_transition_pattern(transition_pattern, self)

	-- we are going to loop over the transition_names, and and remove the hooks that has name same as the argument name.
	for _, transition_name in ipairs(transition_names) do
		if self.bindings[transition_name] == nil then
			goto continue
		end

		for i, hook in ipairs(self.bindings[transition_name]) do
			if hook.name == name then
				table.remove(self.bindings, i)
			end
		end

		::continue::
	end
end

---Completely remove a hook from the state machine.
---
---Removes the hook from all transitions and unregisters it from the state machine.
---After calling this method, the hook name becomes available for reuse.
---This is equivalent to calling off("*", "*", hook_name) and then removing the hook registration.
---
---@param hook_name string Name of the hook to completely remove
---@return nil
function StateMachine:unregister_hook(hook_name)
	if self.hooks[hook_name] == nil then
		error("hook '" .. hook_name .. "' is not registered")
	end

	StateMachine:off("*", "*", hook_name)

	self.hooks[hook_name] = nil
end

---Enable a hook to execute during transitions.
---
---Enables a previously registered hook that may have been disabled.
---The hook will start executing during its registered transitions.
---
---@param name string Name of the hook to enable
---@return nil
function StateMachine:enable_hook(name)
	helper.validate_param(name, "name", "string", false)
	if self.hooks[name] == nil then
		error("Cannot enable hook: '" .. name .. "': not found", vim.log.levels.WARN)
	end

	self.hooks[name].enabled = true
end

---Disable a hook from executing during transitions.
---
---Disables a previously registered hook without removing it from the state machine.
---The hook will stop executing but remains registered and can be re-enabled later.
---
---@param name string Name of the hook to disable
---@return nil
function StateMachine:disable_hook(name)
	helper.validate_param(name, "name", "string", false)
	if self.hooks[name] == nil then
		error("Cannot disable hook: '" .. name .. "': not found", vim.log.levels.WARN)
	end

	self.hooks[name].enabled = false
end

---Enable transitions to allow state changes.
---
---Enables previously registered transitions that may have been disabled.
---Supports wildcards for enabling multiple transitions at once.
---Only enabled transitions can be executed via the to() method.
---
---@param from_state stateName Source state for transitions to enable (supports wildcards "*")
---@param to_state stateName Destination state for transitions to enable (supports wildcards "*")
---@return nil
function StateMachine:enable_transition(from_state, to_state)
	---@type transitionPattern
	local transition_pattern = from_state .. "->" .. to_state

	---@type transitionName[]
	local transition_names = helper.parse_transition_pattern(transition_pattern, self)

	for _, transition_name in ipairs(transition_names) do
		if self.transitions[transition_name] then
			self.transitions[transition_name] = true
		end
	end
end

---Disable transitions to prevent state changes.
---
---Disables previously registered transitions without removing them.
---Supports wildcards for disabling multiple transitions at once.
---Disabled transitions cannot be executed via the to() method.
---
---@param from_state stateName Source state for transitions to disable (supports wildcards "*")
---@param to_state stateName Destination state for transitions to disable (supports wildcards "*")
---@return nil
function StateMachine:disable_transition(from_state, to_state)
	---@type transitionPattern
	local transition_pattern = from_state .. "->" .. to_state

	---@type transitionName[]
	local transition_names = helper.parse_transition_pattern(transition_pattern, self)

	for _, transition_name in ipairs(transition_names) do
		if self.transitions[transition_name] then
			self.transitions[transition_name] = false
		end
	end
end

---Transition the state machine to a new state.
---
---Executes all registered hooks for the transition in priority order.
---The transition must be registered and enabled. Context data is passed
---through all hooks in the execution pipeline.
---
---@param next_state stateName The state to transition to
---@param context_arg transitionContextArg? Optional mutable data passed to all hooks. `caller` is reserved.
---@param mode transitionMode?
---@return nil
function StateMachine:to(next_state, context_arg, mode)
	helper.validate_state_name_param(next_state, "next_state")
	helper.validate_param(context_arg, "context", "table", true)
	helper.validate_mode_pattern(mode, self)
	if not self:is_state_registered(next_state) then
		error("Cannot transition to unregistered state: " .. next_state, vim.log.levels.ERROR)
	end

	local context = vim.deepcopy(context_arg or {})
	---@cast context transitionContext
	context.caller = self.name
	context.mode = mode or "*" -- this is not run all hooks, but only run hooks that aren't registered with a mode.

	---@type transitionName
	local transition_name = self:state() .. "->" .. next_state
	-- Check if transition is enabled
	if self.transitions[transition_name] == nil then
		error("Transition '" .. transition_name .. "' is not registered")
	end
	if self.transitions[transition_name] == false then
		error("Transition '" .. transition_name .. "' is disabled")
	end

	helper.execute_transition(self:state(), next_state, context.mode, context, self)
	self.current_state = next_state
end

return StateMachine
