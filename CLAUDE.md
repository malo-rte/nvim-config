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
  scripts, `py_compile`, the sandbox boot, `audit_keymaps.py`, and the keymap
  conflict check. A tool that is not installed is reported as **skip**, never
  a silent pass. `--fix` lets
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
- **Keymaps are inventoried from a real boot**, not from the source.
  `scripts/keymap_inventory.lua` is loaded with `--cmd` so it runs *before*
  `init.lua`, wraps `nvim_set_keymap`/`nvim_buf_set_keymap`, and records every
  mapping as it is created with the file and line that made it -- including the
  ones made *inside* plugins (mini.surround's `sa`), which no scan of this repo
  can see. `scripts/keymaps.py` drives it:
  - `scripts/keymaps.py` — conflict report (exit 0 clean, 1 conflicts, 2 the
    tool could not run). `--doc` regenerates `docs/keymaps.md`,
    `--json P` saves the raw inventory, `--inventory P` reuses one without
    booting, `--self-test` plants conflicts and insists they are all found.
  - `check.sh` runs `keymaps` (README coverage) and `conflicts` off **one**
    shared boot; `inventory()` in that script is the cache.
  - **Reading the keymap table afterwards is not equivalent** -- it keeps only
    the winner, so two places claiming one key look like one mapping. That is
    the whole reason for the wrapper approach.
  - **Attribution is a silent failure mode.** Walking the stack to the wrong
    frame gives every mapping one bogus owner, so every key has exactly one
    owner and the report says "no conflicts" forever. That bug shipped during
    development and was invisible until conflicts were planted on purpose.
    Hence the attribution canaries in `keymaps.py` (one mapping per owner
    class: config / lazy spec / plugin-created), which refuse to print a
    result if they go missing, and `--self-test`.
  - `docs/keymaps.md` is **generated** and depends on the environment (which
    language servers attach, which buffers could be probed), so it is
    deliberately **not** staleness-checked the way `ftype_icons.lua` is.
    Regenerate it on the machine whose mappings you mean to document.
- **`python3 scripts/audit_keymaps.py`** checks every mapping the config defines
  is named in README.md (exit 0 clean, 1 undocumented, 2 the audit itself
  failed). Run it after adding or renaming a keymap. It now takes its mappings
  from the inventory above. Two earlier approaches under-reported, which is why
  the canaries exist: a regex over `keys = {` blocks stopped at the first
  nested entry, and a regex over `vim.keymap.set("mode", "lhs"` could not see
  a mapping made through an alias (`local map = vim.keymap.set` in
  `config/yocto.lua`, the `map()` helper in `config/lsp.lua`) -- 45 of this
  config's mappings are defined that way and were silently exempt.
- **`User VeryLazy` never fires in a headless boot** (it hangs off `UIEnter`),
  so hlslens, git-conflict, dap, obsidian and ~15 others contribute nothing
  unless something force-loads them — `keymap_inventory.lua` fires the event
  and then calls `require("lazy").load`.
- **`nvim_get_keymap()` returns `lhs` already in readable form** (`<Esc>`,
  `<Space>ff`); putting that through `vim.fn.keytrans` escapes the `<` into
  `<lt>` and makes every such mapping look unrecognised. `canonical()` in
  `keymap_inventory.lua` is the one place that normalises either spelling.
- **`Plugin.values(plugin, "keys", true)`, not `plugin.keys`**, to read a
  plugin's lazy key specs: lazy merges `keys` (and deep-merges `opts`) across
  spec fragments, and the raw field holds only the last fragment's list.
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
