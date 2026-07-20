-- plugins/which-key.lua
local opts = {
	preset = "helix",
	delay = 0, -- try 200 if instant feels too eager
	win = { height = { max = 40 }, border = "rounded" },
	plugins = {
		marks = true,
		registers = true,
		spelling = { enabled = true },
		presets = {
			operators = true,
			motions = true,
			text_objects = true,
			windows = true,
			nav = true,
			z = true,
			g = true,
		},
	},
	icons = { rules = false, breadcrumb = "» ", separator = "→ ", group = "+ " },
}

return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = opts,
	config = function(_, o)
		local wk = require("which-key")
		wk.setup(o)
		wk.add({
			{ "<leader>b", group = "Buffers" },
			{ "<leader>c", group = "Code" },
			{ "<leader>d", group = "Debug" },
			{ "<leader>ct", group = "Toggle" },
			{ "<leader>f", group = "Find/File" },
			{ "<leader>g", group = "Git" },
			{ "<leader>gc", group = "Conflict" },
			{ "<leader>gr", group = "Rebase" },
			{ "<leader>i", group = "Insert" },
			{ "<leader>in", group = "Insert Nerdfont" },
			{ "<leader>o", group = "Obsidian/Notes" },
			{ "<leader>w", group = "Windows" },
			{ "<leader>q", group = "Sessions" },
			{ "<leader>t", group = "Toggle" },
			{ "<leader>u", group = "UI" },
			{ "<leader>y", group = "Yocto" },
		})
	end,
}
