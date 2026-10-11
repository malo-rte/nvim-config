-- Dump every key mapping this config defines, with provenance.
--
-- Loaded with `nvim --headless --cmd "luafile scripts/keymap_inventory.lua"`
-- so it runs *before* init.lua: that is the only way to see each mapping as it
-- is created. Reading the keymap table afterwards is not equivalent -- it keeps
-- only the winner, so two places claiming the same key look like one, which is
-- exactly the conflict worth reporting.
--
-- Driven by scripts/keymaps.py, which boots this against a copy of the repo
-- (lazy.nvim writes lazy-lock.json into stdpath('config'); see nvim-sandbox.sh).
--
-- Env:
--   KEYMAP_OUT      file to write the JSON inventory to (required)
--   KEYMAP_WAIT_MS  ms to let the config settle before dumping (default 9000)
--
-- What is captured, and how:
--   * every nvim_set_keymap / nvim_buf_set_keymap call, which is also every
--     vim.keymap.set call (it funnels through the API) -- including the ones
--     made *inside* plugins, so mini.surround's `sa` and mini.move's arrows
--     show up attributed to the plugin that created them. No static scan can
--     see those.
--   * Neovim's own defaults, snapshotted here before init.lua runs: anything
--     the config then sets over one of them is an override, not a conflict.
--   * lazy.nvim's `keys` specs, read from the plugin table via
--     Plugin.values(plugin, "keys", true) -- NOT plugin.keys, which returns
--     only the last spec fragment's list and would silently under-report.
--   * buffer-local maps, by opening a real buffer per filetype. LspAttach maps
--     (gd, K, <leader>cr, ...) exist nowhere until a server attaches.

local MODES = { "n", "i", "v", "x", "s", "o", "t", "c" }
local CONFIG_ROOT = vim.fn.stdpath("config")

local out_path = vim.env.KEYMAP_OUT
local wait_ms = tonumber(vim.env.KEYMAP_WAIT_MS or "") or 9000

local log = {} -- every set call, in order
local notes = {} -- anything the dump itself could not do

local function note(msg)
	notes[#notes + 1] = tostring(msg)
end

-- Classify a chunk source into (kind, id). `info.source` is used rather than
-- `short_src` on purpose: short_src is truncated to 60 chars, which mangles
-- exactly the long temp-copy paths this runs against.
local function classify(source)
	local path = tostring(source or ""):gsub("^[@=]", "")
	if path:find("/lazy/lazy.nvim/lua/lazy/core/handler/keys.lua", 1, true) then
		-- lazy.nvim creating a lazy-load trigger, or the real mapping after
		-- load. Both belong to the plugin whose spec declared the key, which
		-- only `lazy_keys` below can say.
		return "lazy-handler", "lazy.nvim"
	end
	if path:sub(1, #CONFIG_ROOT + 1) == CONFIG_ROOT .. "/" then
		return "config", path:sub(#CONFIG_ROOT + 2)
	end
	local plugin = path:match("/lazy/([^/]+)/")
	if plugin then
		return "plugin", plugin
	end
	local runtime = path:match("/share/nvim/runtime/(.+)$")
	if runtime then
		return "runtime", runtime
	end
	if path:find("/runtime/lua/", 1, true) or path:find("vim/_", 1, true) then
		return "runtime", path
	end
	return "unknown", path
end

-- Attribute a set call to the first stack frame that is neither keymap
-- plumbing nor this file. Getting this wrong is silent: every mapping ends up
-- owned by the shim, every key has exactly one owner, and the report says
-- "no conflicts" forever. scripts/keymaps.py --self-test is what keeps it honest.
local function owner()
	for lvl = 3, 16 do
		local info = debug.getinfo(lvl, "Sl")
		if not info then
			break
		end
		local source = tostring(info.source or "")
		local is_plumbing = source:find("vim/keymap", 1, true)
			or source:find("keymap_inventory.lua", 1, true)
			or source == "=[C]"
			or source == "[C]"
		if not is_plumbing then
			local kind, id = classify(source)
			return kind, id, info.currentline or 0
		end
	end
	return "unknown", "?", 0
end

-- A mapping is written as `<leader>ff` but lands in the keymap table as a
-- literal space plus "ff". Compare the two forms directly and every leader
-- mapping looks like a different key in each source. `key` below is the
-- canonical form (what you would actually press), `lhs` the way it was written.
local function canonical(lhs)
	local leader = vim.g.mapleader or "\\"
	local localleader = vim.g.maplocalleader or "\\"
	local s = tostring(lhs)
		:gsub("<[lL]eader>", function()
			return leader
		end)
		:gsub("<[lL]ocal[lL]eader>", function()
			return localleader
		end)
	local ok, resolved = pcall(vim.api.nvim_replace_termcodes, s, true, true, true)
	s = ok and resolved or s
	local ok_trans, pretty = pcall(vim.fn.keytrans, s)
	return ok_trans and pretty or s
end

local function record(modes, lhs, rhs, opts, bufnr)
	opts = opts or {}
	local kind, id, line = owner()
	local list = type(modes) == "table" and modes or { modes }
	for _, mode in ipairs(list) do
		log[#log + 1] = {
			mode = mode == "" and " " or mode,
			lhs = lhs,
			key = canonical(lhs),
			desc = opts.desc,
			src_kind = kind,
			src_id = id,
			src_line = line,
			buffer = bufnr,
			rhs = type(rhs) == "string" and rhs or (rhs == nil and "" or "<function>"),
		}
	end
end

-- Snapshot Neovim's defaults before anything of ours runs.
local baseline = {}
for _, mode in ipairs(MODES) do
	local ok, maps = pcall(vim.api.nvim_get_keymap, mode)
	if ok then
		for _, m in ipairs(maps) do
			baseline[mode .. "\t" .. canonical(m.lhs)] = m.desc or ""
		end
	end
end

local real_set = vim.api.nvim_set_keymap
local real_buf_set = vim.api.nvim_buf_set_keymap

vim.api.nvim_set_keymap = function(mode, lhs, rhs, opts)
	pcall(record, mode, lhs, rhs, opts, nil)
	return real_set(mode, lhs, rhs, opts)
end

vim.api.nvim_buf_set_keymap = function(bufnr, mode, lhs, rhs, opts)
	pcall(record, mode, lhs, rhs, opts, bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr)
	return real_buf_set(bufnr, mode, lhs, rhs, opts)
end

-- lazy.nvim `keys` specs: lhs -> owning plugin. Needed because lazy creates
-- both the lazy-load trigger and the post-load mapping from its own handler,
-- so without this every lazy key is owned by "lazy.nvim" and a collision
-- between a global map and a plugin's lazy key is invisible.
local function lazy_keys()
	local ok, config = pcall(require, "lazy.core.config")
	if not ok then
		note("lazy.core.config unavailable: lazy key specs not read")
		return {}
	end
	local plugin_mod = require("lazy.core.plugin")
	local found = {}
	for name, plugin in pairs(config.plugins) do
		local ok_vals, specs = pcall(plugin_mod.values, plugin, "keys", true)
		if not ok_vals then
			note("could not resolve keys for " .. name)
		else
			for _, spec in ipairs(specs or {}) do
				local lhs = type(spec) == "string" and spec or spec[1]
				if lhs then
					local modes = spec.mode or "n"
					for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
						found[#found + 1] = {
							lhs = lhs,
							key = canonical(lhs),
							mode = mode,
							plugin = name,
							desc = type(spec) == "table" and spec.desc or nil,
							ft = type(spec) == "table" and spec.ft or nil,
						}
					end
				end
			end
		end
	end
	return found
end

-- Load everything. In a headless boot `VeryLazy` never fires (it hangs off
-- UIEnter), so hlslens, git-conflict, dap and friends would contribute no
-- mappings at all and the dump would quietly miss ~25 keys.
local function load_everything()
	pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "VeryLazy", modeline = false })
	local ok, config = pcall(require, "lazy.core.config")
	if not ok then
		return {}
	end
	local pending = {}
	for name, plugin in pairs(config.plugins) do
		if not plugin._.loaded then
			pending[#pending + 1] = name
		end
	end
	if #pending > 0 then
		local ok_load, err = pcall(function()
			require("lazy").load({ plugins = pending })
		end)
		if not ok_load then
			note("lazy.load failed: " .. tostring(err))
		end
	end
	local still = {}
	for name, plugin in pairs(config.plugins) do
		if not plugin._.loaded then
			still[#still + 1] = name
		end
	end
	table.sort(still)
	return still
end

-- Buffer-local maps need a buffer. One real file per filetype, then give any
-- language server a moment to attach -- LspAttach is what creates gd/K/<leader>cr.
local PROBES = {
	{ ft = "lua", name = "probe.lua", text = { "local M = {}", "return M" } },
	{ ft = "bitbake", name = "probe.bb", text = { 'DESCRIPTION = "probe"', "inherit core-image" } },
	{ ft = "markdown", name = "probe.md", text = { "# probe", "", "- [ ] task" } },
	{ ft = "python", name = "probe.py", text = { "def main():", "    return 0" } },
	{ ft = "sh", name = "probe.sh", text = { "#!/usr/bin/env bash", "echo probe" } },
}

local function probe_buffers()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	local covered, missed = {}, {}
	for _, probe in ipairs(PROBES) do
		local path = dir .. "/" .. probe.name
		local ok_write = pcall(vim.fn.writefile, probe.text, path)
		if not ok_write then
			missed[#missed + 1] = probe.ft
		else
			local ok_edit = pcall(vim.cmd.edit, { args = { vim.fn.fnameescape(path) }, mods = { silent = true } })
			if not ok_edit then
				missed[#missed + 1] = probe.ft
			else
				-- Let the filetype autocmds run, then wait (briefly) for a server.
				vim.wait(200)
				local bufnr = vim.api.nvim_get_current_buf()
				vim.wait(3000, function()
					return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
				end, 50)
				local clients = {}
				for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
					clients[#clients + 1] = c.name
				end
				covered[#covered + 1] = {
					ft = vim.bo[bufnr].filetype,
					requested = probe.ft,
					clients = clients,
				}
			end
		end
	end
	-- The quickfix window: quicker.nvim maps < and > buffer-locally there.
	pcall(function()
		vim.fn.setqflist({ { filename = dir .. "/" .. PROBES[1].name, lnum = 1, text = "probe" } })
		vim.cmd("copen")
		vim.wait(300)
		covered[#covered + 1] = { ft = "qf", requested = "qf", clients = {} }
		vim.cmd("cclose")
	end)
	return covered, missed
end

-- The keymap table as it stands after boot. The driver diffs this against
-- what we saw being created: anything left over came from somewhere these
-- wrappers cannot watch (a vimscript `:map`, a runtime plugin like matchit),
-- which is a coverage fact worth stating rather than hiding.
local function final_table()
	local all = {}
	for _, mode in ipairs(MODES) do
		local ok, maps = pcall(vim.api.nvim_get_keymap, mode)
		if ok then
			for _, m in ipairs(maps) do
				all[#all + 1] = { mode = mode, key = canonical(m.lhs), desc = m.desc }
			end
		end
	end
	return all
end

vim.defer_fn(function()
	local unloaded = load_everything()
	local buffers, missed_probes = probe_buffers()

	local base_list = {}
	for entry, desc in pairs(baseline) do
		local mode, key = entry:match("^(.-)\t(.*)$")
		base_list[#base_list + 1] = { mode = mode, key = key, desc = desc }
	end

	local payload = {
		version = 1,
		nvim = tostring(vim.version()),
		log = log,
		lazy_keys = lazy_keys(),
		defaults = base_list,
		final = final_table(),
		unloaded_plugins = unloaded,
		buffers_probed = buffers,
		probes_failed = missed_probes,
		notes = notes,
	}

	if not out_path or out_path == "" then
		io.stderr:write("keymap_inventory: KEYMAP_OUT is not set\n")
		vim.cmd("cq")
		return
	end
	local ok, err = pcall(function()
		local fh = assert(io.open(out_path, "w"))
		fh:write(vim.json.encode(payload))
		fh:close()
	end)
	if not ok then
		io.stderr:write("keymap_inventory: could not write " .. out_path .. ": " .. tostring(err) .. "\n")
		vim.cmd("cq")
		return
	end
	io.stderr:write(("keymap_inventory: %d set calls -> %s\n"):format(#log, out_path))
	-- `qa!`, never `qa`: a modified listed buffer blocks headless forever on
	-- the unsaved-changes prompt.
	vim.cmd("qa!")
end, wait_ms)
