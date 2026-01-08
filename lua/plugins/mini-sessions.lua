-- plugins/mini-sessions.lua
return {
	"echasnovski/mini.sessions",
	lazy = false, -- load at startup so first launch can restore
	version = false,
	config = function()
		local ms = require("mini.sessions")

		-- per-project cache dir (hashed by project root)
		local base = vim.fn.stdpath("cache") .. "/nvim-workspaces"
		vim.fn.mkdir(base, "p")

		local root = require("config.project").project_root()
		local id = vim.fn.sha256(root)
		local proj_cache = base .. "/" .. id
		vim.fn.mkdir(proj_cache, "p") -- directory exists for shada + session file

		-- per-project shada
		vim.o.shadafile = proj_cache .. "/shada"
		if (vim.uv or vim.loop).fs_stat(vim.o.shadafile) then
			pcall(vim.cmd, "silent! rshada")
		end

		-- don't persist global options like &tabline
		vim.opt.sessionoptions = {
			"buffers",
			"curdir",
			"folds",
			"help",
			"localoptions",
			"tabpages",
			"winsize",
		}

		-- configure mini.sessions to write inside this project's cache dir
		local opts = {
			autoread = false,
			autowrite = false,
			directory = proj_cache, -- << key change: write into the per-project folder
			file = "", -- no local Session.vim in CWD
			force = { read = false, write = true, delete = false },
			verbose = { read = false, write = true, delete = true },
		}
		ms.setup(opts)

		local sess_name = "session.vim" -- an actual filename under proj_cache

		-- restore on first launch (no file args) after startup settles
		if vim.fn.argc() == 0 then
			vim.schedule(function()
				pcall(ms.read, sess_name, { verbose = false })
				-- sanitize old tabline from legacy sessions if present
				local tl = vim.o.tabline
				if type(tl) == "string" and tl:find("nvim_bufferline", 1, true) then
					vim.o.tabline = ""
				end
			end)
		end

		-- always save on exit
		local aug = vim.api.nvim_create_augroup("PersistentSessionMini", { clear = true })
		vim.api.nvim_create_autocmd("VimLeavePre", {
			group = aug,
			callback = function()
				pcall(ms.write, sess_name, { force = true, verbose = false })
			end,
		})

		-- commands
		vim.api.nvim_create_user_command("SessionSave", function()
			require("mini.sessions").write("session.vim", { force = true })
		end, {})

		vim.api.nvim_create_user_command("SessionLoad", function()
			require("mini.sessions").read("session.vim", { verbose = false })
		end, {})

		vim.api.nvim_create_user_command("SessionDelete", function()
			require("mini.sessions").delete("session.vim", { force = true })
		end, {})

		-- helpers
		vim.keymap.set("n", "<leader>qs", "<Cmd>SessionSave<cr>", { desc = "Session: save (project)" })
		vim.keymap.set("n", "<leader>ql", "<Cmd>SessionLoad<cr>", { desc = "Session: load (project)" })
		vim.keymap.set("n", "<leader>qd", "<cmd>SessionDelete<cr>", { desc = "Delete session" })

		vim.api.nvim_create_autocmd("VimLeavePre", {
			group = vim.api.nvim_create_augroup("PersistShada", { clear = true }),
			callback = function()
				pcall(vim.cmd, "silent! wshada!")
			end,
		})
	end,
}
