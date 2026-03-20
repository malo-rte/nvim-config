---@brief
---
--- Device Tree Source language server (igor-prusov/dts-lsp), built on the
--- tree-sitter-devicetree grammar. Kernel-side DTS focused (not Zephyr).
---
--- Install (Rust):  cargo install dts-lsp
--- Provides: go-to label definition, find references to a label, rename
--- labels/references across the buffer.
---
--- Needs the `dts` filetype (Neovim ships detection for .dts/.dtsi; extra
--- extensions like .dtso/.its are added in config/yocto.lua).

---@type vim.lsp.Config
return {
	cmd = { "dts-lsp" },
	filetypes = { "dts" },
	root_markers = { ".git" },
}
