-- plugins/git.lua
--
-- Two layers:
--   * diffview.nvim -> toggleable "VSCode Source Control" style view:
--       a changed-files panel on the left, the diff on the right.
--       Also file history browsing + merge-conflict resolution.
--   * mini.diff     -> inline gutter change markers + hunk apply/reset/nav,
--       matching the rest of your mini.nvim suite.
--
-- Keymaps (<leader>g = Git group):
--   <leader>gd  toggle Diffview (working tree vs index/HEAD)
--   <leader>gs  toggle Diffview of *staged* changes (HEAD vs index)
--   <leader>gf  file history of the current file
--   <leader>gF  file history of the whole repo
--   <leader>gx  close Diffview (when focus is elsewhere)
--   <leader>go  toggle mini.diff inline overlay
-- mini.diff (defaults): gh apply hunk, gH reset hunk, [h ]h prev/next hunk,
--   [H ]H first/last hunk, gh as a hunk textobject.

return {
	{
		"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFileHistory" },
		keys = {
			{
				"<leader>gd",
				function()
					-- Toggle: close if a Diffview tab is already open, else open.
					local ok, lib = pcall(require, "diffview.lib")
					if ok and lib.get_current_view() then
						vim.cmd("DiffviewClose")
					else
						vim.cmd("DiffviewOpen")
					end
				end,
				desc = "Diffview: toggle (working tree)",
			},
			{ "<leader>gs", "<cmd>DiffviewOpen --cached<cr>", desc = "Diffview: staged (HEAD vs index)" },
			{ "<leader>gf", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history (current file)" },
			{ "<leader>gF", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: file history (repo)" },
			{ "<leader>gx", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
		},
		opts = {
			enhanced_diff_hl = true, -- richer intra-line diff highlighting
			view = {
				default = { layout = "diff2_horizontal" }, -- side-by-side, VSCode-like
				merge_tool = { layout = "diff3_mixed", disable_diagnostics = true },
			},
			file_panel = {
				listing_style = "tree",
				win_config = { position = "left", width = 32 },
			},
			keymaps = {
				view = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } } },
				file_panel = { { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Close Diffview" } } },
			},
		},
	},

	{
		"echasnovski/mini.diff",
		version = "*",
		opts = {
			view = {
				style = "sign",
				signs = { add = "▎", change = "▎", delete = "" },
			},
			-- mappings left at sensible defaults: gh/gH apply/reset, [h ]h nav.
		},
		config = function(_, o)
			local diff = require("mini.diff")
			diff.setup(o)
			vim.keymap.set("n", "<leader>go", function()
				diff.toggle_overlay(0)
			end, { desc = "Git: toggle inline diff overlay" })
		end,
	},
}
