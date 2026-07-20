local opts = {
	-- Module mappings. Use `''` (empty string) to disable one.
	mappings = {
		-- Move visual selection in Visual mode. Defaults are Alt (Meta) + hjkl.
		left = "<C-Left>",
		right = "<C-Right>",
		down = "<C-Down>",
		up = "<C-Up>",

		-- Move current line in Normal mode
		line_left = "<C-Left>",
		line_right = "<C-Right>",
		line_down = "<C-Down>",
		line_up = "<C-Up>",
	},

	-- Options which control moving behavior
	options = {
		-- Automatically reindent selection during linewise vertical move
		reindent_linewise = true,
	},
}

return {
	"nvim-mini/mini.move",
	version = "*",
	opts = opts,

	config = function(_, o)
		local mm = require("mini.move")
		mm.setup(o)
	end,
}
