local opts = {
	mappings = {
		around = "a",
		inside = "i",
		around_next = "an",
		inside_next = "in",
		around_last = "al",
		inside_last = "il",
		goto_left = "g[",
		goto_right = "g]",
	},
	n_lines = 50,
	search_method = "cover_or_next",
	silent = false,
}

return {
	"echasnovski/mini.ai",
	version = "*", -- keep "*" if you prefer releases
	opts = opts,
	config = function(_, o)
		local ai = require("mini.ai")
		local ts = ai.gen_spec.treesitter

		-- attach your Treesitter-powered textobjects now that the module is loaded
		o.custom_textobjects = {
			f = ts({ a = "@function.outer", i = "@function.inner" }),
			c = ts({ a = "@class.outer", i = "@class.inner" }),
			a = ts({ a = "@parameter.outer", i = "@parameter.inner" }),
			b = ts({
				a = { "@block.outer", "@conditional.outer", "@loop.outer" },
				i = { "@block.inner", "@conditional.inner", "@loop.inner" },
			}),
			C = ts({ a = "@comment.outer", i = "@comment.inner" }), -- requires comment queries
		}

		ai.setup(o)
	end,
}
