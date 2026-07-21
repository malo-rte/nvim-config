local icons = require("utils.icons")
local di = icons.diagnostics

return {
	"stevearc/quicker.nvim",
	ft = "qf",
	---@module "quicker"
	---@type quicker.SetupOptions
	opts = {
		buflisted = false,
		number = false,
		relativenumber = false,
		signcolumn = "auto",
		winfixheight = true,
		wrap = false,
	},

	-- Load-triggering keys so the toggles work from a cold start (ft="qf"
	-- alone can't open the quickfix, since it only loads once qf exists).
	keys = {
		{
			"<leader>xq",
			function()
				require("quicker").toggle()
			end,
			desc = "Toggle quickfix",
		},
		{
			"<leader>xl",
			function()
				require("quicker").toggle({ loclist = true })
			end,
			desc = "Toggle loclist",
		},
	},

	config = function(_, opts)
		require("quicker").setup({
			opts = opts,
			use_default_opts = true,
			keys = {
				{
					">",
					function()
						require("quicker").expand({ before = 2, after = 2, add_to_existing = true })
					end,
					desc = "Expand quickfix context",
				},
				{
					"<",
					function()
						require("quicker").collapse()
					end,
					desc = "Collapse quickfix context",
				},
			},

			on_qf = function(bufnr) end,

			edit = {
				-- Enable editing the quickfix like a normal buffer
				enabled = true,
				-- Set to true to write buffers after applying edits.
				-- Set to "unmodified" to only write unmodified buffers.
				autosave = "unmodified",
			},

			constrain_cursor = true,

			highlight = {
				-- Use treesitter highlighting
				treesitter = true,
				-- Use LSP semantic token highlighting
				lsp = true,
				-- Load the referenced buffers to apply more accurate highlights (may be slow)
				load_buffers = false,
			},

			follow = {
				-- When quickfix window is open, scroll to closest item to the cursor
				enabled = false,
			},

			-- Map of quickfix item type to icon
			type_icons = {
				E = di.error .. " ",
				W = di.warn .. " ",
				I = di.info .. " ",
				N = di.info .. " ",
				H = di.hint .. " ",
			},

			-- Border characters
			borders = {
				vert = "┃",
				-- Strong headers separate results from different files
				strong_header = "━",
				strong_cross = "╋",
				strong_end = "┫",
				-- Soft headers separate results within the same file
				soft_header = "╌",
				soft_cross = "╂",
				soft_end = "┨",
			},

			-- How to trim the leading whitespace from results. Can be 'all', 'common', or false
			trim_leading_whitespace = "common",

			-- Maximum width of the filename column
			max_filename_width = function()
				return math.floor(math.min(95, vim.o.columns / 2))
			end,

			-- How far the header should extend to the right
			header_length = function(type, start_col)
				return vim.o.columns - start_col
			end,
		})

	end,
}
