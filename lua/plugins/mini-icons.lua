-- Align mini.icons (used by render-markdown) to the same spec file-type glyphs
-- as devicons, so code-block/file icons match everywhere (DEV-TOOLS-DES-0004).
-- Glyphs come from the generated map (scripts/gen_ftype_icons.py); colour/hl is
-- left to mini.icons' defaults (§89 leaves colour to the theme).
local ft = require("utils.ftype_icons")

local function glyphs(map)
	local out = {}
	for k, g in pairs(map) do
		out[k] = { glyph = g }
	end
	return out
end

return {
	"nvim-mini/mini.icons",
	version = "*",
	lazy = false,
	priority = 900,
	config = function()
		require("mini.icons").setup({
			extension = glyphs(ft.by_extension),
			file = glyphs(ft.by_filename),
			directory = glyphs(ft.by_directory),
		})
	end,
}
