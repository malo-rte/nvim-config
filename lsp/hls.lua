---@brief
---
--- https://haskell-language-server.readthedocs.io/en/latest/
---
--- haskell-language-server (HLS), the language server for Haskell.
---
--- The `haskell-language-server-wrapper` binary selects the HLS build that
--- matches the project's GHC version, so the toolchain (ghc/cabal/stack) must
--- be installed and discoverable -- via ghcup in the dev container, or via nix
--- on NixOS. Formatting is handled by conform.nvim (fourmolu); the
--- `formattingProvider` below is only used if you format through the LSP.

---@type vim.lsp.Config
return {
	cmd = { "haskell-language-server-wrapper", "--lsp" },
	filetypes = { "haskell", "lhaskell" },
	root_markers = {
		"hie.yaml",
		"stack.yaml",
		"cabal.project",
		"package.yaml",
		".git",
	},
	settings = {
		haskell = {
			formattingProvider = "fourmolu",
			cabalFormattingProvider = "cabalfmt",
		},
	},
}
