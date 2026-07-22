# Notes for Claude Code

## Icons / Nerd Font glyphs

**This setup's terminal/font does NOT render Plane-15 glyphs** — the
`nf-md-*` (Material Design) icons, which live in Unicode Plane 15 / SPUA-A
(codepoints `U+F0000` and above). They come out blank/invisible.

Use **BMP-PUA** glyphs instead (`U+E000`–`U+F8FF`): `nf-fa-*`, `nf-cod-*`,
`nf-oct-*`, `nf-seti-*`, `nf-dev-*`, `nf-custom-*`. These render fine.

- Quick check: a codepoint `>= 0xF0000` is Plane 15 → avoid; `0xE000`–`0xF8FF`
  is BMP-PUA → OK.
- Shared, user-facing status glyphs live in `lua/utils/icons.lua`
  (diagnostics, git, autoformat, lsp_kind, …) — keep new ones BMP-PUA.
- The file-type icon map (`lua/utils/ftype_icons.lua`) is generated from the
  DEV-TOOLS-DES-0004 spec and *does* contain `nf-md-*` codepoints; those go
  through devicons/mini.icons for the tree, where they may also not show — the
  BMP rule applies anywhere a glyph must be visible in this terminal.
