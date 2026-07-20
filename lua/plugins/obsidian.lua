-- Obsidian-like note database over a folder of markdown: [[wikilinks]] with
-- completion + follow, backlinks, tags, daily notes, templates, frontmatter.
-- Display is left to render-markdown.nvim (obsidian's own UI is disabled to
-- avoid double conceal/rendering). Search/switch use your existing Telescope.
--
-- Vault location: change the workspace path below to point at your vault.
local vault = vim.fn.expand("~/notes")

return {
	"obsidian-nvim/obsidian.nvim",
	version = "*",
	ft = "markdown",
	dependencies = { "nvim-lua/plenary.nvim" },
	---@module 'obsidian'
	---@type obsidian.config
	opts = {
		workspaces = {
			{ name = "notes", path = vault },
		},
		notes_subdir = "notes",
		new_notes_location = "notes_subdir",

		daily_notes = {
			folder = "dailies",
			date_format = "%Y-%m-%d",
		},
		templates = {
			folder = "templates",
			date_format = "%Y-%m-%d",
			time_format = "%H:%M",
		},

		-- Wikilink/tag completion via blink.cmp (you use blink, not nvim-cmp).
		completion = {
			nvim_cmp = false,
			blink = true,
			min_chars = 2,
		},

		picker = { name = "telescope.nvim" },

		-- render-markdown.nvim owns display; keep obsidian's UI off so they
		-- don't fight over conceal.
		ui = { enable = false },

		follow_url_func = function(url)
			vim.ui.open(url)
		end,
	},
	keys = {
		{ "<leader>on", "<cmd>Obsidian new<cr>", desc = "Obsidian: new note" },
		{ "<leader>oo", "<cmd>Obsidian quick_switch<cr>", desc = "Obsidian: quick switch" },
		{ "<leader>os", "<cmd>Obsidian search<cr>", desc = "Obsidian: search (grep)" },
		{ "<leader>ot", "<cmd>Obsidian today<cr>", desc = "Obsidian: today's daily" },
		{ "<leader>oy", "<cmd>Obsidian yesterday<cr>", desc = "Obsidian: yesterday's daily" },
		{ "<leader>ob", "<cmd>Obsidian backlinks<cr>", desc = "Obsidian: backlinks" },
		{ "<leader>og", "<cmd>Obsidian tags<cr>", desc = "Obsidian: tags" },
		{ "<leader>ol", "<cmd>Obsidian links<cr>", desc = "Obsidian: links in note" },
		{ "<leader>of", "<cmd>Obsidian follow_link<cr>", desc = "Obsidian: follow link" },
		{ "<leader>oT", "<cmd>Obsidian template<cr>", desc = "Obsidian: insert template" },
		{ "<leader>or", "<cmd>Obsidian rename<cr>", desc = "Obsidian: rename note" },
		{ "<leader>ox", "<cmd>Obsidian toggle_checkbox<cr>", desc = "Obsidian: toggle checkbox" },
	},
}
