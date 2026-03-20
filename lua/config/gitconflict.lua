-- config/gitconflict.lua
--
-- Glue around git-conflict.nvim + diffview for rebase conflict editing:
--   * pick an unmerged file to edit
--   * dump every conflict in the repo into the quickfix list (step with quicker)
--   * drive the rebase: continue / abort / skip / status, auto-staging the
--     current file on continue.
--
-- Keymaps (<leader>g):
--   gu   pick unmerged file        gC   conflicts -> quickfix
--   grc  rebase --continue         gra  rebase --abort
--   grs  rebase --skip             grS  rebase status
-- Commands: :ConflictFiles :Conflicts :RebaseContinue :RebaseAbort
--           :RebaseSkip :RebaseStatus

local M = {}
local uv = vim.uv or vim.loop

----------------------------------------------------------------------
-- git helpers
----------------------------------------------------------------------
local function git_lines(cwd, args)
	local cmd = { "git", "-C", cwd }
	vim.list_extend(cmd, args)
	local out = vim.fn.systemlist(cmd)
	return out, vim.v.shell_error
end

local function repo_root()
	local dir = vim.fn.expand("%:p:h")
	if dir == "" then
		dir = vim.fn.getcwd()
	end
	local out, code = git_lines(dir, { "rev-parse", "--show-toplevel" })
	if code ~= 0 or not out[1] or out[1] == "" then
		return nil
	end
	return out[1]
end

local function git_dir(root)
	local out, code = git_lines(root, { "rev-parse", "--absolute-git-dir" })
	if code ~= 0 or not out[1] then
		return nil
	end
	return out[1]
end

-- rebase state: returns (state_dir, done, total) or nil if not rebasing
local function rebase_state(root)
	local gd = git_dir(root)
	if not gd then
		return nil
	end
	local function num(p)
		local f = io.open(p, "r")
		if not f then
			return nil
		end
		local v = f:read("*l")
		f:close()
		return tonumber(v)
	end
	local merge, apply = gd .. "/rebase-merge", gd .. "/rebase-apply"
	if uv.fs_stat(merge) then
		return merge, num(merge .. "/msgnum"), num(merge .. "/end")
	elseif uv.fs_stat(apply) then
		return apply, num(apply .. "/next"), num(apply .. "/last")
	end
	return nil
end

local function unmerged(root)
	local out = git_lines(root, { "diff", "--name-only", "--diff-filter=U" })
	return vim.tbl_filter(function(p)
		return p ~= ""
	end, out)
end

local function buffer_has_markers(buf)
	for _, l in ipairs(vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)) do
		if l:match("^<<<<<<<") or l:match("^>>>>>>>") then
			return true
		end
	end
	return false
end

local function ivy(opts)
	return vim.tbl_deep_extend("force", require("telescope.themes").get_ivy(), opts or {})
end

----------------------------------------------------------------------
-- pickers / quickfix
----------------------------------------------------------------------
function M.pick_unmerged()
	local root = repo_root()
	if not root then
		vim.notify("Not in a git repo", vim.log.levels.WARN)
		return
	end
	local files = unmerged(root)
	if #files == 0 then
		vim.notify("No unmerged files", vim.log.levels.INFO)
		return
	end
	local t = {
		pickers = require("telescope.pickers"),
		finders = require("telescope.finders"),
		conf = require("telescope.config").values,
		actions = require("telescope.actions"),
		state = require("telescope.actions.state"),
	}
	t.pickers
		.new(ivy({}), {
			prompt_title = ("Unmerged files [%d]"):format(#files),
			finder = t.finders.new_table({
				results = files,
				entry_maker = function(p)
					return { value = root .. "/" .. p, ordinal = p, display = p }
				end,
			}),
			sorter = t.conf.generic_sorter({}),
			attach_mappings = function(bufnr)
				t.actions.select_default:replace(function()
					local e = t.state.get_selected_entry()
					t.actions.close(bufnr)
					if e then
						vim.cmd.edit(vim.fn.fnameescape(e.value))
					end
				end)
				return true
			end,
		})
		:find()
end

-- Every conflict in the repo -> quickfix (one entry per <<<<<<< marker).
function M.conflicts_qf()
	local root = repo_root()
	if not root then
		vim.notify("Not in a git repo", vim.log.levels.WARN)
		return
	end
	local files = unmerged(root)
	if #files == 0 then
		vim.notify("No unmerged files", vim.log.levels.INFO)
		return
	end
	local args = { "grep", "-n", "--no-color", "-I", "-e", "^<<<<<<<", "--" }
	vim.list_extend(args, files)
	local items = {}
	for _, l in ipairs(git_lines(root, args)) do
		local f, ln, txt = l:match("^(.-):(%d+):(.*)$")
		if f then
			items[#items + 1] = { filename = root .. "/" .. f, lnum = tonumber(ln), text = txt }
		end
	end
	if #items == 0 then
		vim.notify("No conflict markers found", vim.log.levels.INFO)
		return
	end
	vim.fn.setqflist({}, " ", { title = "Git conflicts", items = items })
	vim.cmd("copen")
end

----------------------------------------------------------------------
-- rebase session
----------------------------------------------------------------------
local function reload_changed()
	vim.cmd("checktime")
end

local function run_rebase(action)
	local root = repo_root()
	if not root then
		vim.notify("Not in a git repo", vim.log.levels.WARN)
		return
	end
	if not rebase_state(root) then
		vim.notify("No rebase in progress", vim.log.levels.WARN)
		return
	end
	-- GIT_EDITOR=true accepts the existing commit message non-interactively.
	vim.system(
		{ "git", "-C", root, "rebase", action },
		{ text = true, env = { GIT_EDITOR = "true", GIT_SEQUENCE_EDITOR = "true" } },
		function(res)
			vim.schedule(function()
				reload_changed()
				if not rebase_state(root) then
					vim.notify("Rebase finished")
					return
				end
				local out = (res.stdout or "") .. (res.stderr or "")
				if out:match("CONFLICT") or #unmerged(root) > 0 then
					local _, d, total = rebase_state(root)
					vim.notify(
						("Conflicts remain%s"):format(d and total and (" (step %d/%d)"):format(d, total) or ""),
						vim.log.levels.WARN
					)
					M.conflicts_qf()
				else
					vim.notify("rebase " .. action)
				end
			end)
		end
	)
end

function M.continue()
	local root = repo_root()
	if not root then
		vim.notify("Not in a git repo", vim.log.levels.WARN)
		return
	end
	if not rebase_state(root) then
		vim.notify("No rebase in progress", vim.log.levels.WARN)
		return
	end
	if buffer_has_markers(0) then
		vim.notify("Current file still has conflict markers — resolve & save first", vim.log.levels.WARN)
		return
	end
	local file = vim.api.nvim_buf_get_name(0)
	if file ~= "" then
		git_lines(root, { "add", "--", file }) -- auto-stage the resolved file
	end
	run_rebase("--continue")
end

function M.abort()
	run_rebase("--abort")
end

function M.skip()
	run_rebase("--skip")
end

function M.status()
	local root = repo_root()
	if not root then
		vim.notify("Not in a git repo", vim.log.levels.WARN)
		return
	end
	local dir, done, total = rebase_state(root)
	if not dir then
		vim.notify("No rebase in progress")
		return
	end
	vim.notify(
		("Rebase %s\nUnmerged files: %d"):format(
			done and total and ("step %d/%d"):format(done, total) or "in progress",
			#unmerged(root)
		)
	)
end

----------------------------------------------------------------------
-- commands + keymaps
----------------------------------------------------------------------
local cmd = vim.api.nvim_create_user_command
cmd("ConflictFiles", M.pick_unmerged, {})
cmd("Conflicts", M.conflicts_qf, {})
cmd("RebaseContinue", M.continue, {})
cmd("RebaseAbort", M.abort, {})
cmd("RebaseSkip", M.skip, {})
cmd("RebaseStatus", M.status, {})

local map = vim.keymap.set
map("n", "<leader>gu", M.pick_unmerged, { desc = "Git: unmerged files" })
map("n", "<leader>gC", M.conflicts_qf, { desc = "Git: conflicts -> quickfix" })
map("n", "<leader>grc", M.continue, { desc = "Rebase: continue" })
map("n", "<leader>gra", M.abort, { desc = "Rebase: abort" })
map("n", "<leader>grs", M.skip, { desc = "Rebase: skip" })
map("n", "<leader>grS", M.status, { desc = "Rebase: status" })

return M
