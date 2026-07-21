-- config/project.lua
local M = {}

-- luv bindings (event loop + filesystem)
---@diagnostic disable: undefined-field
local uv_cwd = vim.uv.cwd
local uv_os_homedir = vim.uv.os_homedir
local uv_fs_stat = vim.uv.fs_stat
local uv_fs_scandir = vim.uv.fs_scandir
local uv_fs_scandir_next = vim.uv.fs_scandir_next
---@diagnostic enable: undefined-field

local root_cache = {}

local MARKERS = { ".git", "Cargo.toml", "go.mod", "pyproject.toml", "package.json" }
local DEFAULT_IGNORE = {
	".git",
	"node_modules",
	"dist",
	"build",
	"target",
	".venv",
	".tox",
	".cache",
	".idea",
	".vscode",
	".cargo",
	".local",
	"go",
	".arduino15",
	".config",
	".rustup",
	".password-store",
	".pwmanager",
}

local function start_dir()
	local buf = vim.api.nvim_buf_get_name(0)
	if buf ~= "" then
		return vim.fs.dirname(vim.fn.fnamemodify(buf, ":p"))
	end
	return uv_cwd()
end

local function root_by_markers(path)
	local home = uv_os_homedir()
	local stop = (path:sub(1, #home) == home) and home or "/"
	local found = vim.fs.find(MARKERS, { path = path, upward = true, stop = stop })
	if #found > 0 then
		return vim.fs.dirname(found[1])
	end
end

local function has_marker(dir, markers)
	for _, m in ipairs(markers) do
		if uv_fs_stat(vim.fs.joinpath(dir, m)) then
			return true
		end
	end
	return false
end

local function compute_root(path)
	local out = vim.fn.systemlist({ "git", "-C", path, "rev-parse", "--show-toplevel" })

	if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
		return out[1]
	end

	return root_by_markers(path) or path
end

local function within(dir, base)
	dir, base = vim.fs.normalize(dir), vim.fs.normalize(base)
	return dir == base or dir:sub(1, #base + 1) == base .. "/"
end

function M.project_root(opts)
	opts = opts or {}
	local path = vim.fn.fnamemodify(opts.path or start_dir(), ":p")

	-- If the focused buffer is outside the working dir (e.g. a stray
	-- session-restored file), anchor to the cwd you actually launched in
	-- / switched into, not the stray file's location.
	local cwd = vim.fn.getcwd()
	if not within(path, cwd) then
		path = vim.fn.fnamemodify(cwd, ":p")
	end

	if not opts.no_cache and root_cache[path] then
		return root_cache[path]
	end
	local root = compute_root(path)
	if not opts.no_cache then
		root_cache[path] = root
	end
	return root
end

function M.clear_root_cache()
	root_cache = {}
end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
	callback = function()
		M.clear_root_cache()
	end,
})

function M.find_projects(root, opts)
	opts = opts or {}
	local markers = opts.markers or MARKERS
	local ignore_dirs = opts.ignore_dirs or DEFAULT_IGNORE
	local max_depth = opts.max_depth or 3
	local follow_links = opts.follow_symlinks or false
	local limit = opts.limit or math.huge
	local prune_on_match = opts.prune_on_match or false

	root = vim.fn.fnamemodify(root or uv_cwd(), ":p")
	local st = uv_fs_stat(root)
	if not st or st.type ~= "directory" then
		return {}
	end

	local function should_ignore(name)
		for _, d in ipairs(ignore_dirs) do
			if name == d then
				return true
			end
		end
		return false
	end

	local results, seen = {}, {}
	local function add(dir)
		if not seen[dir] then
			seen[dir] = true
			results[#results + 1] = dir
		end
	end

	local queue = { { root, 0 } }
	local head = 1
	while head <= #queue and #results < limit do
		local dir, depth = queue[head][1], queue[head][2]
		head = head + 1

		if has_marker(dir, markers) then
			add(dir)
			if prune_on_match then
				goto continue
			end
		end

		if depth < max_depth then
			local ok, iter = pcall(uv_fs_scandir, dir)
			if ok and iter then
				while true do
					local name, typ = uv_fs_scandir_next(iter)
					if not name then
						break
					end
					if (typ == "directory") or (typ == "link" and follow_links) then
						if not should_ignore(name) then
							queue[#queue + 1] = { vim.fs.joinpath(dir, name), depth + 1 }
						end
					end
				end
			end
		end
		::continue::
	end

	table.sort(results)
	return results
end

-- Lazy-require Telescope only when the picker runs
local function telescope_deps()
	local ok = pcall(require, "telescope")
	if not ok then
		return nil
	end
	return {
		pickers = require("telescope.pickers"),
		finders = require("telescope.finders"),
		conf = require("telescope.config").values,
		actions = require("telescope.actions"),
		action_state = require("telescope.actions.state"),
		themes = require("telescope.themes"),
		builtin = require("telescope.builtin"),
	}
end

-- Project picker: scan under `root`, choose, chdir, then open a picker
function M.project_picker(root, opts)
	opts = opts or {}
	local t = telescope_deps()
	if not t then
		vim.notify("Telescope not available (project_picker)", vim.log.levels.ERROR)
		return
	end

	local projects = M.find_projects(root, opts.scan)
	if #projects == 0 then
		vim.notify("No projects found under " .. vim.fn.fnamemodify(root or (uv_cwd()), ":~"), vim.log.levels.WARN)
		return
	end

	local scope = opts.scope or "global" -- 'global' | 'tab' | 'window'
	local function do_chdir(dir)
		if scope == "tab" then
			pcall(vim.cmd.tcd, dir)
		elseif scope == "window" or scope == "win" then
			pcall(vim.cmd.lcd, dir)
		else
			pcall(vim.fn.chdir, dir)
		end
	end

	local open_kind = opts.open or "find_files" -- string or function(dir)

	local theme = t.themes.get_ivy()
	t.pickers
		.new(theme, {
			prompt_title = ("Projects (%s)"):format(vim.fn.fnamemodify(root or uv_cwd(), ":~")),
			finder = t.finders.new_table({
				results = projects,
				entry_maker = function(path)
					return { value = path, ordinal = path, display = vim.fn.fnamemodify(path, ":~") }
				end,
			}),
			sorter = t.conf.generic_sorter(theme),
			attach_mappings = function(bufnr, map)
				local function open_after_switch(which)
					local entry = t.action_state.get_selected_entry()
					if not entry or not entry.value then
						return
					end
					local dir = entry.value
					t.actions.close(bufnr)
					do_chdir(dir)

					if type(open_kind) == "function" then
						return open_kind(dir)
					end
					local ivy = t.themes.get_ivy()
					if which == "live_grep" then
						t.builtin.live_grep(vim.tbl_deep_extend("force", ivy, { cwd = dir }))
					else
						t.builtin.find_files(vim.tbl_deep_extend("force", ivy, { cwd = dir }))
					end
				end

				t.actions.select_default:replace(function()
					open_after_switch(open_kind)
				end)
				map("i", "<C-f>", function()
					open_after_switch("find_files")
				end)
				map("n", "<C-f>", function()
					open_after_switch("find_files")
				end)
				map("i", "<C-g>", function()
					open_after_switch("live_grep")
				end)
				map("n", "<C-g>", function()
					open_after_switch("live_grep")
				end)
				return true
			end,
		})
		:find()
end

return M
