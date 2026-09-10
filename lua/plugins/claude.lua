-- plugins/claude.lua
--
-- Claude Code (coder/claudecode.nvim) -- IDE-protocol integration with the
-- `claude` CLI. It runs a local WebSocket server that the CLI auto-detects on
-- launch, which is what the official VS Code / JetBrains extensions do; Neovim
-- is not officially supported, this is a pure-Lua reimplementation of the same
-- protocol. So Claude sees the current file and selection, and its edits arrive
-- as a real Neovim diff you can review instead of silent writes to disk.
--
-- The "native" terminal provider uses Neovim built-ins, so this needs no
-- dependencies -- notably not snacks.nvim, which this config doesn't use.
--
-- Keymaps (<leader>a = AI/Claude group):
--   <M-a>        toggle + focus Claude (also from inside its terminal)
--   <leader>ac   toggle Claude
--   <leader>af   focus Claude
--   <leader>ar   resume a previous session
--   <leader>aC   continue the last session
--   <leader>am   select model
--   <leader>ab   add the current buffer as context
--   <leader>as   send visual selection (v) / add file from neo-tree (n)
--   <leader>aa   accept diff (or just :w)
--   <leader>ad   deny diff   (or just :q)
-- Inside the terminal, <Esc> belongs to Claude (it interrupts a running turn),
-- so use <M-n> to reach normal mode for scrolling/copying -- see config/keymaps.
--
-- Buffers whose file Claude edits outside the diff flow are reloaded by the
-- checktime autocmd in config/autocmds.lua -- it lives there, not here, because
-- this plugin is lazy and the reload has to work before Claude is ever opened.

local opts = {
	terminal = {
		provider = "native",
		split_side = "right",
		split_width_percentage = 0.30,
		auto_insert = true,
		auto_close = true,
	},
	diff_opts = { layout = "vertical" },
}

return {
	"coder/claudecode.nvim",
	cmd = {
		"ClaudeCode",
		"ClaudeCodeFocus",
		"ClaudeCodeSelectModel",
		"ClaudeCodeAdd",
		"ClaudeCodeSend",
		"ClaudeCodeTreeAdd",
		"ClaudeCodeStatus",
		"ClaudeCodeStart",
		"ClaudeCodeStop",
		"ClaudeCodeOpen",
		"ClaudeCodeClose",
		"ClaudeCodeDiffAccept",
		"ClaudeCodeDiffDeny",
		"ClaudeCodeCloseAllDiffs",
	},
	keys = {
		{ "<M-a>", "<cmd>ClaudeCodeFocus<cr>", mode = { "n", "t" }, desc = "Claude: toggle + focus" },
		{ "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Claude: toggle" },
		{ "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude: focus" },
		{ "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Claude: resume session" },
		{ "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Claude: continue last session" },
		{ "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Claude: select model" },
		{ "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude: add current buffer" },
		{ "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude: send selection" },
		{ "<leader>as", "<cmd>ClaudeCodeTreeAdd<cr>", ft = "neo-tree", desc = "Claude: add file" },
		{ "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Claude: accept diff" },
		{ "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Claude: deny diff" },
	},
	opts = opts,
}
