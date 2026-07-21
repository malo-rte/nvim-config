local git = require("utils.icons").git
local ft = require("utils.ftype_icons")

local neotree_opts = {
	close_if_last_window = true,

	-- Icon glyphs from the shared spec tables (DEV-TOOLS-DES-0004 §2/§4-6/§35).
	default_component_configs = {
		icon = {
			folder_closed = ft.folder.closed,
			folder_open = ft.folder.open,
			folder_empty = ft.folder.empty,
			-- Wrap the default provider: directory-name glyphs (§4-6) for
			-- folders, devicons for files (behaviour otherwise unchanged).
			provider = function(icon, node, state)
				if node.type == "directory" then
					local g = ft.by_directory[(node.name or ""):lower()]
					if g then
						icon.text = g
					end
					return
				end
				if node.type == "file" or node.type == "terminal" then
					local ok, dev = pcall(require, "nvim-web-devicons")
					local name = node.type == "terminal" and "terminal" or node.name
					if ok then
						local devicon, hl = dev.get_icon(name)
						icon.text = devicon or icon.text
						icon.highlight = hl or icon.highlight
					end
				end
			end,
		},
		git_status = {
			symbols = {
				added = git.added,
				modified = git.modified,
				deleted = git.deleted,
				renamed = git.renamed,
				untracked = git.untracked,
				ignored = git.ignored,
				unstaged = git.unstaged,
				staged = git.staged,
				conflict = git.conflict,
			},
		},
	},

	event_handlers = {
		{
			event = "file_opened",
			handler = function(_)
				-- close all Neo-tree windows (any source)
				require("neo-tree.command").execute({ action = "close" })
				-- If you only want to close the filesystem tree, use:
				-- require("neo-tree.command").execute({ action = "close", source = "filesystem" })
			end,
		},
	},
}

local nlfo_opts = {}

local nwp_opts = {
	filter_rules = {
		include_current_win = false,
		autoselect_one = true,
		-- filter using buffer options
		bo = {
			-- if the file type is one of following, the window will be ignored
			filetype = { "neo-tree", "neo-tree-popup", "notify" },
			-- if the buffer type is one of following, the window will be ignored
			buftype = { "terminal", "quickfix" },
		},
	},
}

return {
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-tree/nvim-web-devicons",
		},
		lazy = false,
		version = "*",
		opts = neotree_opts,

		config = function(_, o)
			local nt = require("neo-tree")

			nt.setup(o)

			-- Open Neo-tree at your project root (uses your config.project module)
			vim.keymap.set("n", "<leader>fe", function()
				local project = require("config.project")
				local bufname = vim.api.nvim_buf_get_name(0)
				local has_file = bufname ~= "" and vim.fn.filereadable(bufname) == 1
				local root = project.project_root(has_file and { path = vim.fs.dirname(bufname) } or nil)
				local cmd = ("Neotree position=top toggle dir=%s"):format(vim.fn.fnameescape(root))
				if has_file then
					cmd = cmd .. (" reveal_file=%s reveal_force_cwd"):format(vim.fn.fnameescape(bufname))
				end
				vim.cmd(cmd)
			end, { desc = "Explorer: at project root" })

            vim.keymap.set("n", "<leader>gS", ":Neotree git_status<CR>"
		end,
	},

	{
		"antosha417/nvim-lsp-file-operations",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-neo-tree/neo-tree.nvim", -- makes sure that this loads after Neo-tree.
		},
		opts = nlfo_opts,
		config = function(_, o)
			require("lsp-file-operations").setup(o)
		end,
	},

	{
		"s1n7ax/nvim-window-picker",
		version = "2.*",
		opts = nwp_opts,

		config = function(_, o)
			require("window-picker").setup(o)
		end,
	},
}
