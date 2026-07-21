-- Center screen when jumping
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result centered" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous search result centered" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Half page down (centered)" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Half page up (centered)" })

-- Buffer navigation
vim.keymap.set("n", "<leader>bn", "<Cmd>bnext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<leader>bp", "<Cmd>bprevious<CR>", { desc = "Previous buffer" })

-- Window navigation
vim.keymap.set("n", "<leader>w|", "<Cmd>vsplit<CR>", { desc = "Split window vertically" })
vim.keymap.set("n", "<leader>w-", "<Cmd>split<CR>", { desc = "Split window horizontally" })

-- Better indenting in visual mode
vim.keymap.set("v", "<", "<gv", { desc = "Indent left and reselect" })
vim.keymap.set("v", ">", ">gv", { desc = "Indent right and reselect" })

-- Join behaviour
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join lines and keep the cursor postion" })

-- Delete buffer without closing the window
vim.keymap.set("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

-- Save buffer(s)
vim.keymap.set({ "n", "i", "v" }, "<C-S>", "<cmd>update<cr>", { desc = "Save buffer if modified" })
vim.keymap.set("n", "<leader>bs", "<cmd>update<cr>", { desc = "Save buffer if modified" })
vim.keymap.set("n", "<leader>ba", "<cmd>wall<cr>", { desc = "Save all modified buffers" })

-- Clear search highlight
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR><Esc>", { desc = "Clear search highlight" })

-- Better paste when in visual selection
vim.keymap.set("v", "p", '"_dP', { desc = "Paste without overwriting yank register" })

-- Quickfix
vim.keymap.set("n", "<leader>qo", "<cmd>copen<CR>", { desc = "Open quickfix" })
vim.keymap.set("n", "<leader>qc", "<cmd>cclose<CR>", { desc = "Close quickfix" })
vim.keymap.set("n", "<leader>qn", "<cmd>cnext<CR>", { desc = "Next quickfix item" })
vim.keymap.set("n", "<leader>qp", "<cmd>cprev<CR>", { desc = "Previous quickfix item" })

-- Diagnostics list (global -- not LSP-scoped, so it also covers nvim-lint
-- diagnostics in buffers with no LSP client). Falls back to the quickfix
-- list if Telescope is unavailable.
local function diagnostics_list(opts)
	local ok, tb = pcall(require, "telescope.builtin")
	if ok then
		tb.diagnostics(opts)
	else
		vim.diagnostic.setqflist(opts and opts.bufnr and { bufnr = opts.bufnr } or {})
		vim.cmd("copen")
	end
end
vim.keymap.set("n", "<leader>cd", function()
	diagnostics_list()
end, { desc = "Diagnostics: list (workspace)" })
vim.keymap.set("n", "<leader>cD", function()
	diagnostics_list({ bufnr = 0 })
end, { desc = "Diagnostics: list (current buffer)" })

-- Toggle format on save (per buffer)
local function toggle_buffer_format_on_save()
	vim.b.enable_format_on_save = not vim.b.enable_format_on_save

	if vim.b.enable_format_on_save then
		vim.notify("Format on save: ON for this buffer")
	else
		vim.notify("Format on save: OFF for this buffer")
	end
end

vim.api.nvim_create_user_command("FormatOnSaveToggle", toggle_buffer_format_on_save, {})
vim.keymap.set("n", "<leader>bt", toggle_buffer_format_on_save, { desc = "Buffer format on save Toggle" })

-- Find next merge conflict
vim.api.nvim_create_user_command("NextMergeConflict", function()
	local patterns = {
		"^<<<<<<< ",
		"^=======$",
		"^>>>>>>> ",
	}

	local found = vim.fn.search(table.concat(patterns, "\\|"), "W")

	if found == 0 then
		vim.notify("No further merge conflicts found in this buffer")
	end
end, {})

vim.keymap.set("n", "<leader>bm", "<cmd>NextMergeConflict<cr>", { desc = "Next merge conflict" })
