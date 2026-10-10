-- Obsidian-like note database over a folder of markdown: [[wikilinks]] with
-- completion + follow, backlinks, tags, daily notes, templates, frontmatter.
-- Display is left to render-markdown.nvim (obsidian's own UI is disabled to
-- avoid double conceal/rendering). Search/switch use your existing Telescope.
--
-- The vault is per-project: the workspace resolves to the current project's
-- `.vault/` (created + git-ignored on demand by config.vault). Open it with
-- <leader>ov / :Vault. See lua/config/vault.lua.
return {
	"obsidian-nvim/obsidian.nvim",
	version = "*",
	ft = "markdown",
	dependencies = { "nvim-lua/plenary.nvim" },
	---@module 'obsidian'
	---@type obsidian.config
	opts = {
		workspaces = {
			{
				name = "project",
				path = function()
					return require("config.vault").ensure()
				end,
			},
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

		-- Wikilink/tag completion arrives through the LSP source of blink.cmp:
		-- obsidian.nvim serves it from a built-in `obsidian-ls` server rather
		-- than a completion-plugin integration, which is why the old
		-- `nvim_cmp` / `blink` switches are gone (they are deprecated and nil'd
		-- out by the plugin; removed in obsidian.nvim 4.0). Nothing to opt into
		-- here -- blink's `lsp` source is already enabled in plugins/blink.lua.
		completion = {
			min_chars = 2,
		},

		picker = { name = "telescope.nvim" },

		-- render-markdown.nvim owns display; keep obsidian's UI off so they
		-- don't fight over conceal.
		ui = { enable = false },

		-- `Obsidian <subcommand>`, not the old `ObsidianSubcommand` camel-case
		-- commands: the keys below already use the new form, and leaving this
		-- at its default of true only registers a second set of commands and
		-- warns about them on every load (they go away in obsidian.nvim 4.0).
		legacy_commands = false,

		-- No follow_url_func: it is deprecated (removed in obsidian.nvim 3.18)
		-- and the plugin now opens URLs with vim.ui.open itself, which is
		-- exactly what the function here used to do.
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
