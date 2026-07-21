---@brief
---
--- https://github.com/kdl-org/kdl-rs/tree/main/tools/kdl-lsp
---
--- kdl-lsp, the language server for the KDL Document Language (from the KDL
--- org). It currently provides diagnostics only -- KDL validation via kdl-rs;
--- completions and schema support are planned. Communicates over stdio.
---
--- Install with `cargo install kdl-lsp` (the dev container does this; on NixOS
--- provide it via nix). Not a mason package.

---@type vim.lsp.Config
return {
	cmd = { "kdl-lsp" },
	filetypes = { "kdl" },
	root_markers = { ".git" },
}
