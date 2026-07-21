local M = {}
local uv = vim.uv
local islist = vim.islist

local DATA_DIR = vim.fn.stdpath("data") .. "/nerdfont"
local MAP_PATH = DATA_DIR .. "/glyphnames.json"
local CACHE_PATH = DATA_DIR .. "/mru_cache.json"
local CACHE_SIZE = 200
-- Pin the glyph mapping to a released Nerd Fonts tag, not `master`
-- (DEV-TOOLS-DES-0004 §91: code points must not shift silently between
-- releases). Keep this in sync with utils.icons M.nerd_font.mapping_version.
local MAPPING_VERSION = "v3.4.0"
local REMOTE_URL = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/"
	.. MAPPING_VERSION
	.. "/glyphnames.json"

-- -------- Internal state -----------------------------------------------------------
local map_loaded = false
local name_to_code = {} -- full map: name -> integer codepoint
local mru_cache = {} -- name -> { code=integer, ts=number }
local last_ts = 0

-- -------- Utilities ----------------------------------------------------------------
local function ensure_dir(path)
	-- Create parent directory if missing
	local stat = uv.fs_stat(path)
	if stat and stat.type == "directory" then
		return true
	end
	-- Recursively create
	return vim.fn.mkdir(path, "p") == 1
end

local function read_file(path)
	local fd = uv.fs_open(path, "r", 420) -- 0644
	if not fd then
		return nil
	end
	local stat = uv.fs_fstat(fd)
	if not stat then
		uv.fs_close(fd)
		return nil
	end
	local data = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)
	return data
end

local function write_file(path, data)
	ensure_dir(DATA_DIR)
	local fd = uv.fs_open(path, "w", 420)
	if not fd then
		return false
	end
	uv.fs_write(fd, data, 0)
	uv.fs_close(fd)
	return true
end

local function now()
	last_ts = last_ts + 1
	return os.time() + last_ts * 1e-6
end

local function mru_save()
	local list = {}
	for name, entry in pairs(mru_cache) do
		table.insert(list, { name = name, code = entry.code, ts = entry.ts })
	end
	table.sort(list, function(a, b)
		return a.ts > b.ts
	end)
	-- trim
	while #list > CACHE_SIZE do
		table.remove(list)
	end
	-- back to map for quick load next time
	local out = {}
	for _, it in ipairs(list) do
		out[it.name] = { code = it.code, ts = it.ts }
	end
	write_file(CACHE_PATH, vim.json.encode(out))
end

local function mru_load()
	local data = read_file(CACHE_PATH)
	if not data or #data == 0 then
		return
	end
	local ok, decoded = pcall(vim.json.decode, data)
	if not ok or type(decoded) ~= "table" then
		return
	end
	mru_cache = decoded
	-- keep last_ts ahead to preserve ordering
	for _, entry in pairs(mru_cache) do
		if type(entry.ts) == "number" and entry.ts > last_ts then
			last_ts = entry.ts
		end
	end
end

local function mru_touch(name, code)
	local entry = mru_cache[name]
	if entry then
		entry.ts = now()
	else
		mru_cache[name] = { code = code, ts = now() }
	end
	mru_save()
end

local function hex_to_int(s)
	if type(s) == "number" then
		return s
	end
	if type(s) ~= "string" then
		return nil
	end
	s = s:gsub("^0x", ""):gsub("^U%+", "")
	local n = tonumber(s, 16)
	return n
end

local function utf8_from_code(code)
	-- Prefer Vim’s nr2char which handles UTF-8 correctly.
	return vim.fn.nr2char(code)
end

local function load_map_from_disk()
	if map_loaded then
		return true
	end
	local data = read_file(MAP_PATH)
	if not data or #data == 0 then
		return false
	end
	local ok, decoded = pcall(vim.json.decode, data)
	if not ok or type(decoded) ~= "table" then
		return false
	end

	local tmp = {}
	-- Accept formats:
	-- 1) array of { name = "...", codepoint = "f101" }
	-- 2) map { ["nf-..."] = "f101" } or { ["nf-..."] = 61713 }
	if islist(decoded) then
		for _, item in ipairs(decoded) do
			local nm = item.name or item.glyph or item.key
			local cp = item.codepoint or item.code or item.cp
			if nm and cp then
				local n = hex_to_int(cp)
				if n then
					tmp[nm] = n
				end
			end
		end
	else
		for nm, val in pairs(decoded) do
			local cp
			if type(val) == "table" then
				cp = val.code or val.codepoint or val.cp or val.value
			else
				cp = val
			end
			local n = hex_to_int(cp)
			if n then
				tmp[nm] = n -- bare name, e.g. "md-home"
				tmp["nf-" .. nm] = n -- alias with "nf-" for convenience
			end
		end
	end

	name_to_code = tmp
	map_loaded = true
	return true
end

local function file_mtime_secs(path)
	local st = uv.fs_stat(path)
	if not st then
		return nil
	end
	local mt = st.mtime
	if type(mt) == "table" then -- luv on some platforms
		return mt.sec
	elseif type(mt) == "number" then -- some builds expose seconds directly
		return mt
	end
	return nil
end

local function should_update_now(force)
	if force then
		return true
	end
	-- Only fetch when there is no map on disk yet (first-run bootstrap). The
	-- mapping is pinned (MAPPING_VERSION), so there is no periodic auto-refresh
	-- that could shift code points; an explicit update(true) re-fetches the pin.
	return file_mtime_secs(MAP_PATH) == nil
end

local function done(cb, ...)
	if not cb then
		return
	end
	if vim.in_fast_event and vim.in_fast_event() then
		return vim.schedule_wrap(cb)(...) -- captures & unpacks safely
	end
	cb(...)
end

-- Try to load cache eagerly on first require
mru_load()

-- -------- Public: get_code / get_utf8 ---------------------------------------------
function M.get_code(name)
	if type(name) ~= "string" then
		return nil
	end

	-- 1) MRU cache (fast path, even before JSON map is loaded)
	local c = mru_cache[name]
	if c and type(c.code) == "number" then
		mru_touch(name, c.code)
		return c.code
	end

	-- 2) Full map (load if present on disk)
	if not map_loaded then
		load_map_from_disk()
	end
	local code = name_to_code[name]
	if type(code) == "number" then
		mru_touch(name, code)
		return code
	end

	-- 3) Not found
	return nil
end

function M.get_utf8(name)
	local code = M.get_code(name)
	if not code then
		return nil
	end
	return utf8_from_code(code)
end

-- Fetch latest JSON from GitHub and refresh map.
-- Signature: update(force?, callback?)
--  - force: boolean (optional) — set true to bypass the 1-week check.
--  - callback(err, count|nil, skipped|nil)
--      * on success after fetch: (nil, entry_count, false)
--      * skipped (already fresh): (nil, nil, true)
--      * error: (string_err, 0, false)

function M.update(force, callback)
	ensure_dir(DATA_DIR)

	if not should_update_now(force) then
		return done(callback, nil, nil, true)
	end

	local function handle_json(text)
		local ok, decoded = pcall(vim.json.decode, text)
		if not ok then
			return done(callback, "Failed to decode JSON from upstream", 0, false)
		end

		write_file(MAP_PATH, vim.json.encode(decoded))

		map_loaded = false
		if not load_map_from_disk() then
			return done(callback, "Saved but failed to parse on reload", 0, false)
		end

		local count = 0
		for _ in pairs(name_to_code) do
			count = count + 1
		end
		return done(callback, nil, count, false)
	end

	if vim.system then
		vim.system({ "curl", "-fsSL", REMOTE_URL }, { text = true }, function(res)
			if res.code ~= 0 then
				return done(callback, "curl failed: " .. (res.stderr or ("code " .. tostring(res.code))), 0, false)
			end
			handle_json(res.stdout or "")
		end)
	else
		local out = vim.fn.system({ "curl", "-fsSL", REMOTE_URL })
		local ok = (vim.v.shell_error == 0)
		if not ok then
			return done(callback, "curl failed: " .. tostring(out), 0, false)
		end
		handle_json(out)
	end
end

function M.init()
	M.update(false, function(err, count, skipped)
		vim.schedule(function()
			if err then
				vim.notify("nerdfont update failed: " .. err, vim.log.levels.WARN)
			elseif skipped then
				-- vim.notify("nerdfont map is already fresh (skipped)")
			else
				vim.notify(("nerdfont map updated (%d entries)"):format(count))
			end
		end)
	end)

	load_map_from_disk()
end

-- Return a list of all glyphs for Telescope
function M.list_all()
	local data = read_file(MAP_PATH)
	if not data or #data == 0 then
		return {}
	end
	local ok, decoded = pcall(vim.json.decode, data)
	if not ok or type(decoded) ~= "table" then
		return {}
	end

	local items = {}
	if islist(decoded) then
		-- Array form: { { name="...", code="..." }, ... }
		for _, item in ipairs(decoded) do
			local nm = item.name or item.glyph or item.key
			local cp = item.code or item.codepoint or item.cp
			if nm and cp then
				local n = hex_to_int(cp)
				if n then
					table.insert(items, {
						name = nm,
						code = n,
						char = utf8_from_code(n),
						display = string.format("%s %s", utf8_from_code(n), nm),
					})
				end
			end
		end
	else
		-- Map form: { ["name"] = "f101" } or { ["name"] = { code="f101" } }
		for nm, val in pairs(decoded) do
			local cp
			if type(val) == "table" then
				cp = val.code or val.codepoint or val.cp or val.value
			else
				cp = val
			end
			local n = hex_to_int(cp)
			if n then
				table.insert(items, {
					name = nm,
					code = n,
					char = utf8_from_code(n),
					display = string.format("%s %s", utf8_from_code(n), nm),
				})
			end
		end
	end

	return items
end

return M
