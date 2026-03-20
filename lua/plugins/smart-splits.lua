local opts = {
	ignored_buftypes = { "nofile", "quickfix", "prompt" },
	ignored_filetypes = { "NvimTree", "neo-tree" },
	default_amount = 2,

	at_edge = function(ctx)
		if ctx.mux and ctx.mux.type == "tmux" then
			return "wrap"
		end
		return "stop"
	end,

	float_win_behavior = "previous",
	move_cursor_same_row = false,
	cursor_follows_swapped_bufs = false,

	ignored_events = { "BufEnter", "WinEnter" },

	multiplexer_integration = nil,
	disable_multiplexer_nav_when_zoomed = true,
	kitty_password = nil,
	zellij_move_focus_or_tab = false,
	log_level = "info",
}

return {
	{
		"mrjones2014/smart-splits.nvim",
		build = "./kitty/install-kittens.bash",
		lazy = false,
		opts = opts,
		config = function(_, o)
			local ss = require("smart-splits")
			ss.setup(o)

			local function bycount(f)
				return function()
					f(vim.v.count1)
				end
			end

			vim.keymap.set("n", "<M-S-Left>", bycount(ss.resize_left), { silent = true, desc = "Resize left" })
			vim.keymap.set("n", "<M-S-Right>", bycount(ss.resize_right), { silent = true, desc = "Resize right" })
			vim.keymap.set("n", "<M-S-Down>", bycount(ss.resize_down), { silent = true, desc = "Resize down" })
			vim.keymap.set("n", "<M-S-Up>", bycount(ss.resize_up), { silent = true, desc = "Resize up" })

			vim.keymap.set("n", "<M-Left>", ss.move_cursor_left, { silent = true, desc = "Focus left window" })
			vim.keymap.set("n", "<M-Right>", ss.move_cursor_right, { silent = true, desc = "Focus right window" })
			vim.keymap.set("n", "<M-Down>", ss.move_cursor_down, { silent = true, desc = "Focus below window" })
			vim.keymap.set("n", "<M-Up>", ss.move_cursor_up, { silent = true, desc = "Focus above window" })

			vim.keymap.set("n", "<leader>w<Left>", ss.swap_buf_left, { silent = true, desc = "Swap buffer left" })
			vim.keymap.set("n", "<leader>w<Down>", ss.swap_buf_down, { silent = true, desc = "Swap buffer down" })
			vim.keymap.set("n", "<leader>w<Up>", ss.swap_buf_up, { silent = true, desc = "Swap buffer up" })
			vim.keymap.set("n", "<leader>w<Right>", ss.swap_buf_right, { silent = true, desc = "Swap buffer right" })
		end,
	},
}
