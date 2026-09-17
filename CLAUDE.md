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

Inside the dev container, plain `nvim` loads this repo: the image symlinks
`~/.config/nvim` at the bind mount (`/workspaces/<repo dir name>`, currently
`/workspaces/nvim` — `enter-dev-container.sh` derives it from the repo
directory). That is the interactive loop; note it writes `lazy-lock.json` into
the repo, which is right when you are bumping plugins and wrong in a check.

Two scripts wrap the checks so nothing has to be retyped:

- **`scripts/check.sh`** — everything at once: `stylua --check`, a `loadfile`
  parse of every Lua file, `luacheck`, a Plane-15 glyph report, a staleness
  check on the generated `ftype_icons.lua`, `bash -n` + `shellcheck` on the
  scripts, `py_compile`, the sandbox boot, and `audit_keymaps.py`. A tool that
  is not installed is reported as **skip**, never a silent pass. `--fix` lets
  the formatters write; `scripts/check.sh boot keymaps` runs a subset;
  `--list` names them. Run it in the container:
  `docker/enter-dev-container.sh scripts/check.sh`.
- **`scripts/nvim-sandbox.sh`** — boots the config against a **copy** so
  nothing the boot writes lands in the repo. Default shares the real plugin /
  mason / parser state (seconds, not a full reinstall) and isolates only the
  config; `--clean` isolates everything. `--lua '<chunk>'` runs a chunk in the
  booted config (that is how to inspect anything live), and `-- <args>` starts
  a real nvim on the copy.

- **Boot against a copy, not a symlink to the repo.** lazy.nvim writes
  `lazy-lock.json` into `stdpath('config')`, so a symlinked boot rewrites the
  committed lockfile — and if `$NVIM_TS_PARSERS` is set for the test,
  `mason.lua` returns `{}` and the boot *deletes* the mason entries from it.
  That is what the sandbox script is for.
- Setting `$NVIM_TS_PARSERS` to a throwaway dir is the way to skip compiling ~50
  treesitter parsers in a smoke test — but it puts the config on its **NixOS**
  path (`env.is_nix`), so mason is skipped and the portable branch goes untested.
- Parse check a file: `nvim --headless -u NONE -c "lua assert(loadfile('f.lua'))" -c qa`.
- **`python3 scripts/audit_keymaps.py`** checks every mapping the config defines
  is named in README.md (exit 0 clean, 1 undocumented, 2 the audit itself
  failed). Run it after adding or renaming a keymap. It reads lazy `keys` specs
  from a headless Neovim's live plugin table, **not** by parsing the Lua --
  a regex over `keys = {` blocks stops at the first nested entry and reports
  "all documented" while silently missing keys, which is why the script has
  canaries and refuses to print a result if they go missing.
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
- **blink.cmp must be a start plugin.** Its `plugin/blink-cmp.lua` is what
  registers `vim.lsp.config('*', { capabilities = ... })`, and capabilities are
  read when a client *starts* — servers start on `FileType`, long before any
  `InsertEnter`. Deferring it silently costs every server its completion
  capabilities.
- **Telescope is lazy**, so anything that needs it must `require` it *inside* a
  function, never at file scope (that was what kept pulling it into startup via
  `utils.nerdfontpicker` and `config.lsp`). `vim.ui.select` is kept routed
  through it by a shim in the spec's `init` that loads it on first use.
- **`:checktime` inside an autocmd will not reload the buffer that autocmd is
  firing for.** Testing the reload handler with
  `nvim_exec_autocmds('BufEnter', { buffer = cur })` therefore always looks
  broken; switch buffers for real (`:buffer #`) to see it work.
- Uses `vim.uv` / `vim.islist` directly (no `vim.loop` / `vim.tbl_islist`
  fallbacks) — targeting 0.12; lua_ls flags the deprecated names.

## Git / workflow

- The maintainer also pushes from other machines. **`git pull --rebase origin
  main` before pushing**, and sanity-check the config still boots after a rebase
  (an incoming commit once carried a syntax error).

## Docker (dev container)

- **No Docker daemon inside this container** — can't run `docker build`;
  Dockerfile changes are verified only to the package/asset level, not a real
  build.
- The image chain is `nvim-config-build` (the toolchains something compiles
  *at runtime*: cc for treesitter parsers and fzf-native, python3-venv for
  mason's PyPI packages, git/curl) → `nvim-config-dev` (Neovim, the maintenance
  toolkit, node, Claude Code, shell tools). `enter-dev-container.sh` builds both
  in that order and tags them by those names. Keep the `FROM` in
  `nvim-config-dev/Dockerfile` matching that tag — it previously pointed at
  `dev-tools-build:latest`, an image nothing here builds, so a from-scratch
  build could only work by accident.
- The Debian base is **pinned by digest** (`debian:13.6@sha256:…`) in both
  Dockerfiles; bump them together. `apt-get` still pulls current packages on
  every build, so the pin costs no security updates.
- `nvim-config-dev` is **multi-stage**: a throwaway `rust-tools` stage builds
  `kdlfmt` and `kdl-lsp` and the runtime image gets only those two binaries —
  no rustup tree. Anything else that needs `cargo` has to be added there, not
  installed at runtime.
- **Neovim state lives in named volumes** (`nvim-dev-<repo>-{share,state,cache}`),
  so lazy's clones, mason's servers and the ~50 compiled parsers survive
  `docker run --rm`. The image pre-creates those paths as the dev user — that is
  what gives a fresh volume the right ownership. Wipe them to test a cold start:
  `docker volume rm nvim-dev-nvim-{share,state,cache}`.
- Haskell (ghcup/ghc/HLS) is **opt-in**: `WITH_HASKELL=1 docker/enter-dev-container.sh`.
  It is multi-GB for one of 19 servers, and `mason.lua` already handles a
  missing `ghcup` deliberately (reports hls as skipped once instead of retrying
  every startup).
- `enter-dev-container.sh` takes a command (`… scripts/check.sh` runs it and
  exits, no TTY when piped) and honours `SKIP_BUILD=1` to reuse the images.
