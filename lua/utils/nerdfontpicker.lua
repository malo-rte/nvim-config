local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local function to_codepoint(v)
	if type(v) == "number" then
		return v
	end
	if type(v) ~= "string" then
		return nil
	end
	-- try U+XXXX from either "U+F118E" or "<U+F118E>"
	local u = v:match("U%+([%x]+)") or v:match("<U%+([%x]+)>")
	if u then
		return tonumber(u, 16)
	end
	-- strip 0x / U+ prefixes if present
	local hex = v:gsub("^0x", ""):gsub("^U%+", "")
	if hex:match("^[%x]+$") then
		return tonumber(hex, 16)
	end
	return nil
end

local function load_glyphs()
	local path = vim.fn.stdpath("data") .. "/nerdfont/glyphnames.json"
	local f = io.open(path, "r")
	if not f then
		vim.notify("Nerd Font glyph map not found at " .. path, vim.log.levels.ERROR)
		return {}
	end
	local data = f:read("*a")
	f:close()
	local ok, decoded = pcall(vim.json.decode, data)
	if not ok or type(decoded) ~= "table" then
		vim.notify("Failed to parse glyphnames.json", vim.log.levels.ERROR)
		return {}
	end

	local list = {}
	-- your file is a map: { ["md-foo"] = { code="f1234", char="<U+F1234>" }, ... }
	for name, entry in pairs(decoded) do
		local cp
		if type(entry) == "table" then
			cp = entry.code or entry.codepoint or entry.cp or entry.value
			if not cp and entry.char then
				cp = entry.char -- like "<U+F118E>"
			end
		else
			cp = entry
		end
		local n = to_codepoint(cp)
		if n then
			local ch = vim.fn.nr2char(n)
			table.insert(list, {
				name = name,
				char = ch,
				code = n,
			})
		end
	end

	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

local function nerd_font_picker(action, field)
	local items = load_glyphs()
	pickers
		.new({}, {
			prompt_title = "Nerd Font Picker (" .. action .. " " .. field .. ")",
			finder = finders.new_table({
				results = items,
				entry_maker = function(item)
					return {
						value = item,
						display = string.format("%s  %s", item.char, item.name),
						ordinal = item.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(bufnr, _)
				actions.select_default:replace(function()
					local sel = action_state.get_selected_entry()
					actions.close(bufnr)
					local text = (field == "name") and sel.value.name or sel.value.char
					if action == "insert" then
						vim.api.nvim_put({ text }, "", true, true)
					elseif action == "yank" then
						vim.fn.setreg('"', text)
						vim.fn.setreg("+", text)
						vim.fn.setreg("*", text)
						vim.notify("Yanked: " .. text)
					end
				end)
				return true
			end,
		})
		:find()
end

-- :NerdFontPicker yank name
-- :NerdFontPicker insert char
vim.api.nvim_create_user_command("NerdFontPicker", function(cmd)
	local args = vim.split(cmd.args, "%s+")
	local action = args[1]
	local field = args[2]
	if (action ~= "yank" and action ~= "insert") or (field ~= "name" and field ~= "char") then
		vim.notify("Usage: :NerdFontPicker <yank|insert> <name|char>", vim.log.levels.ERROR)
		return
	end
	nerd_font_picker(action, field)
end, {
	nargs = "+",
	complete = function(_, line)
		local parts = vim.split(line, "%s+")
		if #parts == 2 then
			return { "yank", "insert" }
		elseif #parts == 3 then
			return { "name", "char" }
		end
		return {}
	end,
	desc = "Pick a Nerd Font glyph and yank or insert it",
})
