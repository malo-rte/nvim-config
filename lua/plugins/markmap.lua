-- Mindmaps: render the current markdown's heading tree as an interactive
-- mindmap in the browser. Requires the `markmap-cli` binary on PATH (Node);
-- the dev container installs it, and on NixOS provide it via nix.
return {
	"Zeioth/markmap.nvim",
	cmd = { "MarkmapOpen", "MarkmapSave", "MarkmapWatch", "MarkmapWatchStop" },
	ft = "markdown",
	opts = {
		html_output = vim.fn.stdpath("cache") .. "/markmap.html",
		hide_toolbar = false,
		grace_period = 3600000,
	},
	config = function(_, o)
		require("markmap").setup(o)
	end,
	keys = {
		{ "<leader>om", "<cmd>MarkmapOpen<cr>", desc = "Mindmap: open (markmap)" },
		{ "<leader>oM", "<cmd>MarkmapWatch<cr>", desc = "Mindmap: live watch" },
	},
}
