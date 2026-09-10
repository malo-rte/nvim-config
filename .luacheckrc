-- luacheck config for this Neovim config (nvim-lint runs `luacheck` on lua/).
--
-- `vim` is listed as writable rather than read-only because the config assigns
-- through it constantly (vim.g, vim.opt, vim.o, ...).
globals = {
	"vim",
}
