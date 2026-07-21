local icons = require("utils.icons")
local di = icons.diagnostics
local git = icons.git

local opts = {
	options = {
		icons_enabled = true,
		globalstatus = true,
		theme = "auto",
		component_separators = { left = "│", right = "│" },
		section_separators = { left = "", right = "" },
		disabled_filetypes = { statusline = { "alpha", "starter" } },
	},

	sections = {
		lualine_a = { "mode" },
		lualine_b = {
			{ "branch", icon = icons.git_repo.branch },
			{ "diff", symbols = { added = git.added .. " ", modified = git.modified .. " ", removed = git.deleted .. " " } },
		},

		lualine_c = {
			-- project root (from your config.project) + short filename
			function()
				local ok, project = pcall(require, "config.project")
                local root = (ok and project.project_root()) or vim.uv.cwd()
				return " " .. vim.fn.fnamemodify(root, ":~")
			end,
			{ "filename", path = 1, newfile_status = true, symbols = { modified = " " .. icons.file.modified, readonly = icons.file.readonly .. " " } },
		},

		lualine_x = {
			-- format-on-save indicator: green when on, dim when off
			{
				function()
					return icons.autoformat
				end,
				cond = function()
					return vim.bo.buftype == ""
				end,
				color = function()
					local ok, af = pcall(require, "config.autoformat")
					return (ok and af.enabled(0)) and "DiagnosticOk" or "Comment"
				end,
			},
			{
				"diagnostics",
				sources = { "nvim_diagnostic" },
				sections = { "error", "warn", "info", "hint" },
				symbols = { error = di.error .. " ", warn = di.warn .. " ", info = di.info .. " ", hint = di.hint .. " " },
				update_in_insert = false,
				always_visible = false,
			},
			-- active LSP clients for this buffer
			function()
				local clients = vim.lsp.get_clients({ bufnr = 0 })
				if #clients == 0 then
					return ""
				end
				local names = {}
				for _, c in ipairs(clients) do
					names[#names + 1] = c.name
				end
				return "  " .. table.concat(names, ",")
			end,
			"encoding",
			"fileformat",
			"filetype",
		},

		lualine_y = {
			-- macro recording indicator (auto-refresh)
			function()
				local reg = vim.fn.reg_recording()
				if reg == "" then
					return ""
				end
				return "⏺ REC @" .. reg
			end,
			"progress",
		},

		lualine_z = { "location" },
	},

	extensions = { "neo-tree", "quickfix", "man", "fugitive" },
}

return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	opts = opts,

	config = function(_, o)
		local ll = require("lualine")

		-- keep the REC indicator live
		vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
			callback = function()
				vim.defer_fn(function()
					ll.refresh({ place = { "statusline" } })
				end, 10)
			end,
			desc = "Refresh lualine on macro record state change",
		})

		ll.setup(o)
	end,
}
