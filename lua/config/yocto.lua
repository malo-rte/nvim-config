-- config/yocto.lua
--
-- Yocto / embedded ergonomics, build-aware.
--
-- Model:
--   * Workspace  = top-most git dir (walk up; keep the highest ancestor with .git).
--   * Builds     = bblayers.conf files found (recursively) under build/, builds/,
--                  or bitbake-builds/ in the workspace.
--   * Active build = one bblayers.conf you pick with :YoctoSelectBuild (<leader>yb).
--   * Layers     = resolved by matching the active bblayers.conf's BBLAYERS
--                  entries to the *real* conf/layer.conf dirs on disk, using the
--                  longest bottom-up path-segment match, tie-broken toward the
--                  active build's own tree. This is container/host agnostic: the
--                  paths inside bblayers.conf only need a matching tail on disk.
--
-- Build dirs and fetched layers are frequently gitignored, so scans use
-- --no-ignore with explicit prunes (tmp*, sstate-cache, downloads, .git).
--
-- Keymaps (<leader>y): yb select build · yr recipes · yc classes · yl layers
--   yg grep · ya bbappend->recipe · yi info

local M = {}
local uv = vim.uv or vim.loop

local config = {
	-- Extra dir names (besides build/builds/bitbake-builds) to look in.
	build_dirs = vim.g.yocto_build_dirs or { "build", "builds", "bitbake-builds" },
}

----------------------------------------------------------------------
-- Filetype + treesitter
----------------------------------------------------------------------
vim.filetype.add({
	extension = { dtso = "dts", its = "dts" },
	pattern = {
		[".*/conf/.*%.conf"] = "bitbake",
		[".*/recipes[^/]*/.*%.conf"] = "bitbake",
	},
})
pcall(vim.treesitter.language.register, "devicetree", "dts")

----------------------------------------------------------------------
-- Path helpers
----------------------------------------------------------------------
local function is_dir(p)
	local st = p and uv.fs_stat(p)
	return st and st.type == "directory"
end

local function exists(p)
	return p and uv.fs_stat(p) ~= nil
end

local function collapse(path)
	path = path:gsub("//+", "/")
	local parts = {}
	for seg in path:gmatch("[^/]+") do
		if seg == "." then
		elseif seg == ".." then
			if #parts > 0 then
				table.remove(parts)
			end
		else
			parts[#parts + 1] = seg
		end
	end
	return "/" .. table.concat(parts, "/")
end

local function segments(p)
	local t = {}
	for s in p:gmatch("[^/]+") do
		t[#t + 1] = s
	end
	return t
end

-- equal trailing segments
local function suffix_len(a, b)
	local i, j, n = #a, #b, 0
	while i >= 1 and j >= 1 and a[i] == b[j] do
		n, i, j = n + 1, i - 1, j - 1
	end
	return n
end

-- equal leading segments
local function prefix_len(a, b)
	local i, n = 1, 0
	while i <= #a and i <= #b and a[i] == b[i] do
		n, i = n + 1, i + 1
	end
	return n
end

----------------------------------------------------------------------
-- Workspace / scanning
----------------------------------------------------------------------
local function start_dir()
	local bn = vim.api.nvim_buf_get_name(0)
	if bn ~= "" then
		return vim.fs.dirname(vim.fn.fnamemodify(bn, ":p"))
	end
	return vim.fn.getcwd()
end

-- Highest ancestor that is a git repo (.git as dir or file). nil if none.
local function top_git_dir()
	local dir, top = start_dir(), nil
	while dir and dir ~= "" do
		if exists(dir .. "/.git") then
			top = dir
		end
		local parent = vim.fs.dirname(dir)
		if parent == dir then
			break
		end
		dir = parent
	end
	return top
end

local PRUNE = {
	"!**/tmp*/**",
	"!**/sstate-cache/**",
	"!**/downloads/**",
	"!**/.git/**",
	"!**/node_modules/**",
}

local function rg_find(glob, roots)
	local cmd = { "rg", "--files", "--no-ignore", "--hidden", "--glob", glob }
	for _, g in ipairs(PRUNE) do
		cmd[#cmd + 1] = "--glob"
		cmd[#cmd + 1] = g
	end
	for _, r in ipairs(roots) do
		cmd[#cmd + 1] = r
	end
	local out = {}
	for _, f in ipairs(vim.fn.systemlist(cmd)) do
		if f ~= "" then
			out[#out + 1] = collapse(f)
		end
	end
	return out
end

-- conf/bblayers.conf files under <ws>/{build,builds,bitbake-builds}
local function find_builds(ws)
	local roots = {}
	for _, b in ipairs(config.build_dirs) do
		local d = ws .. "/" .. b
		if is_dir(d) then
			roots[#roots + 1] = d
		end
	end
	if #roots == 0 then
		return {}
	end
	return rg_find("**/conf/bblayers.conf", roots)
end

-- All real layer dirs (parent of conf/layer.conf) under the workspace.
local function find_layer_dirs(ws)
	local dirs = {}
	for _, f in ipairs(rg_find("**/conf/layer.conf", { ws })) do
		dirs[#dirs + 1] = vim.fs.dirname(vim.fs.dirname(f))
	end
	return dirs
end

----------------------------------------------------------------------
-- bblayers.conf parsing
----------------------------------------------------------------------
local function logical_lines(path)
	local fd = io.open(path, "r")
	if not fd then
		return {}
	end
	local raw = fd:read("*a")
	fd:close()
	raw = raw:gsub("\\%s*\n", " ")
	local lines = {}
	for line in raw:gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	return lines
end

-- Ordered list of intended layer path strings (vars expanded where possible;
-- unresolved ${...} left intact, since matching is by trailing segments).
local function intended_layers(bbl)
	local topdir = vim.fs.dirname(vim.fs.dirname(bbl))
	local vars, bblayers = { TOPDIR = topdir }, nil
	for _, line in ipairs(logical_lines(bbl)) do
		local code = line:gsub("#.*$", "")
		local name, val = code:match('^%s*([%w_]+)%s*[?:+.]?=%s*"(.-)"%s*$')
		if name == "BBLAYERS" then
			bblayers = (bblayers and (bblayers .. " ") or "") .. val
		elseif name and not val:find("${@", 1, true) then
			vars[name] = val
		end
	end
	local function expand(s)
		for _ = 1, 5 do
			local n
			s, n = s:gsub("%${([%w_]+)}", function(v)
				return vars[v] or ("${" .. v .. "}")
			end)
			if n == 0 then
				break
			end
		end
		return s
	end
	local out = {}
	if not bblayers then
		return out, topdir
	end
	for tok in bblayers:gmatch("%S+") do
		local p = expand(tok)
		if not p:match("^/") and not p:match("^%${") then
			p = topdir .. "/" .. p
		end
		out[#out + 1] = collapse(p)
	end
	return out, topdir
end

----------------------------------------------------------------------
-- State + resolution
----------------------------------------------------------------------
local state = { active = nil } -- path to the active conf/bblayers.conf
local cache = { ws = nil, layer_dirs = nil, resolved_key = nil, resolved = nil }

local function ws_root()
	return top_git_dir() or vim.fn.getcwd()
end

local function layer_index(ws)
	if cache.ws == ws and cache.layer_dirs then
		return cache.layer_dirs
	end
	local dirs = find_layer_dirs(ws)
	cache.ws, cache.layer_dirs = ws, dirs
	return dirs
end

-- Resolve the active build's BBLAYERS to real on-disk layer dirs.
-- Returns: resolved (ordered dirs), unmatched (intended strings), mapping list.
local function resolve()
	if not state.active then
		return nil
	end
	if cache.resolved_key == state.active and cache.resolved then
		return cache.resolved.layers, cache.resolved.unmatched, cache.resolved.mapping
	end

	local ws = ws_root()
	local cands = layer_index(ws)
	local cseg = {}
	for i, c in ipairs(cands) do
		cseg[i] = segments(c)
	end

	local intended, topdir = intended_layers(state.active)
	local bseg = segments(topdir)

	local resolved, unmatched, mapping, seen = {}, {}, {}, {}
	for _, ip in ipairs(intended) do
		local iseg = segments(ip)
		local best, blen, btie
		for k, c in ipairs(cands) do
			local l = suffix_len(iseg, cseg[k])
			if l > 0 then
				local tie = prefix_len(bseg, cseg[k])
				if not best or l > blen or (l == blen and tie > btie) then
					best, blen, btie = c, l, tie
				end
			end
		end
		if best then
			mapping[#mapping + 1] = { intended = ip, matched = best }
			if not seen[best] then
				seen[best] = true
				resolved[#resolved + 1] = best
			end
		else
			unmatched[#unmatched + 1] = ip
		end
	end

	cache.resolved_key = state.active
	cache.resolved = { layers = resolved, unmatched = unmatched, mapping = mapping }
	return resolved, unmatched, mapping
end

----------------------------------------------------------------------
-- Build picker
----------------------------------------------------------------------
local function ivy(opts)
	return vim.tbl_deep_extend("force", require("telescope.themes").get_ivy(), opts or {})
end

-- on_done(selected_bblayers_path) is called after a build is chosen.
function M.select_build(on_done)
	local ws = ws_root()
	local builds = find_builds(ws)
	if #builds == 0 then
		vim.notify(
			"yocto: no bblayers.conf under " .. table.concat(config.build_dirs, "/, ") .. "/ in " .. ws,
			vim.log.levels.WARN
		)
		return
	end
	if #builds == 1 then
		state.active, cache.resolved_key = builds[1], nil
		vim.notify("yocto: active build " .. vim.fn.fnamemodify(vim.fs.dirname(vim.fs.dirname(builds[1])), ":~"))
		if on_done then
			on_done(builds[1])
		end
		return
	end

	local t = {
		pickers = require("telescope.pickers"),
		finders = require("telescope.finders"),
		conf = require("telescope.config").values,
		actions = require("telescope.actions"),
		state = require("telescope.actions.state"),
	}
	t.pickers
		.new(ivy({}), {
			prompt_title = "Select Yocto build",
			finder = t.finders.new_table({
				results = builds,
				entry_maker = function(p)
					local d = vim.fs.dirname(vim.fs.dirname(p)) -- build dir
					return { value = p, ordinal = d, display = vim.fn.fnamemodify(d, ":~") }
				end,
			}),
			sorter = t.conf.generic_sorter({}),
			attach_mappings = function(bufnr)
				t.actions.select_default:replace(function()
					local entry = t.state.get_selected_entry()
					t.actions.close(bufnr)
					if entry then
						state.active, cache.resolved_key = entry.value, nil
						vim.notify(
							"yocto: active build " .. vim.fn.fnamemodify(vim.fs.dirname(vim.fs.dirname(entry.value)), ":~")
						)
						if on_done then
							on_done(entry.value)
						end
					end
				end)
				return true
			end,
		})
		:find()
end

-- Ensure a build is active; if not, open the picker and run `cont` afterward.
local function with_active(cont)
	if state.active then
		return cont()
	end
	vim.notify("yocto: pick an active build first", vim.log.levels.INFO)
	M.select_build(function()
		cont()
	end)
end

----------------------------------------------------------------------
-- Layer pickers
----------------------------------------------------------------------
local function rg_files_cmd(globs)
	local cmd = { "rg", "--files", "--no-ignore", "--hidden", "--glob", "!**/.git/*" }
	for _, g in ipairs(globs) do
		cmd[#cmd + 1] = "--glob"
		cmd[#cmd + 1] = g
	end
	return cmd
end

local function pick_files(title, globs)
	with_active(function()
		local layers = resolve()
		if not layers or #layers == 0 then
			vim.notify("yocto: active build resolved to no layers (try :YoctoLayersInfo)", vim.log.levels.WARN)
			return
		end
		local cmd = rg_files_cmd(globs)
		vim.list_extend(cmd, layers)
		require("telescope.builtin").find_files(ivy({
			prompt_title = ("%s  [%d layers]"):format(title, #layers),
			find_command = cmd,
			path_display = { "smart" },
		}))
	end)
end

function M.recipes()
	pick_files("Yocto Recipes", { "*.bb", "*.bbappend" })
end

function M.classes()
	pick_files("Yocto Classes / Includes", { "*.bbclass", "*.inc" })
end

function M.layers()
	pick_files("Yocto Layers (conf/layer.conf)", { "**/conf/layer.conf" })
end

function M.grep()
	with_active(function()
		local layers = resolve()
		if not layers or #layers == 0 then
			vim.notify("yocto: active build resolved to no layers", vim.log.levels.WARN)
			return
		end
		require("telescope.builtin").live_grep(ivy({
			prompt_title = ("Grep BitBake files  [%d layers]"):format(#layers),
			search_dirs = layers,
			glob_pattern = { "*.bb", "*.bbappend", "*.bbclass", "*.inc", "*.conf" },
		}))
	end)
end

function M.find_recipe()
	local fname = vim.api.nvim_buf_get_name(0)
	if not fname:match("%.bbappend$") then
		vim.notify("Not a .bbappend buffer", vim.log.levels.WARN)
		return
	end
	local base = vim.fn.fnamemodify(fname, ":t"):gsub("%.bbappend$", ""):gsub("_[^_]*$", "")
	with_active(function()
		local layers = resolve()
		if not layers or #layers == 0 then
			vim.notify("yocto: active build resolved to no layers", vim.log.levels.WARN)
			return
		end
		local cmd = rg_files_cmd({ base .. "_*.bb", base .. ".bb" })
		vim.list_extend(cmd, layers)
		local matches = vim.tbl_filter(function(p)
			return p ~= "" and p:match("%.bb$")
		end, vim.fn.systemlist(cmd))
		if #matches == 0 then
			vim.notify(("No recipe for '%s' across %d layers"):format(base, #layers), vim.log.levels.WARN)
		elseif #matches == 1 then
			vim.cmd.edit(vim.fn.fnameescape(matches[1]))
		else
			require("telescope.builtin").find_files(ivy({
				prompt_title = ("Recipes for %s  [%d layers]"):format(base, #layers),
				find_command = cmd,
				path_display = { "smart" },
			}))
		end
	end)
end

function M.info()
	if not state.active then
		vim.notify("yocto: no active build. Run :YoctoSelectBuild (<leader>yb).")
		return
	end
	local layers, unmatched, mapping = resolve()
	local lines = {
		"Active build: " .. vim.fn.fnamemodify(vim.fs.dirname(vim.fs.dirname(state.active)), ":~"),
		"Workspace:    " .. vim.fn.fnamemodify(ws_root(), ":~"),
		("Resolved %d layer(s):"):format(#layers),
	}
	for _, m in ipairs(mapping) do
		lines[#lines + 1] = "  " .. vim.fn.fnamemodify(m.matched, ":~")
	end
	if #unmatched > 0 then
		lines[#lines + 1] = ("Unmatched %d:"):format(#unmatched)
		for _, u in ipairs(unmatched) do
			lines[#lines + 1] = "  " .. u
		end
	end
	vim.notify(table.concat(lines, "\n"))
end

----------------------------------------------------------------------
-- Recipe navigation: BitBake-aware `gf`
--   require/include <path> -> open the file (relative, layer-root, basename)
--   anything else          -> treat <cword> as a class -> <name>.bbclass
-- Uses the active build's layers, falling back to the full layer index.
----------------------------------------------------------------------
local function nav_layers()
	local layers = resolve()
	if layers and #layers > 0 then
		return layers
	end
	return layer_index(ws_root())
end

-- Open the single hit, or a picker for several. Returns false if no hits.
local function choose(title, files)
	files = vim.tbl_filter(function(f)
		return f and f ~= ""
	end, files or {})
	if #files == 0 then
		return false
	end
	if #files == 1 then
		vim.cmd.edit(vim.fn.fnameescape(files[1]))
		return true
	end
	local t = {
		pickers = require("telescope.pickers"),
		finders = require("telescope.finders"),
		conf = require("telescope.config").values,
		actions = require("telescope.actions"),
		state = require("telescope.actions.state"),
	}
	t.pickers
		.new(ivy({}), {
			prompt_title = title,
			finder = t.finders.new_table({
				results = files,
				entry_maker = function(p)
					return { value = p, ordinal = p, display = vim.fn.fnamemodify(p, ":~") }
				end,
			}),
			sorter = t.conf.generic_sorter({}),
			attach_mappings = function(bufnr)
				t.actions.select_default:replace(function()
					local e = t.state.get_selected_entry()
					t.actions.close(bufnr)
					if e then
						vim.cmd.edit(vim.fn.fnameescape(e.value))
					end
				end)
				return true
			end,
		})
		:find()
	return true
end

local function find_class(name, layers)
	local cmd = rg_files_cmd({ "**/classes*/" .. name .. ".bbclass", "**/" .. name .. ".bbclass" })
	vim.list_extend(cmd, layers)
	local want = name .. ".bbclass"
	return vim.tbl_filter(function(p)
		return p ~= "" and vim.fs.basename(p) == want
	end, vim.fn.systemlist(cmd))
end

local function resolve_require(token, curfile, layers)
	-- 1) absolute
	if token:match("^/") and vim.fn.filereadable(token) == 1 then
		return { token }
	end
	-- 2) relative to the current file
	local rel = collapse(vim.fs.dirname(curfile) .. "/" .. token)
	if vim.fn.filereadable(rel) == 1 then
		return { rel }
	end
	-- 3) relative to each layer root (BBPATH-style)
	local hits = {}
	for _, L in ipairs(layers) do
		local cand = collapse(L .. "/" .. token)
		if vim.fn.filereadable(cand) == 1 then
			hits[#hits + 1] = cand
		end
	end
	if #hits > 0 then
		return hits
	end
	-- 4) basename across layers (handles ${...} in the path)
	local base = (token:match("([^/]+)$") or token):gsub("%${[^}]*}", "")
	if base == "" then
		return {}
	end
	local cmd = rg_files_cmd({ "**/" .. base, base })
	vim.list_extend(cmd, layers)
	return vim.tbl_filter(function(p)
		return p ~= "" and vim.fs.basename(p) == base
	end, vim.fn.systemlist(cmd))
end

function M.goto_def()
	local layers = nav_layers()
	if #layers == 0 then
		vim.notify("yocto: no layers (select a build or open within a workspace)", vim.log.levels.WARN)
		return
	end
	vim.cmd("normal! m'")                       -- record origin for <C-o>
	local line = vim.api.nvim_get_current_line() -- <- this line must still be here
	local req = line:match("^%s*require%s+(%S+)") or line:match("^%s*include%s+(%S+)")

	if req then
		if not choose("require/include: " .. req, resolve_require(req, vim.api.nvim_buf_get_name(0), layers)) then
			vim.notify("yocto: could not resolve '" .. req .. "'", vim.log.levels.WARN)
		end
		return
	end
	local name = vim.fn.expand("<cword>")
	if name == "" then
		vim.notify("yocto: nothing under cursor", vim.log.levels.WARN)
		return
	end
	if not choose(name .. ".bbclass", find_class(name, layers)) then
		vim.notify("yocto: no class '" .. name .. ".bbclass'", vim.log.levels.WARN)
	end
end

----------------------------------------------------------------------
-- Commands + keymaps
----------------------------------------------------------------------
local ucmd = vim.api.nvim_create_user_command
ucmd("YoctoSelectBuild", function()
	M.select_build()
end, {})
ucmd("YoctoRecipes", M.recipes, {})
ucmd("YoctoClasses", M.classes, {})
ucmd("YoctoLayers", M.layers, {})
ucmd("YoctoGrep", M.grep, {})
ucmd("YoctoFindRecipe", M.find_recipe, {})
ucmd("YoctoLayersInfo", M.info, {})
ucmd("YoctoGoto", M.goto_def, {})
ucmd("YoctoRefresh", function()
	cache = { ws = nil, layer_dirs = nil, resolved_key = nil, resolved = nil }
	vim.notify("yocto: caches cleared")
end, {})

vim.api.nvim_create_autocmd("DirChanged", {
	callback = function()
		cache = { ws = nil, layer_dirs = nil, resolved_key = nil, resolved = nil }
	end,
})

local map = vim.keymap.set
map("n", "<leader>yb", function()
	M.select_build()
end, { desc = "Yocto: select active build" })
map("n", "<leader>yr", M.recipes, { desc = "Yocto: find recipes" })
map("n", "<leader>yc", M.classes, { desc = "Yocto: find classes/includes" })
map("n", "<leader>yl", M.layers, { desc = "Yocto: list layers" })
map("n", "<leader>yg", M.grep, { desc = "Yocto: grep BitBake files" })
map("n", "<leader>ya", M.find_recipe, { desc = "Yocto: bbappend -> recipe" })
map("n", "<leader>yi", M.info, { desc = "Yocto: layer info" })
map("n", "<leader>yj", M.goto_def, { desc = "Yocto: goto inherit/require under cursor" })

-- BitBake-aware `gf` in recipe buffers.
vim.api.nvim_create_autocmd("FileType", {
	pattern = "bitbake",
	callback = function(ev)
		vim.keymap.set("n", "gf", M.goto_def, {
			buffer = ev.buf,
			desc = "BitBake: goto inherit/require/include",
		})
	end,
})

return M
