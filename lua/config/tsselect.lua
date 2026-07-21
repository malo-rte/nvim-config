-- config/tsselect.lua
--
-- Treesitter incremental selection for the nvim-treesitter `main` branch,
-- which dropped the built-in incremental_selection module.
--
--   <C-space>  in normal mode : select the node under the cursor
--              in visual mode : expand the selection to the next larger node
--   <BS>       in visual mode : shrink back to the previous node
--
-- Only works in buffers where treesitter is active (see treesitter.lua).

local M = {}

-- per-window stack of selected nodes
local stack = {}

local function same_range(a, b)
	local a1, a2, a3, a4 = a:range()
	local b1, b2, b3, b4 = b:range()
	return a1 == b1 and a2 == b2 and a3 == b3 and a4 == b4
end

local ESC = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

-- Charwise-select a node's range via the '< / '> marks + gv.
local function select_node(node)
	local srow, scol, erow, ecol = node:range()
	local buf = vim.api.nvim_get_current_buf()
	if ecol == 0 then
		-- range ends at the start of a line (exclusive): back up to the
		-- previous line's end.
		erow = erow - 1
		ecol = #(vim.api.nvim_buf_get_lines(buf, erow, erow + 1, false)[1] or "")
	end
	-- Leave any active visual mode first, otherwise `gv` commits the current
	-- selection's marks over the ones we set (selection would lag by one step).
	if vim.fn.mode():find("[vV\22]") then
		vim.api.nvim_feedkeys(ESC, "nx", false)
	end
	vim.fn.setpos("'<", { 0, srow + 1, scol + 1, 0 })
	vim.fn.setpos("'>", { 0, erow + 1, math.max(ecol, 1), 0 })
	vim.cmd("normal! gv")
end

function M.init()
	local node = vim.treesitter.get_node()
	if not node then
		return
	end
	stack[vim.api.nvim_get_current_win()] = { node }
	select_node(node)
end

function M.expand()
	local win = vim.api.nvim_get_current_win()
	local s = stack[win]
	if not s or #s == 0 then
		return M.init()
	end
	local node = s[#s]
	local parent = node:parent()
	while parent and same_range(parent, node) do
		parent = parent:parent()
	end
	if parent then
		s[#s + 1] = parent
		select_node(parent)
	else
		select_node(node) -- already at the root
	end
end

function M.shrink()
	local s = stack[vim.api.nvim_get_current_win()]
	if not s or #s <= 1 then
		if s and s[1] then
			select_node(s[1])
		end
		return
	end
	table.remove(s)
	select_node(s[#s])
end

vim.keymap.set({ "n", "x" }, "<C-space>", function()
	if vim.fn.mode():match("[vV\22]") then
		M.expand()
	else
		M.init()
	end
end, { desc = "TS: select / expand node" })

vim.keymap.set("x", "<BS>", function()
	M.shrink()
end, { desc = "TS: shrink node selection" })

return M
