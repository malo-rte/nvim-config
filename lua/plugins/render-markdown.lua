return {
	"MeanderingProgrammer/render-markdown.nvim",
	-- Only ever renders markdown, so let the filetype pull it in rather than
	-- loading it in every session.
	ft = { "markdown", "markdown.mdx" },
	-- dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.nvim" }, -- if you use the mini.nvim suite
	dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" }, -- if you use standalone mini plugins
	-- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
	---@module 'render-markdown'
	---@type render.md.UserConfig

	opts = {
		completions = {
			lsp = { enabled = true },
		},
	},

	config = function(_, o)
		require("render-markdown").setup(o)
	end,
}
