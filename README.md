# Neovim configuration

A modular Neovim config (targets **Neovim 0.12+**) that runs in two
environments from the same files: NixOS (parsers/LSPs provided by nix) and a
Debian dev container (parsers built locally, LSPs via mason). Plugins are
managed with [lazy.nvim](https://github.com/folke/lazy.nvim).

Highlights: LSP + completion (blink.cmp), Telescope, Treesitter, a mini.nvim
suite, git tooling (diffview + git-conflict + mini.diff), DAP debugging,
Obsidian-style per-project notes, Yocto/BitBake helpers, and a spec-driven
icon system.

## Keybindings

`<leader>` is **Space**. Press `<leader>` and wait to see the
[which-key](https://github.com/folke/which-key.nvim) menu. Many LSP keys are
buffer-local (active only when a language server is attached).

### Leader groups

| Prefix | Group |
|---|---|
| `<leader>b` | Buffers |
| `<leader>c` | Code (LSP) |
| `<leader>d` | Debug |
| `<leader>f` | Find/File |
| `<leader>g` | Git (`gc` Conflict, `gr` Rebase) |
| `<leader>i` | Insert (`in` Nerd Font glyph) |
| `<leader>o` | Obsidian/Notes |
| `<leader>q` | Quit/Session |
| `<leader>u` | UI/Toggle |
| `<leader>w` | Windows |
| `<leader>x` | Diagnostics/Quickfix |
| `<leader>y` | Yocto |

### Buffers — `<leader>b`

| Key | Action |
|---|---|
| `<leader>bn` / `<leader>bp` | Next / previous buffer |
| `<leader>bd` | Delete buffer (keep window) |
| `<leader>bs` | Save if modified |
| `<leader>ba` | Save all modified |

### Find / File — `<leader>f`

| Key | Action |
|---|---|
| `<leader>ff` | Find files (project root) |
| `<leader>fg` | Live grep (project root) |
| `<leader>fr` | Frecency / recent (project) |
| `<leader>fb` | Find buffers |
| `<leader>fe` | Explorer at project root (neo-tree) |
| `<leader>fp` | Find & switch project |

### Code / LSP — `<leader>c` (buffer-local)

| Key | Action |
|---|---|
| `gd` / `gD` | Go to definition / declaration |
| `gi` | Go to implementation |
| `grr` | References (Telescope) |
| `K` | Hover docs |
| `<leader>ca` | Code action |
| `<leader>cr` | Rename |
| `<leader>cs` | Switch header/source (clangd) |
| `[d` / `]d` | Previous / next diagnostic (also `<S-Up>` / `<S-Down>`) |

### Diagnostics / Quickfix — `<leader>x`

| Key | Action |
|---|---|
| `<leader>xx` | Diagnostics: workspace |
| `<leader>xX` | Diagnostics: current buffer |
| `<leader>xq` | Toggle quickfix |
| `<leader>xl` | Toggle loclist |
| `[q` / `]q` | Previous / next quickfix item (`[Q` / `]Q` first/last) |
| `[l` / `]l` | Previous / next loclist item |

### UI / Toggle — `<leader>u`

| Key | Action |
|---|---|
| `<leader>uf` | Toggle format-on-save (buffer) |
| `<leader>uh` | Toggle inlay hints (LSP buffer) |
| `<leader>ui` / `<leader>uI` | Toggle indent-scope (buffer / global) |
| `<leader>us` | Toggle spell |
| `<leader>uw` | Toggle wrap |
| `<leader>ul` | Toggle line numbers |

### Git — `<leader>g`

| Key | Action |
|---|---|
| `<leader>gd` | Diffview: toggle (working tree) |
| `<leader>gs` | Diffview: staged (HEAD vs index) |
| `<leader>gf` / `<leader>gF` | Diffview: file / repo history |
| `<leader>gx` | Diffview: close |
| `<leader>go` | Toggle inline diff overlay (mini.diff) |
| `<leader>gu` | Pick unmerged file |
| `<leader>gC` | Conflicts → quickfix |
| `<leader>gm` | Next merge conflict |
| `]x` / `[x` | Next / previous conflict |
| `<leader>gco` / `<leader>gct` | Take ours / theirs |
| `<leader>gcb` / `<leader>gc0` | Take both / neither |
| `<leader>grc` / `<leader>gra` | Rebase continue / abort |
| `<leader>grs` / `<leader>grS` | Rebase skip / status |

### Debug (DAP) — `<leader>d`

| Key | Action |
|---|---|
| `<F5>` | Start / continue (`<leader>dc` also) |
| `<F10>` / `<F11>` / `<F12>` | Step over / into / out |
| `<leader>db` / `<leader>dB` | Breakpoint / conditional |
| `<leader>dl` | Log point |
| `<leader>dr` | Toggle REPL |
| `<leader>dL` | Run last |
| `<leader>dt` | Terminate |
| `<leader>du` | Toggle DAP UI |
| `<leader>de` | Eval expression (n/v) |

### Obsidian / Notes — `<leader>o`

Per-project vault in `<project>/.vault/` (git-ignored, never synced).

| Key | Action |
|---|---|
| `<leader>ov` | Open this project's vault (create if needed) |
| `<leader>on` | New note |
| `<leader>oo` | Quick switch |
| `<leader>os` | Search (grep) |
| `<leader>ot` / `<leader>oy` | Today's / yesterday's daily |
| `<leader>ob` | Backlinks |
| `<leader>og` | Tags |
| `<leader>ol` | Links in note |
| `<leader>of` | Follow link |
| `<leader>oT` | Insert template |
| `<leader>or` | Rename note |
| `<leader>ox` | Toggle checkbox |
| `<leader>om` / `<leader>oM` | Mindmap: open / live-watch (markmap) |

### Quit / Session — `<leader>q`

| Key | Action |
|---|---|
| `<leader>qq` | Quit all |
| `<leader>qs` / `<leader>ql` / `<leader>qd` | Session save / load / delete (project) |

### Windows — `<leader>w`

| Key | Action |
|---|---|
| <code>&lt;leader&gt;w&#124;</code> / `<leader>w-` | Split vertical / horizontal |
| `<leader>w<Left/Right/Up/Down>` | Swap buffer in direction |
| `<M-Left/Right/Up/Down>` | Focus window (smart-splits) |
| `<M-S-Left/Right/Up/Down>` | Resize window |

### Yocto / BitBake — `<leader>y`

| Key | Action |
|---|---|
| `<leader>yb` | Select active build |
| `<leader>yr` | Find recipes |
| `<leader>yc` | Find classes / includes |
| `<leader>yl` | List layers |
| `<leader>yg` | Grep BitBake files |
| `<leader>ya` | `.bbappend` → recipe |
| `<leader>yi` | Layer info |
| `<leader>yj` | Goto inherit/require under cursor (`gf` in BitBake buffers) |

### Insert Nerd Font glyph — `<leader>in`

| Key | Action |
|---|---|
| `<leader>inc` | Insert glyph character |
| `<leader>inn` | Insert glyph name |

### Editing (non-leader)

| Key | Action |
|---|---|
| `n` / `N` | Next / previous search result, centered |
| `<C-d>` / `<C-u>` | Half-page down / up, centered |
| `J` | Join lines, keep cursor position |
| `<C-S>` | Save (normal/insert/visual) |
| `<Esc>` | Clear search highlight |
| `<` / `>` (visual) | Indent and reselect |
| `p` (visual) | Paste without clobbering the yank register |
| `<C-Left/Right/Up/Down>` | Move line / selection (mini.move) |
| `gc` / `gcc` | Comment (operator / line) |
| `sa` `sd` `sr` `sf` `sh` | Surround add / delete / replace / find / highlight (mini.surround) |
| `af` `if` `ac` `ic` `aa` `ia` | Function / class / parameter textobjects |
| `]f` / `[f` | Next / previous function |

## Layout

```
init.lua              entry point
lua/config/           options, keymaps, lazy bootstrap, LSP, project, vault, yocto, git-conflict
lua/plugins/          one file per plugin
lua/utils/            icons (shared table), diagnostics, nerd-font helpers
lsp/                  one file per language server (driven by vim.lsp.enable)
scripts/              gen_ftype_icons.py (generates the file-type icon map from the spec)
docker/               dev container (Neovim 0.12, tree-sitter, ghcup, node)
```
