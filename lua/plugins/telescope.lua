local opts = {
	pickers = {
		lsp_references = {
			theme = "ivy",
			initial_mode = "normal",
			show_line = false,
			include_declaration = false, -- usually nicer for “real” references
		},

		diagnostics = {
			theme = "ivy",
			initial_mode = "normal",
		},

		lsp_definitions = { theme = "ivy", initial_mode = "normal" },
		lsp_implementations = { theme = "ivy", initial_mode = "normal" },
		lsp_type_definitions = { theme = "ivy", initial_mode = "normal" },
		lsp_document_symbols = { theme = "ivy", initial_mode = "normal" },
		lsp_workspace_symbols = { theme = "ivy", initial_mode = "normal" },
		lsp_incoming_calls = { theme = "ivy", initial_mode = "normal" },
		lsp_outgoing_calls = { theme = "ivy", initial_mode = "normal" },
	},

	extensions = {
		frecency = {
			show_scores = true, -- Default: false
			-- If `true`, it shows confirmation dialog before any entries are removed from the DB
			-- If you want not to be bothered with such things and to remove stale results silently
			-- set db_safe_mode=false and auto_validate=true
			--
			-- This fixes an issue I had in which I couldn't close the floating
			-- window because I couldn't focus it
			db_safe_mode = false, -- Default: true
			-- If `true`, it removes stale entries count over than db_validate_threshold
			auto_validate = true, -- Default: true
			-- It will remove entries when stale ones exist more than this count
			db_validate_threshold = 10, -- Default: 10
			-- Show the path of the active filter before file paths.
			-- So if I'm in the `dotfiles-latest` directory it will show me that
			-- before the name of the file
			show_filter_column = false, -- Default: true
		},
	},
}

-- helper so we never mutate the base Ivy opts
local function with_ivy(opts)
	return vim.tbl_deep_extend("force", require("telescope.themes").get_ivy(), opts or {})
end

return {
	"nvim-telescope/telescope.nvim",
	version = "*",
	dependencies = {
		{ "nvim-lua/plenary.nvim" },
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make", cond = vim.fn.executable("make") == 1 },
		{ "nvim-telescope/telescope-frecency.nvim" },
		{ "kkharji/sqlite.lua", enabled = true }, -- speeds up telescope-frecency
	},
	opts = opts,

	config = function(_, o)
		local ts = require("telescope")
		local tb = require("telescope.builtin")
		local project = require("config.project")
		ts.setup(o)

		ts.load_extension("frecency")

		local ok = pcall(ts.load_extension, "fzf")
		if not ok then
			vim.schedule(function()
				vim.notify("telescope-fzf-native not loaded (optional)", vim.log.levels.WARN)
			end)
		end

		vim.keymap.set("n", "<leader>bb", ":Telescope buffers theme=ivy<cr>")

		vim.keymap.set("n", "<leader>fr", function()
			local project = require("config.project")
			local dir = project.project_root()
			-- choose your scope: tcd (tab), lcd (window), or chdir (global)
			pcall(vim.cmd.tcd, vim.fn.fnameescape(dir))
			ts.extensions.frecency.frecency(with_ivy({ workspace = "CWD" }))
		end, { desc = "Frecency (project)" })

		-- Find files from your dynamic project root
		vim.keymap.set("n", "<leader>ff", function()
			tb.find_files(with_ivy({ cwd = project.project_root() }))
		end, { desc = "Find files (project root)" })

		-- Live grep from your dynamic project root
		vim.keymap.set("n", "<leader>fg", function()
			tb.live_grep(with_ivy({ cwd = project.project_root() }))
		end, { desc = "live grep (project root)" })

		-- Find a project in the home directory and select it
		vim.keymap.set("n", "<leader>fp", function()
			project.project_picker("~", {
				scan = { max_depth = 16, prune_on_match = true },
				scope = "tab", --  or 'global' / 'window'
				open = "find_files", -- or 'live_grep'
			})
		end, { desc = "Find & switch project" })

		vim.keymap.set("n", "<leader>inc", ":NerdFontPicker insert char<CR>", { desc = "Insert nerdfont char" })
		vim.keymap.set("n", "<leader>inn", ":NerdFontPicker insert name<CR>", { desc = "Insert nerdfont glyph name" })

		-- Create commands
		vim.api.nvim_create_user_command("ProjectPick", function(opts)
			project.project_picker(opts.args ~= "" and opts.args or "~", {
				scan = { max_depth = 16, prune_on_match = true },
				scope = "tab", -- or 'global' / 'window'
				open = "find_files", -- or 'live_grep'
			})
		end, { nargs = "?" })

		vim.api.nvim_create_user_command("ProjectFiles", function()
			tb.find_files(with_ivy({ cwd = project.project_root() }))
		end, {})

		vim.api.nvim_create_user_command("ProjectGrep", function()
			tb.live_grep(with_ivy({ cwd = project.project_root() }))
		end, {})
	end,
}
