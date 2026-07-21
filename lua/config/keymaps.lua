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

-- List navigation (unimpaired-style): quickfix and location list
vim.keymap.set("n", "]q", "<cmd>cnext<CR>", { desc = "Next quickfix item" })
vim.keymap.set("n", "[q", "<cmd>cprev<CR>", { desc = "Previous quickfix item" })
vim.keymap.set("n", "]Q", "<cmd>clast<CR>", { desc = "Last quickfix item" })
vim.keymap.set("n", "[Q", "<cmd>cfirst<CR>", { desc = "First quickfix item" })
vim.keymap.set("n", "]l", "<cmd>lnext<CR>", { desc = "Next loclist item" })
vim.keymap.set("n", "[l", "<cmd>lprev<CR>", { desc = "Previous loclist item" })

-- Diagnostics / quickfix hub (<leader>x). Global (not LSP-scoped), so it also
-- covers nvim-lint diagnostics in buffers with no LSP client. Falls back to the
-- quickfix list if Telescope is unavailable.
local function diagnostics_list(opts)
	local ok, tb = pcall(require, "telescope.builtin")
	if ok then
		tb.diagnostics(opts)
	else
		vim.diagnostic.setqflist(opts and opts.bufnr and { bufnr = opts.bufnr } or {})
		vim.cmd("copen")
	end
end
vim.keymap.set("n", "<leader>xx", function()
	diagnostics_list()
end, { desc = "Diagnostics: workspace" })
vim.keymap.set("n", "<leader>xX", function()
	diagnostics_list({ bufnr = 0 })
end, { desc = "Diagnostics: current buffer" })

-- UI / toggles (<leader>u): one home for all editor toggles. Inlay hints live
-- in the LSP attach (buffer-local) as <leader>uh; indent-scope toggles are in
-- the mini.indentscope plugin as <leader>ui / uI.
local function toggle_buffer_format_on_save()
	vim.b.enable_format_on_save = not vim.b.enable_format_on_save
	vim.notify("Format on save: " .. (vim.b.enable_format_on_save and "ON" or "OFF") .. " for this buffer")
end
vim.api.nvim_create_user_command("FormatOnSaveToggle", toggle_buffer_format_on_save, {})
vim.keymap.set("n", "<leader>uf", toggle_buffer_format_on_save, { desc = "Toggle: format on save (buffer)" })
vim.keymap.set("n", "<leader>us", function()
	vim.opt_local.spell = not vim.opt_local.spell:get()
end, { desc = "Toggle: spell" })
vim.keymap.set("n", "<leader>uw", function()
	vim.opt_local.wrap = not vim.opt_local.wrap:get()
end, { desc = "Toggle: wrap" })
vim.keymap.set("n", "<leader>ul", function()
	local on = not vim.opt_local.number:get()
	vim.opt_local.number = on
	vim.opt_local.relativenumber = on
end, { desc = "Toggle: line numbers" })

-- Quit / session
vim.keymap.set("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })

-- Git: jump to the next merge conflict in the buffer
vim.api.nvim_create_user_command("NextMergeConflict", function()
	local patterns = { "^<<<<<<< ", "^=======$", "^>>>>>>> " }
	local found = vim.fn.search(table.concat(patterns, "\\|"), "W")
	if found == 0 then
		vim.notify("No further merge conflicts found in this buffer")
	end
end, {})
vim.keymap.set("n", "<leader>gm", "<cmd>NextMergeConflict<cr>", { desc = "Git: next merge conflict" })
