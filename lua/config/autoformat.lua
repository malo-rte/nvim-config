-- config/autoformat.lua
--
-- Layered "format on save" decision, remembered across sessions. conform.nvim's
-- format_on_save asks M.enabled(bufnr) at save time. Precedence, most specific
-- first:
--   1. per-file override    (<leader>uf) -- machine-local state
--   2. per-project override (<leader>uF) -- machine-local state, keyed by root
--   3. committed repo marker  <root>/.autoformat  -- team-shared; file content
--      "off"/"false"/"no"/"0" => off, otherwise its presence => on
--   4. global default (M.default)
--
-- Personal overrides (1,2) live in stdpath('state')/autoformat.json and never
-- touch a repo. The marker (3) is committed so a project can ship a default.

local M = {}
local project = require("config.project")

M.default = false
local MARKER = ".autoformat"
local STATE = vim.fn.stdpath("state") .. "/autoformat.json"
local db = { files = {}, projects = {} }

local function load()
	local f = io.open(STATE, "r")
	if not f then
		return
	end
	local data = f:read("*a")
	f:close()
	local ok, decoded = pcall(vim.json.decode, data)
	if ok and type(decoded) == "table" then
		db.files = decoded.files or {}
		db.projects = decoded.projects or {}
	end
end
load()

local function save()
	vim.fn.mkdir(vim.fn.stdpath("state"), "p")
	local f = io.open(STATE, "w")
	if f then
		f:write(vim.json.encode(db))
		f:close()
	end
end

-- committed marker: nil (absent), true (present/on), false (content says off)
local function read_marker(root)
	if not root then
		return nil
	end
	local f = io.open(vim.fs.joinpath(root, MARKER), "r")
	if not f then
		return nil
	end
	local v = (f:read("*a") or ""):gsub("%s+", ""):lower()
	f:close()
	if v == "off" or v == "false" or v == "no" or v == "0" then
		return false
	end
	return true
end

local function bpath(bufnr)
	local n = vim.api.nvim_buf_get_name(bufnr or 0)
	return n ~= "" and vim.fs.normalize(vim.fn.fnamemodify(n, ":p")) or nil
end

local function broot(bufnr)
	local n = vim.api.nvim_buf_get_name(bufnr or 0)
	local opts = n ~= "" and { path = vim.fs.dirname(n) } or nil
	local ok, r = pcall(project.project_root, opts)
	return ok and r or nil
end

--- Resolve the decision for a buffer. Returns (enabled: boolean, source: string).
function M.resolve(bufnr)
	bufnr = bufnr or 0
	local p = bpath(bufnr)
	if p and db.files[p] ~= nil then
		return db.files[p], "file"
	end
	local r = broot(bufnr)
	if r then
		if db.projects[r] ~= nil then
			return db.projects[r], "project"
		end
		local m = read_marker(r)
		if m ~= nil then
			return m, "marker (.autoformat)"
		end
	end
	return M.default, "default"
end

function M.enabled(bufnr)
	return (M.resolve(bufnr))
end

function M.toggle_file(bufnr)
	bufnr = bufnr or 0
	local p = bpath(bufnr)
	if not p then
		vim.notify("autoformat: buffer has no file", vim.log.levels.WARN)
		return
	end
	db.files[p] = not M.enabled(bufnr)
	save()
	vim.notify("Autoformat (this file): " .. (db.files[p] and "ON" or "OFF"))
end

function M.toggle_project(bufnr)
	bufnr = bufnr or 0
	local r = broot(bufnr)
	if not r then
		vim.notify("autoformat: not in a project", vim.log.levels.WARN)
		return
	end
	local cur = db.projects[r]
	if cur == nil then
		cur = read_marker(r)
		if cur == nil then
			cur = M.default
		end
	end
	db.projects[r] = not cur
	save()
	vim.notify(("Autoformat (project %s): %s"):format(vim.fn.fnamemodify(r, ":t"), db.projects[r] and "ON" or "OFF"))
end

function M.clear_file(bufnr)
	bufnr = bufnr or 0
	local p = bpath(bufnr)
	if p then
		db.files[p] = nil
		save()
	end
	local v, src = M.resolve(bufnr)
	vim.notify(("Autoformat: file override cleared -> %s (%s)"):format(v and "ON" or "OFF", src))
end

function M.status(bufnr)
	local v, src = M.resolve(bufnr or 0)
	vim.notify(("Autoformat: %s  (from %s)"):format(v and "ON" or "OFF", src))
end

local cmd = vim.api.nvim_create_user_command
cmd("AutoformatFile", function()
	M.toggle_file(0)
end, { desc = "Toggle format-on-save for this file" })
cmd("AutoformatProject", function()
	M.toggle_project(0)
end, { desc = "Toggle format-on-save for this project" })
cmd("AutoformatClear", function()
	M.clear_file(0)
end, { desc = "Clear this file's format-on-save override" })
cmd("AutoformatStatus", function()
	M.status(0)
end, { desc = "Show format-on-save state and its source" })

local map = vim.keymap.set
map("n", "<leader>uf", function()
	M.toggle_file(0)
end, { desc = "Autoformat: toggle (file)" })
map("n", "<leader>uF", function()
	M.toggle_project(0)
end, { desc = "Autoformat: toggle (project)" })
map("n", "<leader>ud", function()
	M.clear_file(0)
end, { desc = "Autoformat: clear file override" })

return M
