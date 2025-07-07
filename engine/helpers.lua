local M = {}

function M.get_keys(tbl)
	local keys = {}
	for k, _ in pairs(tbl) do
		table.insert(keys, k)
	end
	return keys
end

-- Execute the transition.
---@param from_state stateName
---@param to_state stateName
---@param context transitionContext
---@param mode transitionMode
---@param statemachine StateMachine
function M.execute_transition(from_state, to_state, mode, context, statemachine)
	
	-- Get the pipeline of hooks to execute for this transition
	local pipeline = M.compute_transition_pipeline(from_state, to_state, mode, statemachine)
	
	-- Add transition to history
	local transition_name = from_state .. "->" .. to_state
	table.insert(statemachine.history, transition_name)
	
	-- print("Executing transition: " .. transition_name)
	-- for index, hook in ipairs(pipeline) do
	-- 	print("[" .. index .. "] Hook: " .. hook.name .. " (class: " .. hook.class .. ", enabled: " .. tostring(hook.enabled) .. ")")
	-- end
	-- print("Executing transition end")
	---Execute each hook in the pipeline
	for _, hook in ipairs(pipeline) do
		if hook.enabled then
			-- Call the hook function with the transition context
			-- The context is mutable and passed through the entire pipeline
			local success, error_msg = pcall(hook.func, context, from_state, to_state)
			
			if not success then
				vim.notify(
					"Hook '" .. hook.name .. "' failed during transition " .. transition_name .. ": " .. error_msg,
					vim.log.levels.ERROR
				)
			end
		end
	end
end

-- Create and return the pipeline queue for the desired transaction.
---@param from_state stateName
---@param to_state stateName
---@param mode transitionMode
---@param statemachine StateMachine
function M.compute_transition_pipeline(from_state, to_state, mode, statemachine)
	local pipeline = {}
	
	-- Get transition name and collect hooks
	local transition_name = from_state .. "->" .. to_state
	local hooks_to_execute = {}
	
	-- Get hooks for this exact transition (wildcards already expanded during registration)
	if statemachine.bindings[transition_name] then
		for _, hook in ipairs(statemachine.bindings[transition_name]) do
			if hook.enabled and M.should_execute_hook(statemachine, mode, hook) then
				table.insert(hooks_to_execute, hook)
			end
		end
	end

	-- Sort hooks by class (priority) - lower class number = higher priority
	table.sort(hooks_to_execute, function(a, b)
		return a.class < b.class
	end)
	
	-- Add general hooks that run before normal hooks
	for _, hook in ipairs(statemachine.general_hooks) do
		if hook.enabled and hook.type == "before" then
			table.insert(pipeline, 1, hook) -- Insert at beginning
		end
	end
	
	-- Add transition-specific hooks
	for _, hook in ipairs(hooks_to_execute) do
		table.insert(pipeline, hook)
	end
	
	-- Add general hooks that run after normal hooks
	for _, hook in ipairs(statemachine.general_hooks) do
		if hook.enabled and hook.type == "after" then
			table.insert(pipeline, hook) -- Insert at end
		end
	end
	
	return pipeline
end

-- Parse a state set like "{state1,state2,state3}" or a single state
-- Invalid {*,state1}, and {*}
---@param state_part string
---@return string[]
local function parse_set_pattern(state_part)
	if string.sub(state_part, 1, 1) == "{" and string.sub(state_part, -1) == "}" then
		-- Parse state set: {state1,state2,state3}
		local inner = string.sub(state_part, 2, -2) -- Remove { }
		local states = {}
		for state in string.gmatch(inner, "[^,]+") do
			local trimmed = vim.trim(state)
			if trimmed == "*" then 
				error("Wildcard '*' cannot be used in state sets. Use '*' as a standalone state instead.")
			end
			table.insert(states, vim.trim(state))
		end
		return states
	else
		-- Single state or wildcard
		return {state_part}
	end
end

-- Get the from_state and to_state from the transitionPattern. It will return 
-- a transitionName[] table from the unpacked pattern.
---@param transition_pattern transitionPattern
---@param statemachine StateMachine
---@return transitionName[]
function M.parse_transition_pattern(transition_pattern, statemachine)
	local from_state, to_state = M.parse_transition_name(transition_pattern)
	local transition_names = {}
	-- Parse from and to state sets
	local from_states = parse_set_pattern(from_state)
	local to_states = parse_set_pattern(to_state)
	-- Expand state sets and wildcards
	for _, from in ipairs(from_states) do
		for _, to in ipairs(to_states) do
			if from == "*" and to == "*" then
				-- *->* matches all possible transitions
				for state1, _ in pairs(statemachine.states) do
					for state2, _ in pairs(statemachine.states) do
						table.insert(transition_names, state1 .. "->" .. state2)
					end
				end
			elseif from == "*" then
				-- *->state matches all transitions to specific state
				for state, _ in pairs(statemachine.states) do
					table.insert(transition_names, state .. "->" .. to)
				end
			elseif to == "*" then
				-- state->* matches all transitions from specific state
				for state, _ in pairs(statemachine.states) do
					table.insert(transition_names, from .. "->" .. state)
				end
			else
				-- Exact transition match
				table.insert(transition_names, from .. "->" .. to)
			end
		end
	end
	
	return transition_names
end

-- Get the from_state to to_state from the transition name. It will return a tuple
-- from_state and to_state.
---@param transition_name transitionName
---@return stateName from_state, stateName to_state
function M.parse_transition_name(transition_name)
	local separator_pos = string.find(transition_name, "->")
	if not separator_pos then
		error("Invalid transition name format: " .. transition_name .. " (expected format: 'from->to')")
	end
	
	local from_state = string.sub(transition_name, 1, separator_pos - 1)
	local to_state = string.sub(transition_name, separator_pos + 2)
	
	return from_state, to_state
end

-- Validate a parameter's type and existence.
---@param param any The parameter value to validate
---@param param_name string The name of the parameter for error messages
---@param expected_type string The expected Lua type ("string", "number", "function", etc.)
---@param allow_nil boolean Whether nil values are allowed for this parameter
function M.validate_param(param, param_name, expected_type, allow_nil)
	if not allow_nil and param == nil then
		error("Parameter '" .. param_name .. "' cannot be nil")
	end
	if param ~= nil and type(param) ~= expected_type then
		error("Parameter '" .. param_name .. "' must be of type " .. expected_type .. ", got " .. type(param))
	end
end

-- Validate a state name parameter with state-specific rules.
---@param state_name any The state name value to validate
---@param param_name string The name of the parameter for error messages
function M.validate_state_name_param(state_name, param_name)
	M.validate_param(state_name, param_name, "string", false)
	if state_name == "" then
		error("Parameter '" .. param_name .. "' cannot be empty string")
	end
end

-- Returns a table of transition modes that match the mode_filter.
--
---@param mode_filter transitionModePattern
---@param statemachine StateMachine
---@return transitionMode[]
function M.parse_mode_filter(mode_filter, statemachine)
	if vim.trim(mode_filter) == "*" then
		return M.get_keys(statemachine.transition_modes)
	end

	local result = parse_set_pattern(mode_filter)
	return result
end



-- Validate if mode pattern contains only registered modes.
--
---@param mode_filter transitionModePattern?
---@param statemachine StateMachine
---@return boolean
function M.validate_mode_pattern(mode_filter, statemachine)
	if mode_filter == nil then
		return false
	end

	-- no hook will be created with unregistered modes.
	for _, mode in ipairs(M.parse_mode_filter(mode_filter, statemachine)) do
		local transition_modes = M.get_keys(statemachine.transition_modes)
		if not vim.tbl_contains(transition_modes, mode) then
			error("Mode '" .. mode .. "' is not registered")
		end
	end
	return true
end

-- Determines if a state is part of mode
---@param transition_mode transitionMode
---@param statemachine StateMachine
---@param hook tHook
---@return boolean is_mode
function M.should_execute_hook(statemachine, transition_mode, hook)
	if hook.enabled == false then
		return false
	end
	if transition_mode == "*" then
		if hook.mode_filter == transition_mode then
			return true
		else
			return false
		end
	elseif hook.mode_filter == "*" then
			return true
	end

	--- otherwise, hook.mode_filter is mode_filter pattern, which can be a single mode or a set of modes.
	if hook.mode_filter then
		if #M.get_keys(statemachine.transition_modes) == 0 then
			error("This state machine doesn't have any transition modes registered. ")
		end

		local expanded_filter = M.parse_mode_filter(hook.mode_filter, statemachine)
		-- print(transition_mode)
		-- print(hook.name)
		-- print_table(expanded_filter)
		-- print_table(M.get_keys(statemachine.transition_modes))
		-- validate if input transition_mode is registered and also check if hook should be executed if it contains transition_mode
		if vim.tbl_contains(M.get_keys(statemachine.transition_modes), transition_mode) then
			if vim.tbl_contains(expanded_filter, transition_mode) then
				-- print("true")
				return true
			else
				-- print("false")
				return false
			end
		else
			error("Transition mode '" .. transition_mode .. "' is not registered in this state machine.")
		end
	else
		return true -- default to true if no mode_filter is set
	end
end

return M
