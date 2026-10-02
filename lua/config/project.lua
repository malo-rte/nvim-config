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
local root_pin = nil

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

-- The repo git reports for `path`, cached. The answer depends on the cwd as
-- well as the path (the anchoring in M.project_root), so both belong in the
-- key. Caching by path alone needed a full wipe on every BufEnter, which meant
-- a synchronous `git rev-parse` per buffer switch -- on the UI thread, since
-- the statusline asks for the root on redraw. Call M.clear_root_cache() if a
-- repo appears mid-session.
local function resolve(cwd, path, no_cache)
	local key = cwd .. "\0" .. path
	if not no_cache and root_cache[key] then
		return root_cache[key]
	end
	local root = compute_root(path)
	if not no_cache then
		root_cache[key] = root
	end
	return root
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

	local natural = resolve(cwd, path, opts.no_cache)

	-- A pinned repo level (M.root_up / M.root_down) applies in two cases, and
	-- both are needed: the path is inside the pin (pinned *up* -- a file in a
	-- submodule while the superproject is pinned), or the pin sits inside the
	-- repo the path naturally belongs to (pinned *down* -- a file at the
	-- superproject root while a submodule is pinned, which is exactly the case
	-- <leader>pd prompts for). Anywhere else the pin is ignored rather than
	-- cleared, so hopping to an unrelated project and back keeps your level.
	if root_pin and (within(path, root_pin) or within(root_pin, natural)) then
		return root_pin
	end

	return natural
end

function M.clear_root_cache()
	root_cache = {}
end

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

-- ---------------------------------------------------------------------------
-- Repo level: submodules and nested repositories
--
-- compute_root() asks git for --show-toplevel, which is always the *innermost*
-- repo. Inside a submodule that means every picker, the neo-tree root, the
-- vault and the autoformat marker lookup anchor to the submodule, with no way
-- to say "I mean the superproject". These move that anchor one level at a time
-- and pin it; the statusline shows the pinned root with a trailing marker.
-- ---------------------------------------------------------------------------

local function git(dir, args)
	local cmd = { "git", "-C", dir }
	vim.list_extend(cmd, args)
	local out = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return out
end

--- The repo one level up: a submodule's superproject if there is one, else the
--- nearest enclosing directory with a project marker (plain nested repos --
--- git has no opinion about those, so fall back to the marker search).
---@param root string
---@return string|nil
function M.parent_root(root)
	local out = git(root, { "rev-parse", "--show-superproject-working-tree" })
	if out and out[1] and out[1] ~= "" then
		return vim.fs.normalize(out[1])
	end
	local parent = vim.fs.dirname(root)
	if not parent or parent == root then
		return nil
	end
	local found = root_by_markers(parent)
	-- root_by_markers starts at `parent`, so a marker *in* root cannot match;
	-- guard anyway against a symlinked path resolving back onto itself.
	if found and vim.fs.normalize(found) ~= vim.fs.normalize(root) then
		return vim.fs.normalize(found)
	end
end

--- Repos directly under `root`: registered submodules first (git knows those
--- even when they are not checked out), then any other nested repo found by
--- scanning. The scan stops descending at each repo it finds, so a submodule
--- inside a submodule is reached by stepping down twice, not in one jump.
---@param root string
---@return string[]
function M.child_roots(root)
	root = vim.fs.normalize(vim.fn.fnamemodify(root, ":p"))
	local seen, out = {}, {}
	local function add(dir)
		dir = vim.fs.normalize(dir)
		if dir ~= root and not seen[dir] and uv_fs_stat(dir) then
			seen[dir] = true
			out[#out + 1] = dir
		end
	end

	for _, line in ipairs(git(root, { "submodule", "--quiet", "foreach", "echo $toplevel/$sm_path" }) or {}) do
		if line ~= "" then
			add(line)
		end
	end

	local function ignored(name)
		for _, d in ipairs(DEFAULT_IGNORE) do
			if name == d then
				return true
			end
		end
		return false
	end

	local function scan(dir, depth)
		if depth > 3 then
			return
		end
		local ok, iter = pcall(uv_fs_scandir, dir)
		if not ok or not iter then
			return
		end
		while true do
			local name, typ = uv_fs_scandir_next(iter)
			if not name then
				break
			end
			if typ == "directory" and not ignored(name) then
				local child = vim.fs.joinpath(dir, name)
				if has_marker(child, { ".git" }) then
					add(child)
				else
					scan(child, depth + 1)
				end
			end
		end
	end
	scan(root, 1)

	table.sort(out)
	return out
end

--- The pinned root, or nil when the level is whatever git says.
---@return string|nil
function M.pinned_root()
	return root_pin
end

local function pin(dir, how)
	root_pin = vim.fs.normalize(dir)
	M.clear_root_cache()
	vim.notify(("project root %s: %s"):format(how, vim.fn.fnamemodify(root_pin, ":~")), vim.log.levels.INFO)
	pcall(vim.cmd.redrawstatus)
end

--- Pin the next repo level up (submodule -> superproject -> ...).
function M.root_up()
	local cur = M.project_root()
	local up = M.parent_root(cur)
	if not up then
		vim.notify(
			("project root: %s is already the outermost repo"):format(vim.fn.fnamemodify(cur, ":~")),
			vim.log.levels.WARN
		)
		return
	end
	pin(up, "up")
end

--- Pin a repo level down. The submodule the current buffer lives in is the
--- obvious answer when there is one; otherwise pick from the children.
function M.root_down()
	local cur = M.project_root()
	local kids = M.child_roots(cur)
	if #kids == 0 then
		vim.notify(
			("project root: no submodule or nested repo under %s"):format(vim.fn.fnamemodify(cur, ":~")),
			vim.log.levels.WARN
		)
		return
	end

	local here = start_dir()
	for _, k in ipairs(kids) do
		if within(here, k) then
			return pin(k, "down")
		end
	end

	if #kids == 1 then
		return pin(kids[1], "down")
	end

	-- vim.ui.select, so this goes through Telescope via the shim in the
	-- telescope spec without requiring it here (it is a lazy plugin).
	vim.ui.select(kids, {
		prompt = "Project root: down into",
		format_item = function(d)
			return vim.fn.fnamemodify(d, ":~")
		end,
	}, function(choice)
		if choice then
			pin(choice, "down")
		end
	end)
end

--- Drop the pin: back to the repo git reports for the current buffer.
function M.root_reset()
	if not root_pin then
		vim.notify("project root: not pinned", vim.log.levels.INFO)
		return
	end
	root_pin = nil
	M.clear_root_cache()
	vim.notify("project root: " .. vim.fn.fnamemodify(M.project_root(), ":~"), vim.log.levels.INFO)
	pcall(vim.cmd.redrawstatus)
end

return M
