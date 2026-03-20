-- Highlight the yanked text for 200ms
local highlight_yank_group = vim.api.nvim_create_augroup("HighlightYank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
	group = highlight_yank_group,
	desc = "Briefly highlight on yank",
	callback = function()
		vim.hl.on_yank({ higroup = "IncSearch", timeout = 200 })
	end,
})

-- Make window separators brighter
vim.api.nvim_create_autocmd("ColorScheme", {
	callback = function()
		vim.api.nvim_set_hl(0, "VertSplit", { link = "Normal" })
		vim.api.nvim_set_hl(0, "WinSeparator", { link = "Normal" })

		vim.opt.fillchars = {
			vert = "│",
			vertleft = "┤",
			vertright = "├",
			verthoriz = "┼",
			horiz = "─",
			horizup = "┴",
			horizdown = "┬",
		}
	end,
})
