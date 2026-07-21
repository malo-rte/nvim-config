-- config/mergediag.lua
--
-- Surface in-file conflict markers as diagnostics, so a merge/rebase/cherry-
-- pick/revert conflict shows in the sign column, virtual lines, the <leader>xx
-- list, and navigates with [d / ]d like any other diagnostic. All of those git
-- operations write the same markers, so a marker scan covers them all.
--
-- While a buffer has conflicts, the *other* diagnostic namespaces (LSP, lint)
-- are muted for that buffer so the broken-syntax noise stays hidden -- this
-- keeps the behaviour of git-conflict's old disable_diagnostics, but leaves our
-- conflict diagnostics visible. They are restored once the conflict is gone.
--
-- The scan is stateful (only flags separators/base/end inside an open block) so
-- it never false-positives on markdown ==== rules or code with >> etc.
--
-- NOTE: during a rebase, ours/theirs are inverted -- HEAD is the branch you are
-- rebasing ONTO, and the >>>>>>> side is your commit being replayed.

local M = {}
local ns = vim.api.nvim_create_namespace("merge_conflicts")

local START = "^<<<<<<<"
local BASE = "^|||||||"
local SEP = "^======="
local END = "^>>>>>>>"

-- bufnr -> { [ns_id] = true } : the namespaces WE muted, so we restore exactly
-- those (and nothing the user disabled elsewhere).
local muted = {}

local function mute_others(bufnr)
	muted[bufnr] = muted[bufnr] or {}
	for id in pairs(vim.diagnostic.get_namespaces()) do
		if id ~= ns and not muted[bufnr][id] then
			local ok, enabled = pcall(vim.diagnostic.is_enabled, { bufnr = bufnr, ns_id = id })
			if not ok or enabled then
				pcall(vim.diagnostic.enable, false, { bufnr = bufnr, ns_id = id })
				muted[bufnr][id] = true
			end
		end
	end
end

local function unmute(bufnr)
	local set = muted[bufnr]
	if not set then
		return
	end
	for id in pairs(set) do
		pcall(vim.diagnostic.enable, true, { bufnr = bufnr, ns_id = id })
	end
	muted[bufnr] = nil
end

--- Rescan a buffer for conflict markers, publish them, and mute/restore other
--- diagnostic sources depending on whether the buffer is currently conflicted.
function M.refresh(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_loaded(bufnr) or vim.bo[bufnr].buftype ~= "" then
		return
	end

	local diags = {}
	local open = false
	for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		local lnum, msg = i - 1, nil
		if line:match(START) then
			open, msg = true, "Conflict start — current/HEAD (rebase: the branch being rebased onto)"
		elseif open and line:match(BASE) then
			msg = "Conflict base — common ancestor"
		elseif open and line:match(SEP) then
			msg = "Conflict separator"
		elseif open and line:match(END) then
			open, msg = false, "Conflict end — incoming (rebase: your commit being replayed)"
		end
		if msg then
			diags[#diags + 1] = {
				lnum = lnum,
				col = 0,
				end_lnum = lnum,
				end_col = #line,
				severity = vim.diagnostic.severity.ERROR,
				source = "git-conflict",
				message = msg,
			}
		end
	end

	vim.diagnostic.set(ns, bufnr, diags)

	if #diags > 0 then
		mute_others(bufnr)
	else
		unmute(bufnr)
	end
end

local group = vim.api.nvim_create_augroup("MergeConflictDiagnostics", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "TextChanged", "InsertLeave" }, {
	group = group,
	callback = function(ev)
		M.refresh(ev.buf)
	end,
})
vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
	group = group,
	callback = function(ev)
		muted[ev.buf] = nil
	end,
})

vim.api.nvim_create_user_command("MergeDiagnosticsRefresh", function()
	M.refresh(0)
end, { desc = "Rescan buffer for git conflict diagnostics" })

return M
