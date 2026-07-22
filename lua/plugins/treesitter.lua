
local langs = {
	"c",
	"bash",
	"bitbake",
	"cmake",
	"cpp",
	"css",
	"csv",
	"devicetree",
	"diff",
	"dockerfile",
	"dot",
	"git_config",
	"git_rebase",
	"gitattributes",
	"gitignore",
	"gnuplot",
	"gpg",
	"groovy",
	"go",
	"graphql",
	"haskell",
	"html",
	"http",
	"idl",
	"java",
	"javascript",
	"jq",
	"json",
	"kconfig",
	"kdl",
	"latex",
	"llvm",
	"lua",
	"m68k",
	"make",
	"markdown",
	"markdown_inline",
	"matlab",
	"meson",
	"nasm",
	"nix",
	"objdump",
	"perl",
	"promql",
	"python",
	"query",
	"regex",
	"rust",
	"sql",
	"ssh_config",
	"terraform",
}

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			local env = require("config.env")
			if env.parser_dir then
				-- NixOS: precompiled parsers from nix on the runtimepath, no
				-- compilation. APPEND (not prepend) so Neovim's own bundled
				-- parsers (c, lua, vim, markdown, query, ...) win -- they match
				-- Neovim's/nvim-treesitter's queries, whereas the frozen nixpkgs
				-- versions can lag and throw "invalid node type" query errors
				-- (e.g. the cmdline vim parser). nix only fills the gaps.
				-- nixpkgs does not package every grammar (gnuplot, gpg, idl,
				-- kconfig, m68k, objdump, promql, ssh_config, terraform),
				-- so those filetypes have no treesitter here.
				vim.opt.runtimepath:append(env.parser_dir)
			else
				-- Portable (dev container): compile parsers locally.
				require("nvim-treesitter").install(langs)
			end

			-- main branch does NOT auto-start highlighting; do it per-filetype
			vim.api.nvim_create_autocmd("FileType", {
				callback = function(ev)
					local ft = vim.bo[ev.buf].filetype
					local lang = vim.treesitter.language.get_lang(ft)
					if lang and vim.treesitter.language.add(lang) then
						pcall(vim.treesitter.start, ev.buf, lang)
						-- treesitter-based indent (optional)
						vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					end
				end,
			})
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		config = function()
			require("nvim-treesitter-textobjects").setup({
				select = { lookahead = true },
			})

			local sel = require("nvim-treesitter-textobjects.select").select_textobject
			local move = require("nvim-treesitter-textobjects.move")

			for lhs, q in pairs({
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				["ac"] = "@class.outer",
				["ic"] = "@class.inner",
				["aa"] = "@parameter.outer",
				["ia"] = "@parameter.inner",
			}) do
				vim.keymap.set({ "x", "o" }, lhs, function()
					sel(q, "textobjects")
				end, { desc = "TS " .. q })
			end

			vim.keymap.set({ "n", "x", "o" }, "]f", function()
				move.goto_next_start("@function.outer", "textobjects")
			end, { desc = "Next function" })
			vim.keymap.set({ "n", "x", "o" }, "[f", function()
				move.goto_previous_start("@function.outer", "textobjects")
			end, { desc = "Prev function" })
		end,
	},
}
