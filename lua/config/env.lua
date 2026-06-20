-- Where treesitter parsers and LSP servers come from depends on the host.
--
-- On NixOS they are provided declaratively: parsers as a parser/ dir on the
-- runtimepath via $NVIM_TS_PARSERS, LSP servers on $PATH from nvim-lsp.nix. The
-- presence of that env var is the signal (with /etc/NIXOS as a fallback marker).
-- Anywhere it is unset -- notably the Debian dev container -- we are in
-- "portable" mode and must build parsers and install LSP servers (mason) here.
local M = {}

M.parser_dir = vim.env.NVIM_TS_PARSERS
M.is_nix = M.parser_dir ~= nil or vim.uv.fs_stat("/etc/NIXOS") ~= nil

return M
