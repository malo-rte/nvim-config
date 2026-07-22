# Notes for Claude Code

Neovim config (targets **0.12+**), managed with lazy.nvim. Runs in two
environments from the same files (see `lua/config/env.lua`):
- **NixOS** — treesitter parsers + LSP servers provided by nix (`$NVIM_TS_PARSERS`,
  `/etc/NIXOS` as the signal).
- **Debian dev container** — parsers compiled locally, LSP servers via mason.

## Icons / Nerd Font glyphs

**This terminal/font does NOT render Plane-15 glyphs** — the `nf-md-*`
(Material Design) icons live in Unicode Plane 15 / SPUA-A (`U+F0000`+) and come
out blank/invisible.

- Use **BMP-PUA** glyphs (`U+E000`–`U+F8FF`): `nf-fa-*`, `nf-cod-*`, `nf-oct-*`,
  `nf-seti-*`, `nf-dev-*`, `nf-custom-*`. Quick check: codepoint `>= 0xF0000` →
  avoid; `0xE000`–`0xF8FF` → OK.
- Shared user-facing status glyphs live in `lua/utils/icons.lua` (single source
  of truth: diagnostics, git, autoformat, lsp_kind, …). Keep new ones BMP-PUA.
- Icons follow the `DEV-TOOLS-DES-0004-icon-rules.adoc` spec. The file-type map
  `lua/utils/ftype_icons.lua` is **generated** — run
  `python3 scripts/gen_ftype_icons.py` to regenerate from the spec (it still
  contains `nf-md-*` codepoints, which may not show in this terminal).
- Nerd Font glyph mapping is pinned to `v3.4.0` in `lua/utils/nerdfont.lua`
  (never `master`).

## Testing the config (headless)

The repo is **not** at `~/.config/nvim` here — it's `/workspaces/nvim-config`,
so plain `nvim` won't load it. To boot the real config headless:

```sh
tmp=$(mktemp -d); ln -s /workspaces/nvim-config "$tmp/nvim"
XDG_CONFIG_HOME="$tmp" nvim --headless "+lua vim.defer_fn(function() ... vim.cmd('qa!') end, 6000)"
```

- Parse check a file: `nvim --headless -u NONE -c "lua assert(loadfile('f.lua'))" -c qa`.
- A modified **listed** buffer + `qa` (no `!`) **hangs** headless on the
  unsaved-changes prompt — always `qa!`, and use unlisted scratch buffers.
- `require('lualine').statusline()` renders the **inactive** line (no
  `lualine_x`); set `vim.g.actual_curwin = vim.api.nvim_get_current_win()` first
  to get the active one.
- Verifications run headless with no terminal → they confirm a glyph is *in* the
  statusline string, **not** that it renders visibly. Glyph visibility must be
  confirmed on the real machine.

## Gotchas that cost debugging time

- **LSP autodiscovery is scoped to `stdpath('config')/lsp`** (not the whole
  runtimepath) in both `config/lsp.lua` and `mason.lua` — otherwise plugins that
  ship `lsp/*.lua` (e.g. mason-lspconfig's `omnisharp_mono`) get enabled and
  fail to launch (exit code 127).
- **nvim-treesitter is on the `main` branch**: no built-in incremental selection
  (custom `config/tsselect.lua`); parsers compile via the **`tree-sitter` CLI**
  (must be on PATH — the container installs it); `install(langs)` warns on langs
  not in the registry.
- **lualine `color` as a *function*** must return a table `{ fg = "#hex" }` — a
  highlight-group-name **string** only works in the static path, else the
  component renders with no colour (looked invisible).
- **`project.project_root` anchors out-of-cwd files to the cwd** (its `within`
  check) — when testing, set the shell cwd to the temp project.
- **conform** silently skips a formatter whose binary isn't installed, so adding
  a `formatters_by_ft` mapping is safe even before the tool exists.
- Uses `vim.uv` / `vim.islist` directly (no `vim.loop` / `vim.tbl_islist`
  fallbacks) — targeting 0.12; lua_ls flags the deprecated names.

## Git / workflow

- The maintainer also pushes from other machines. **`git pull --rebase origin
  main` before pushing**, and sanity-check the config still boots after a rebase
  (an incoming commit once carried a syntax error).

## Docker (dev container)

- **No Docker daemon inside this container** — can't run `docker build`;
  Dockerfile changes are verified only to the crate/asset level, not a real build.
- **Pre-existing `FROM` mismatch**: `nvim-config-dev/Dockerfile` FROMs
  `dev-tools-build:latest`, but `enter-dev-container.sh` builds/tags
  `nvim-config-build`. A from-scratch build won't succeed until reconciled (or a
  `dev-tools-build:latest` image already exists).
