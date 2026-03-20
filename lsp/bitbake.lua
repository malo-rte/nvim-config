---@brief
---
--- Official Yocto Project BitBake language server (the server behind the
--- VSCode BitBake extension).
---
--- Install (Node):  npm i -g language-server-bitbake
--- Provides: variable/symbol go-to-definition, hover, completion, and
--- embedded language awareness (inline Python/shell in recipes).
---
--- Relies on the `bitbake` filetype, which recent Neovim ships (vim-bitbake).
--- Recipe `*.conf` files are mapped to `bitbake` in config/yocto.lua.

---@type vim.lsp.Config
return {
	cmd = { "language-server-bitbake", "--stdio" },
	filetypes = { "bitbake" },
	root_markers = {
		"conf/layer.conf", -- inside a layer
		"conf/bblayers.conf", -- inside a build dir
		"oe-init-build-env",
		".git",
	},
}
