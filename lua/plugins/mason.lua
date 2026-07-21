-- LSP server installation for portable / dev-container environments.
--
-- On NixOS the servers are already on $PATH (nvim-lsp.nix), so mason is skipped
-- entirely -- and must be, since mason's prebuilt binaries don't run against the
-- nix store. Off NixOS (the Debian dev container) mason installs the servers and
-- puts them on $PATH; lua/config/lsp.lua's vim.lsp.enable() then drives both
-- environments identically from the same lsp/*.lua configs.
local env = require("config.env")

if env.is_nix then
	return {}
end

-- Reuse the server list from the lsp/*.lua files so it never drifts from
-- lua/config/lsp.lua (which enables exactly these).
local function configured_servers()
	local names = {}
	-- Only our own lsp/ configs (scope to the config dir, not the whole
	-- runtimepath -- else plugins that ship lsp/*.lua leak in, e.g.
	-- mason-lspconfig's omnisharp_mono).
	for _, path in ipairs(vim.fn.globpath(vim.fn.stdpath("config") .. "/lsp", "*.lua", false, true)) do
		local name = vim.fs.basename(path):gsub("%.lua$", "")
		if not name:match("^_") then
			names[#names + 1] = name
		end
	end
	return names
end

return {
	{
		"mason-org/mason.nvim",
		opts = {},
	},
	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = { "mason-org/mason.nvim" },
		opts = function()
			-- Only request servers mason actually knows; the embedded ones
			-- (verible, vhdl_ls, dts, bitbake) come from the project toolchain.
			local ok, map = pcall(function()
				return require("mason-lspconfig").get_mappings().lspconfig_to_package
			end)
			local ensure = {}
			for _, s in ipairs(configured_servers()) do
				if not ok or map[s] then
					ensure[#ensure + 1] = s
				end
			end
			return {
				ensure_installed = ensure,
				-- lua/config/lsp.lua already calls vim.lsp.enable() for each.
				automatic_enable = false,
			}
		end,
	},
}
