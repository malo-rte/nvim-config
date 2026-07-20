local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

-- Glyph parsing lives in utils.nerdfont (single source of truth for
-- glyphnames.json). list_all() returns { name, char, code, display };
-- we only sort by name here for a stable picker order.
local nerdfont = require("utils.nerdfont")

local function load_glyphs()
	local list = nerdfont.list_all()
	if #list == 0 then
		vim.notify(
			"Nerd Font glyph map not available (run :lua require('utils.nerdfont').update(true))",
			vim.log.levels.ERROR
		)
		return {}
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
