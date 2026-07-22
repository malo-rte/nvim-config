---@brief
---
--- https://github.com/nix-community/nixd
---
--- nixd, a Nix language server with evaluation-based completion (NixOS /
--- home-manager options and nixpkgs attrs), diagnostics, and formatting.
--- Provide it via nix on NixOS; mason installs it in the dev container.
---
--- Formatting is delegated to nixfmt (also wired into conform.nvim). Option
--- completion needs an expression pointing at your own flake -- see the
--- commented examples below.

---@type vim.lsp.Config
return {
	cmd = { "nixd" },
	filetypes = { "nix" },
	root_markers = { "flake.nix", ".git" },
	settings = {
		nixd = {
			formatting = { command = { "nixfmt" } },
			nixpkgs = { expr = "import <nixpkgs> { }" },
			-- Option completion: fill in your flake path + host/user, e.g.
			-- nixos = {
			--   expr = 'import (builtins.getFlake "/home/malo/nixcfg").nixosConfigurations.HOSTNAME.options',
			-- },
			-- home_manager = {
			--   expr = '(builtins.getFlake "/home/malo/nixcfg").homeConfigurations."malo".options',
			-- },
		},
	},
}
