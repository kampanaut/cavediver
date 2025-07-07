---History domain data structures and state management.
---@alias Filehash string -- File hash type alias
---@alias Bufnr number -- Buffer number type alias
---@alias Filepath string -- File path type alias
---
---@class HistoryState
---@field crux table<Filehash, Bufnr> File hash to access time mapping (hash → timestamp)
---@field ordered OrderedHistory Ordered buffer lists for recency-based operations
---@field history_index number Next available timestamp for buffer access tracking
---@field hash_buffer_registry BuffersRegistry Bidirectional file hash ↔ buffer number mappings
---@field hash_filepath_registry FilepathRegistry Bidirectional file hash ↔ file path mappings
---@field cycling_origins table<number, WindowSnapshot> Window states before cycling began (winid → snapshot)
---@field closed_buffers Filehash[] Stack of closed buffer filehashes that can be reopened via hash_filepath_registry
---@field noname_content table<Filepath, NoNameBufferContent> Content storage for [No Name] buffers

---@class NoNameBufferContent [No Name] buffer content and metadata for restoration
---@field lines string[] Buffer content as array of lines
---@field filetype string Buffer filetype for syntax highlighting
---@field cursor {[1]:number, [2]:number} Cursor position as {row, col} tuple

---@class BufferHistoryItem Array element: {buf=number, time=number}
---@field buf number Buffer number
---@field time number Access timestamp from history_index

---@class OrderedHistory
---@field crux BufferHistoryItem[] Buffers ordered by recency (most recent first)
---@field nonharpooned BufferHistoryItem[] Non-harpooned buffers ordered by recency

---@class BuffersRegistry
---@field buffers table<Filehash, Bufnr> File hash → buffer number lookup
---@field hashes table<Bufnr, Filehash> Buffer number → file hash lookup

---@class FilepathRegistry
---@field filepaths table<Filehash, Filepath> File hash → file paths lookup
---@field hashes table<Filepath, Filehash> File path → file hash lookup

---@alias WindowSnapshot WindowTriquetra Captured window state before cycling for restoration

local HistorySM = require('cavediver.domains.history.sm')
local states = require("cavediver.domains.history.states")

---@type HistoryState
local corpus = {
	-- Function to check if history tracking is detached (legacy compatibility)
	history_detached = function()
		return HistorySM:state() == states.DETACHED
	end,
	-- Core buffer access history: file_hash → access_time
	crux = {},
	-- Ordered buffer lists for recency-based operations
	ordered = {
		crux = {},        -- All buffers ordered by recency
		nonharpooned = {} -- Non-harpooned buffers ordered by recency
	},
	-- Monotonic timestamp counter for buffer access ordering
	history_index = 1,
	-- Bidirectional file hash ↔ buffer number mappings
	hash_buffer_registry = {
		buffers = {}, -- hash → buffer
		hashes = {}   -- buffer → hash
	},
	hash_filepath_registry = {
		filepaths = {},
		hashes = {}
	},
	-- Window states captured before cycling for restoration
	cycling_origins = {}, -- cycling_origins
	-- Stack of closed buffer filenames that can be reopened
	closed_buffers = {},
	-- Content storage for [No Name] buffers (identifier → content)
	noname_content = {},
}
return corpus
