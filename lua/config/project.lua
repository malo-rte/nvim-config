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
	-- tool state, not projects: ~/.claude/plugins/marketplaces/* are each a
	-- git repo, so without this they dominate a $HOME scan (4 of 7 here).
	".claude",
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

-- A resumable breadth-first project scan.
--
-- `step(budget)` visits at most `budget` directories and returns whether work
-- remains, so one traversal serves both callers: M.find_projects drains it in
-- a single call, M.find_projects_async slices it across event-loop ticks. The
-- scan is one function rather than two because the pruning, ignore and depth
-- rules are the fiddly part and must not drift between a blocking and a
-- non-blocking copy.
local function scanner(root, opts)
	opts = opts or {}
	local markers = opts.markers or MARKERS
	local ignore_dirs = opts.ignore_dirs or DEFAULT_IGNORE
	local max_depth = opts.max_depth or 3
	local follow_links = opts.follow_symlinks or false
	local limit = opts.limit or math.huge
	local prune_on_match = opts.prune_on_match or false

	root = vim.fn.fnamemodify(root or uv_cwd(), ":p")
	local st = uv_fs_stat(root)

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

	-- An unreadable or missing root simply yields nothing.
	local queue = (st and st.type == "directory") and { { root, 0 } } or {}
	local head = 1

	local function more()
		return head <= #queue and #results < limit
	end

	-- `deadline_ns` matters more than `budget`: a slice measured in directories
	-- blocks for however long those directories take, which on a slow or
	-- network filesystem is unbounded. Time-bounding the slice keeps the pause
	-- the same regardless of how expensive each scandir turns out to be.
	local function step(budget, deadline_ns)
		local visited = 0
		while more() and visited < budget do
			if deadline_ns and vim.uv.hrtime() > deadline_ns then
				break
			end
			local dir, depth = queue[head][1], queue[head][2]
			head = head + 1
			visited = visited + 1

			local matched = has_marker(dir, markers)
			if matched then
				add(dir)
			end

			-- prune_on_match stops at the first marker; without it the walk
			-- descends into projects too, which is how a repo inside a repo
			-- (vendored checkout, submodule, sub-crate) gets listed.
			if not (matched and prune_on_match) and depth < max_depth then
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
		end
		return more()
	end

	return step, results
end

function M.find_projects(root, opts)
	local step, results = scanner(root, opts)
	while step(math.huge) do
	end
	table.sort(results)
	return results
end

--- Which `fd` to use, if any. Debian installs the binary as `fdfind`.
local function fd_bin()
	for _, b in ipairs({ "fd", "fdfind" }) do
		if vim.fn.executable(b) == 1 then
			return b
		end
	end
end

--- `fd` invocation that finds marker files/dirs anywhere under `root`.
---
--- Three flags carry the whole design:
---   --hidden     `.git` is a dotfile and would otherwise be invisible
---   --no-ignore  a project ignored by some parent .gitignore is still a project
---   --prune      report a matched directory but do not walk into it, so `.git`
---                costs one directory instead of its whole object store
--- `.git` is deliberately *not* passed as --exclude even though DEFAULT_IGNORE
--- lists it: excluding it would drop the very markers being searched for, and
--- --prune already stops the descent.
local function fd_cmd(bin, root, opts)
	local markers = opts.markers or MARKERS
	local names = {}
	for _, m in ipairs(markers) do
		names[#names + 1] = (m:gsub("%%.", "\\."))
	end

	local cmd = {
		bin,
		"--hidden",
		"--no-ignore",
		"--absolute-path",
		"--prune",
		("^(%s)$"):format(table.concat(names, "|")),
	}
	if opts.max_depth and opts.max_depth ~= math.huge then
		vim.list_extend(cmd, { "--max-depth", tostring(opts.max_depth) })
	end
	if opts.limit and opts.limit ~= math.huge then
		vim.list_extend(cmd, { "--max-results", tostring(opts.limit) })
	end

	local marker_set = {}
	for _, m in ipairs(markers) do
		marker_set[m] = true
	end
	for _, d in ipairs(opts.ignore_dirs or DEFAULT_IGNORE) do
		if not marker_set[d] then
			vim.list_extend(cmd, { "--exclude", d })
		end
	end

	cmd[#cmd + 1] = root
	return cmd
end

--- The same scan as M.find_projects_async, handed to `fd` instead.
---
--- fd is parallel and native, which is the difference between "the picker
--- fills over a second or two" and "the picker is already full": on a $HOME of
--- 65k directories the Lua walk takes ~1.6 s and fd ~0.2 s. The Lua walk stays
--- as the fallback for machines without fd, and for prune_on_match, which fd
--- cannot express -- its --prune acts on matched *markers*, not on the project
--- directory that contains them.
---
---@return fun()|nil cancel nil when fd cannot serve this scan
function M.find_projects_fd(root, opts, on_batch, on_done)
	opts = opts or {}
	local bin = fd_bin()
	if not bin or opts.prune_on_match then
		return nil
	end
	root = vim.fn.fnamemodify(root or uv_cwd(), ":p")

	local results, seen = {}, {}
	local pending, dirty, cancelled = "", false, false

	-- fd prints a trailing slash on directories, so strip it before taking the
	-- parent: dirname("~/p/.git/") is "~/p/.git", not "~/p".
	local function take(line)
		if line == "" then
			return
		end
		local dir = vim.fs.dirname((line:gsub("/+$", "")))
		if dir and dir ~= "" and not seen[dir] then
			seen[dir] = true
			results[#results + 1] = dir
			dirty = true
		end
	end

	-- stdout arrives in chunks that split lines anywhere.
	local function feed(chunk)
		pending = pending .. chunk
		while true do
			local nl = pending:find("\n", 1, true)
			if not nl then
				break
			end
			take(pending:sub(1, nl - 1))
			pending = pending:sub(nl + 1)
		end
	end

	local handle = vim.system(fd_cmd(bin, root, opts), {
		text = true,
		-- This runs in a fast event context: parse here, touch the editor only
		-- inside vim.schedule.
		stdout = function(_, chunk)
			if cancelled or not chunk then
				return
			end
			feed(chunk)
			if dirty then
				dirty = false
				vim.schedule(function()
					if not cancelled and on_batch then
						on_batch(results)
					end
				end)
			end
		end,
	}, function()
		vim.schedule(function()
			if cancelled then
				return
			end
			take(pending)
			table.sort(results)
			if on_done then
				on_done(results)
			end
		end)
	end)

	return function()
		cancelled = true
		pcall(function()
			handle:kill(15)
		end)
	end
end

--- M.find_projects without blocking the editor.
---
--- `limit` caps results, not work: a recursive scan of a $HOME holding tens of
--- thousands of directories keeps walking long after it has found everything,
--- and doing that synchronously is what made the recursive picker feel hung.
--- This runs the same traversal in slices, handing control back to the event
--- loop between them, and reports what it has so far after every slice that
--- found something -- so a picker can fill while the scan is still running.
---
--- Results arrive in breadth-first order (shallowest first) and are sorted
--- only at the end; re-sorting mid-scan would reshuffle a list someone is
--- already looking at.
---
---@param root string
---@param opts table|nil as M.find_projects, plus `budget_ms` (milliseconds of
---  walking per event-loop tick, default 8 -- under one frame) and `slice` (a
---  hard directory cap per tick, default 2000)
---@param on_batch fun(results: string[])|nil called after a slice found something
---@param on_done fun(results: string[])|nil called once, after the final slice
---@return fun() cancel stops the walk (call it when the picker closes)
function M.find_projects_async(root, opts, on_batch, on_done)
	opts = opts or {}
	local slice = opts.slice or 2000
	local budget_ms = opts.budget_ms or 8
	local step, results = scanner(root, opts)
	local cancelled, reported = false, 0

	local function tick()
		if cancelled then
			return
		end
		local busy = step(slice, vim.uv.hrtime() + budget_ms * 1e6)
		if #results > reported then
			reported = #results
			if on_batch then
				on_batch(results)
			end
		end
		if busy then
			vim.schedule(tick)
		else
			table.sort(results)
			if on_done then
				on_done(results)
			end
		end
	end

	vim.schedule(tick)
	return function()
		cancelled = true
	end
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

	-- Synchronous callers (a bounded scan) keep the old contract: nothing found
	-- means say so and never open an empty picker. The async path cannot know
	-- that yet, so it opens first and reports at the end -- see below.
	local projects = {}
	if not opts.async then
		projects = M.find_projects(root, opts.scan)
		if #projects == 0 then
			vim.notify("No projects found under " .. vim.fn.fnamemodify(root or (uv_cwd()), ":~"), vim.log.levels.WARN)
			return
		end
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
	local where = vim.fn.fnamemodify(root or uv_cwd(), ":~")

	-- One entry table per path, reused by every finder this picker gets.
	-- Telescope's selection_strategy = "follow" re-finds the selected entry
	-- with `container[1] == entry` -- an identity comparison -- so a refresh
	-- that built fresh tables for the same paths would never match, and the
	-- selection would snap back to the top on every batch.
	local entries = {}
	local function entry_maker(path)
		local e = entries[path]
		if not e then
			e = { value = path, ordinal = path, display = vim.fn.fnamemodify(path, ":~") }
			entries[path] = e
		end
		return e
	end

	local picker = t.pickers.new(theme, {
		prompt_title = opts.async and ("Projects (%s) -- scanning"):format(where) or ("Projects (%s)"):format(where),
		-- Keep the cursor on whatever is selected while results stream in.
		selection_strategy = opts.async and "follow" or nil,
		finder = t.finders.new_table({
			results = projects,
			entry_maker = entry_maker,
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

	picker:find()

	if not opts.async then
		return
	end

	-- Fill the picker as the scan runs. Refreshing swaps in a new table finder
	-- over the results so far; reset_prompt stays false so whatever has been
	-- typed keeps filtering. The title carries the count, because an empty
	-- picker that is merely still scanning looks like a broken one.
	local function title(text)
		pcall(function()
			picker.layout.prompt.border:change_title(text)
		end)
	end

	local cancel
	local function refresh(results)
		if picker.closed then
			if cancel then
				cancel()
			end
			return
		end
		picker:refresh(
			t.finders.new_table({
				results = vim.list_slice(results, 1, #results),
				entry_maker = entry_maker,
			}),
			{ reset_prompt = false }
		)
	end

	local function batch(results)
		refresh(results)
		title(("Projects (%s) -- %d, scanning"):format(where, #results))
	end

	local function finish(results)
		if picker.closed then
			return
		end
		refresh(results)
		title(("Projects (%s) -- %d"):format(where, #results))
		if #results == 0 then
			vim.notify("No projects found under " .. where, vim.log.levels.WARN)
		end
	end

	-- fd when it is installed (parallel and native, roughly 8x the Lua walk),
	-- otherwise the pure-Lua sliced walk. Both stream into the same refresh.
	cancel = M.find_projects_fd(root, opts.scan, batch, finish) or M.find_projects_async(root, opts.scan, batch, finish)

	-- Stop walking when the picker goes away, rather than scanning $HOME for
	-- nobody. Telescope sets picker.closed on close; the autocmd catches the
	-- buffer being wiped even if that is bypassed.
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = picker.prompt_bufnr,
		once = true,
		callback = function()
			cancel()
		end,
	})
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
