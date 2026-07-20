-- Apply the DEV-TOOLS-DES-0004 §2-32 file-type glyphs as a nvim-web-devicons
-- override. The glyph map is generated from the spec (see
-- scripts/gen_ftype_icons.py -> lua/utils/ftype_icons.lua); here we only swap
-- the glyph and keep devicons' own colour/name, since the spec leaves colour
-- to the theme (§89). neo-tree and lualine both read devicons, so this makes
-- file-type icons consistent everywhere.
--
-- devicons.setup() runs once (it self-guards), so the override must be passed
-- in that single call. Default colours are read straight from the theme module
-- (no setup needed) so each overridden entry keeps its colour.
return {
	"nvim-tree/nvim-web-devicons",
	lazy = false,
	priority = 900,
	config = function()
		local devicons = require("nvim-web-devicons")
		local theme = require("nvim-web-devicons.icons-default")
		local spec = require("utils.ftype_icons")
		local def_ext = theme.icons_by_file_extension or {}
		local def_file = theme.icons_by_filename or {}
		local fallback = { color = "#6d8086", cterm_color = "66" }

		-- Build an override table, taking each entry's colour/name from the
		-- default theme where it exists (filename keys are matched case-
		-- insensitively by devicons, so lower them).
		-- devicons builds a "DevIcon<name>" highlight group, so a fabricated
		-- name for a new key must be sanitized to word characters (keys like
		-- "cargo.toml", "c++", ".gitignore" would otherwise raise E5248).
		local function sanitize(s)
			return "Ft_" .. (s:gsub("[^%w]+", "_"))
		end

		local function build(defs, map, lower)
			local out = {}
			for key, glyph in pairs(map) do
				local k = lower and key:lower() or key
				local e = defs[k] or defs[key] or {}
				out[k] = {
					icon = glyph,
					color = e.color or fallback.color,
					cterm_color = e.cterm_color or fallback.cterm_color,
					name = e.name or sanitize(k),
				}
			end
			return out
		end

		devicons.setup({
			default = true,
			override_by_extension = build(def_ext, spec.by_extension, false),
			override_by_filename = build(def_file, spec.by_filename, true),
		})
	end,
}
