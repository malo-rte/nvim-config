-- plugins/git-conflict.lua
--
-- In-buffer conflict handling: navigation, choose-a-side, highlighting.
-- Mappings are set buffer-local only when a conflict is detected, so they
-- never shadow the `c` change operator in normal buffers.
--
--   ]x / [x            next / previous conflict
--   <leader>gco        take OURS    (the <<<<<<< side)
--   <leader>gct        take THEIRS  (the >>>>>>> side)
--   <leader>gcb        take BOTH
--   <leader>gc0        take NEITHER
--
-- NOTE: during a rebase, ours/theirs are inverted from intuition:
--   <<<<<<< HEAD  == the branch you're rebasing ONTO (upstream)
--   >>>>>>> ...   == your commit being replayed
-- These actions operate on the marker content, so just keep that straight.

return {
	"akinsho/git-conflict.nvim",
	version = "*",
	event = "VeryLazy",
	opts = {
		default_mappings = false,
		default_commands = true, -- :GitConflictListQf etc. still available
		disable_diagnostics = true, -- markers break syntax; quiet the LSP while resolving
		list_opener = "copen",
		highlights = {
			incoming = "DiffAdd",
			current = "DiffText",
		},
	},
	config = function(_, o)
		require("git-conflict").setup(o)

		-- Global maps: leader-prefixed so they don't shadow the `c` operator,
		-- and always visible in which-key. They no-op outside a conflict.
		local function m(lhs, plug, desc)
			vim.keymap.set("n", lhs, plug, { desc = desc })
		end
		m("]x", "<Plug>(git-conflict-next-conflict)", "Next conflict")
		m("[x", "<Plug>(git-conflict-prev-conflict)", "Prev conflict")
		m("<leader>gco", "<Plug>(git-conflict-ours)", "Conflict: take ours (<<<)")
		m("<leader>gct", "<Plug>(git-conflict-theirs)", "Conflict: take theirs (>>>)")
		m("<leader>gcb", "<Plug>(git-conflict-both)", "Conflict: take both")
		m("<leader>gc0", "<Plug>(git-conflict-none)", "Conflict: take neither")
	end,
}
