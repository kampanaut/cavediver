---Storage domain data structures for session persistence.
---
---This module contains the data structures for managing session persistence,
---including file paths, session metadata, and serialization formats.

local M = {}

---@class StorageData
---@field session_file string Default session file path
---@field auto_save_interval number Auto-save interval in milliseconds
---@field last_save_time number Timestamp of last save operation
---@field session_metadata table Session metadata including version and timestamp
---@field serialization_format string Format for data serialization (json, lua, etc.)

---Auto-save interval in milliseconds (5 minutes default)
---@type number
M.auto_save_interval = 300000

---Timestamp of last save operation
---@type number
M.last_save_time = 0

---Session metadata including version and creation info
---@type table
M.session_metadata = {
    version = "1.0.0",
    created_at = nil,
    last_modified = nil,
    domains = {},
}

---Serialization format for session data
---@type string
M.serialization_format = "json"

---Session data structure template
---@type table
M.session_template = {
    metadata = {
        version = "1.0.0",
        created_at = nil,
        last_modified = nil,
        nvim_version = nil,
    },
    domains = {
        history = {},
        navigation = {},
        window = {},
        ui = {},
    },
}

---Error state information
---@type table
M.error_state = {
    last_error = nil,
    error_count = 0,
    last_error_time = nil,
}

return M
