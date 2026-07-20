return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },

	config = function()
		local c = require("conform")
		local opts = {
			formatters_by_ft = {
				lua = { "stylua" },

				python = function(bufnr)
					if c.get_formatter_info("ruff_format", bufnr).available then
						return { "ruff_format" }
					else
						return { "isort", "black" }
					end
				end,

				rust = { "rustfmt" },
				haskell = { "fourmolu" },
				cabal = { "cabal_fmt" },
				javascript = { "prettierd", "prettier", stop_after_first = true },
				javascriptreact = { "prettierd", "prettier", stop_after_first = true },
				typescript = { "prettierd", "prettier", stop_after_first = true },
				typescriptreact = { "prettierd", "prettier", stop_after_first = true },
				json = { "prettierd", "prettier", stop_after_first = true },
				jsonc = { "prettierd", "prettier", stop_after_first = true },
				yaml = { "prettierd", "prettier", stop_after_first = true },
				html = { "prettierd", "prettier", stop_after_first = true },
				css = { "prettierd", "prettier", stop_after_first = true },
				scss = { "prettierd", "prettier", stop_after_first = true },
				c = { "clang_format" },
				cpp = { "clang_format" },
				asm = { "asmfmt" },
				markdown = { "prettierd", "prettier" },
				graphql = { "prettierd", "prettier" },
				text = { "prettierd", "prettier" },
				cmake = { "cmake_format" },

				sh = { "shfmt" },

				verilog = { "verible" },
				systemverilog = { "verible" },
			},
			formatters = {
				prettier = {
					require_cwd = true,
					cwd = require("conform.util").root_file({
						"package.json",
						".prettierrc",
						".prettierrc.json",
						".prettierrc.yml",
						".prettierrc.yaml",
						".prettierrc.json5",
						".prettierrc.js",
						".prettierrc.cjs",
						".prettierrc.mjs",
						".prettierrc.toml",
						"prettier.config.js",
						"prettier.config.cjs",
						"prettier.config.mjs",
					}),
				},

				cmake_format = {
					command = "cmake-format",
					stdin = true,
				},
			},

			format_on_save = function(bufnr)
				if vim.b[bufnr].enable_format_on_save then
					return {
						timeout_ms = 1500,
						lsp_format = "never",
					}
				end

				return nil
			end,
		}

		c.setup(opts)
	end,
}
