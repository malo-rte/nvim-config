vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("my_lsp_attach", { clear = true }),
	callback = function(ev)
		local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))

		-- If you want Conform to handle ALL formatting, uncomment these:
		-- client.server_capabilities.documentFormattingProvider = false
		-- client.server_capabilities.documentRangeFormattingProvider = false

		local tsb = require("telescope.builtin")

		local function map(keys, func, desc)
			vim.keymap.set("n", keys, func, {
				buffer = ev.buf,
				silent = true,
				desc = "LSP: " .. desc,
			})
		end

		local function toggle_inlay_hints()
			-- Neovim 0.10+ API
			local enabled = false
			if vim.lsp.inlay_hint then
				if vim.lsp.inlay_hint.is_enabled then
					enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = ev.buf })
				end
				vim.lsp.inlay_hint.enable(not enabled, { bufnr = ev.buf })
			end
		end

		-- Core LSP maps
		map("gd", vim.lsp.buf.definition, "Go to definition")
		map("gr", vim.lsp.buf.references, "References (LSP)")
		map("gD", vim.lsp.buf.declaration, "Go to declaration")
		map("gi", vim.lsp.buf.implementation, "Go to implementation")
		map("K", vim.lsp.buf.hover, "Hover docs")
		map("<leader>rn", vim.lsp.buf.rename, "Rename")
		map("<leader>ca", vim.lsp.buf.code_action, "Code action")
		map("<leader>cti", toggle_inlay_hints, "Toggle inlay hints")

		-- Telescope-powered LSP views
		map("<leader>cd", tsb.diagnostics, "Diagnostics (Telescope)")
		map("grr", tsb.lsp_references, "References (Telescope)")

		-- Diagnostics navigation
		map("[d", function()
			vim.diagnostic.jump({ count = -1 })
		end, "Previous diagnostic")

		map("]d", function()
			vim.diagnostic.jump({ count = 1 })
		end, "Next diagnostic")

		map("<S-Up>", function()
			vim.diagnostic.jump({ count = -1 })
		end, "Previous diagnostic")

		map("<S-Down>", function()
			vim.diagnostic.jump({ count = 1 })
		end, "Next diagnostic")

		map("<leader>cs", "<cmd>LspClangdSwitchSourceHeader<cr>", "Switch header/source")
	end,
})

local ok, blink = pcall(require, "blink.cmp")

if ok then
	vim.lsp.config("*", {
		capabilities = blink.get_lsp_capabilities(),
	})
end

-- Enable all LSPs that have a config file in lsp/*.lua
local enabled = {}

local lsp_files = vim.api.nvim_get_runtime_file("lsp/*.lua", true)
for _, path in ipairs(lsp_files) do
	local name = vim.fs.basename(path):gsub("%.lua$", "")

	-- optional: skip helper files, e.g. _shared.lua
	if not name:match("^_") and not enabled[name] then
		enabled[name] = true
		vim.lsp.enable(name)
	end
end

-- Diagnostics UI (signs, virtual text, etc.)
require("utils.diagnostics").setup()
