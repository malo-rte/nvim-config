-- Highlight the yanked text for 200ms
local highlight_yank_group = vim.api.nvim_create_augroup("HighlightYank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
	group = highlight_yank_group,
	desc = "Briefly highlight on yank",
	callback = function()
		vim.hl.on_yank({ higroup = "IncSearch", timeout = 200 })
	end,
})

-- Prose ergonomics for markdown notes: soft-wrap on word boundaries, conceal
-- markup (wikilinks/formatting), and spell-check. render-markdown manages its
-- own conceal while rendering; this covers plain editing and wikilink display.
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("MarkdownNotes", { clear = true }),
	pattern = { "markdown", "markdown.mdx" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.linebreak = true
		vim.opt_local.breakindent = true
		vim.opt_local.conceallevel = 2
		vim.opt_local.spell = true
	end,
})

-- 'autoread' is set in config/options.lua but nothing triggers the check, so a
-- file edited underneath us (by Claude, a rebase, a formatter run in another
-- terminal) stays stale in the buffer until something else forces a reload.
vim.api.nvim_create_autocmd({ "FocusGained", "TermLeave", "BufEnter" }, {
	group = vim.api.nvim_create_augroup("ReloadChangedFiles", { clear = true }),
	desc = "Reload buffers whose file changed on disk",
	callback = function(ev)
		if vim.bo[ev.buf].buftype == "" then
			vim.cmd("checktime")
		end
	end,
})

-- Make window separators brighter
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("WindowSeparators", { clear = true }),
	desc = "Keep window separators bright across colorscheme switches",
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
