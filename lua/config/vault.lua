-- config/vault.lua
--
-- Per-project Obsidian vault. Each project gets its own `.vault/` for docs,
-- brainstorming, and ideas. The vault is always git-ignored via the repo's
-- .git/info/exclude -- which is local and never committed or pushed -- so it
-- never syncs to a public repo. obsidian.nvim points its workspace at the
-- current project's vault (see lua/plugins/obsidian.lua).

local M = {}
local uv = vim.uv
local project = require("config.project")

local VAULT = ".vault"
local SUBDIRS = { "notes", "ideas", "brainstorming", "dailies", "templates" }
local MARKERS = { ".git", "Cargo.toml", "go.mod", "pyproject.toml", "package.json" }

local function exists(p)
	return p and uv.fs_stat(p) ~= nil
end

-- Only real project roots (git repo or a build marker) host a vault, so we
-- never scatter .vault/ into arbitrary directories.
local function is_project(root)
	if not root then
		return false
	end
	for _, m in ipairs(MARKERS) do
		if exists(vim.fs.joinpath(root, m)) then
			return true
		end
	end
	return false
end

function M.dir(root)
	root = root or project.project_root()
	return root and vim.fs.joinpath(root, VAULT) or nil
end

-- Add `.vault/` to the repo's local excludes. .git/info/exclude is never
-- committed or pushed, so the vault stays out of every (public) repo.
local function ensure_ignored(root)
	local gitdir = vim.fs.joinpath(root, ".git")
	local st = uv.fs_stat(gitdir)
	if not st or st.type ~= "directory" then
		return -- no repo, or a worktree/submodule .git file: skip (best-effort)
	end
	local exclude = vim.fs.joinpath(gitdir, "info", "exclude")
	local f = io.open(exclude, "r")
	if f then
		for l in f:lines() do
			if l == VAULT or l == VAULT .. "/" then
				f:close()
				return -- already ignored
			end
		end
		f:close()
	end
	vim.fn.mkdir(vim.fs.joinpath(gitdir, "info"), "p")
	local w = io.open(exclude, "a")
	if w then
		w:write("\n# per-project Obsidian vault (nvim)\n" .. VAULT .. "/\n")
		w:close()
	end
end

-- Create (idempotently) the project's vault and return its path, or nil if the
-- current location is not a project. Safe to call repeatedly.
function M.ensure(root)
	root = root or project.project_root()
	if not is_project(root) then
		return nil
	end
	local vdir = M.dir(root)
	vim.fn.mkdir(vdir, "p")
	for _, s in ipairs(SUBDIRS) do
		vim.fn.mkdir(vim.fs.joinpath(vdir, s), "p")
	end
	ensure_ignored(root)

	local index = vim.fs.joinpath(vdir, "index.md")
	if not exists(index) then
		vim.fn.writefile({
			"# " .. vim.fn.fnamemodify(root, ":t") .. " vault",
			"",
			"Docs, brainstorming, and ideas for this project. Git-ignored; never synced.",
			"",
			"## Ideas",
			"",
			"## Notes",
			"",
		}, index)
	end
	return vdir
end

-- Ensure + open the current project's vault, switching obsidian's workspace to
-- it if obsidian is already loaded on a different vault.
function M.open()
	local root = project.project_root()
	if not is_project(root) then
		vim.notify("vault: not inside a project (need .git or a project marker)", vim.log.levels.WARN)
		return
	end
	local vdir = M.ensure(root)
	vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(vdir, "index.md")))

	-- If obsidian is already loaded on a different vault, switch it to this one.
	if _G.Obsidian then
		local cur = _G.Obsidian.workspace
		if not cur or vim.fs.normalize(tostring(cur.path)) ~= vim.fs.normalize(vdir) then
			local ok, W = pcall(require, "obsidian.workspace")
			if ok then
				local ws = W.new({ name = vim.fn.fnamemodify(root, ":t"), path = vdir, strict = true })
				if ws then
					pcall(W.set, ws)
				end
			end
		end
	end
end

vim.api.nvim_create_user_command("Vault", function()
	M.open()
end, { desc = "Open this project's Obsidian vault (creating it if needed)" })

vim.keymap.set("n", "<leader>ov", M.open, { desc = "Obsidian: open project vault" })

return M
