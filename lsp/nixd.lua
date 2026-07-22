---@brief
---
--- https://github.com/nix-community/nixd
---
--- nixd, a Nix language server with evaluation-based completion (NixOS /
--- home-manager options and nixpkgs attrs), diagnostics, and formatting.
--- Provide it via nix on NixOS; mason installs it in the dev container.
---
--- Option completion targets your flake. The hostname and username are read at
--- runtime (this runs on the actual host), so nvim on any machine targets that
--- machine's nixosConfigurations.<host> automatically -- no per-host editing.

local FLAKE = "/home/cfg/nixos-cfg"
local host = vim.uv.os_gethostname()
local user = vim.env.USER or (vim.uv.os_get_passwd() or {}).username or ""

return {
	cmd = { "nixd" },
	filetypes = { "nix" },
	root_markers = { "flake.nix", ".git" },
	settings = {
		nixd = {
			formatting = { command = { "nixfmt" } },
			nixpkgs = { expr = "import <nixpkgs> { }" },
			options = {
				-- NixOS options for this host.
				nixos = {
					expr = ('(builtins.getFlake "%s").nixosConfigurations."%s".options'):format(FLAKE, host),
				},
				-- Standalone home-manager, config named after the user. If your HM
				-- config uses a different name (e.g. "user@host") or is a NixOS
				-- module, adjust this expr -- nixd just skips it if it fails to eval.
				["home-manager"] = {
					expr = ('(builtins.getFlake "%s").homeConfigurations."%s".options'):format(FLAKE, user),
				},
			},
		},
	},
}
