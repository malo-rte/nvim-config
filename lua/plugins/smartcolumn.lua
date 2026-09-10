-- plugins/smartcolumn.lua
--
-- Hide the colorcolumn until a line actually needs it: the ruler appears only
-- once something in view crosses the limit, so it reads as a warning rather
-- than permanent furniture down the middle of every buffer.
--
-- The limit itself still comes from 'colorcolumn' in config/options.lua and is
-- read from there rather than repeated here, so the two cannot drift. A
-- project's .editorconfig max_line_length overrides it (the plugin honours
-- editorconfig by default, and options.lua enables vim.g.editorconfig).
return {
	"m4xshen/smartcolumn.nvim",
	event = { "BufReadPost", "BufNewFile" },

	opts = {
		-- Whatever options.lua set; plugin specs are evaluated after
		-- config.options runs, so this is the real value.
		colorcolumn = vim.o.colorcolumn,

		-- The plugin's default scope is "file", which re-reads and measures
		-- every line of the buffer on every CursorMoved and CursorMovedI.
		-- "window" measures only the visible lines -- the same answer for what
		-- you can actually see, and it doesn't scale with file size.
		scope = "window",

		-- Prose, sidebars and generated buffers: a ruler there is noise, not a
		-- limit. (gitcommit is deliberately absent -- see custom_colorcolumn.)
		disabled_filetypes = {
			"help",
			"text",
			"markdown",
			"man",
			"checkhealth",
			"lspinfo",
			"qf",
			"neo-tree",
			"lazy",
			"mason",
			"notify",
			"TelescopePrompt",
			"dap-repl",
		},

		-- Git's own convention for the commit message body. Drop this entry if
		-- you'd rather gitcommit followed the global limit.
		custom_colorcolumn = { gitcommit = "72" },
	},

	config = function(_, o)
		require("smartcolumn").setup(o)

		-- setup() only installs autocmds; nothing has looked at the buffer that
		-- is already open, so the global 'colorcolumn' would stay drawn until
		-- the first cursor move. Evaluate the current buffer once, now.
		vim.api.nvim_exec_autocmds("BufEnter", {})
	end,
}
