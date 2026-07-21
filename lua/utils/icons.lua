-- lua/utils/icons.lua
--
-- Single source of truth for the semantic status glyphs shared across the
-- config (diagnostic signs, statusline, quickfix, file explorer git column).
-- Having one table keeps the renderers from drifting apart, which is exactly
-- what DEV-TOOLS-DES-0004 forbids (§86 semantic consistency: one icon, one
-- meaning, stable across views and modules). Code points follow the alert
-- vocabulary (§78 / §39) and the git vocabulary (§35 per-file, §37 repo).
--
-- Nerd Fonts >= 3.0; the glyph mapping is pinned (see utils.nerdfont and
-- §91 nerd font version policy) so code points do not shift between releases.

local M = {}

-- Pinned Nerd Font mapping metadata (DEV-TOOLS-DES-0004 §91).
M.nerd_font = {
	minimum_version = "3.0",
	mapping_version = "3.4.0", -- ryanoasis/nerd-fonts v3.4.0 glyphnames.json
}

-- Diagnostic severities -- one glyph per concept, used everywhere.
--   error  nf-cod-error       U+EA87   (spec Error)
--   warn   nf-fa-warning      U+F071   (spec Warning)
--   info   nf-fa-info_circle  U+F05A   (spec Information)
--   hint   nf-cod-lightbulb   U+EA61   (editor-local; the spec has no Hint)
M.diagnostics = {
	error = "",
	warn = "",
	info = "",
	hint = "",
}

-- Per-file git state (DEV-TOOLS-DES-0004 §35). All Codicon nf-cod-diff_*
-- except untracked (nf-fa-question) and conflict (nf-cod-git_merge), per the
-- spec's fixed per-concept classes (§ "Git rules").
--   added EADC, modified EADE, deleted EADF, renamed EAE0, copied EBCC,
--   untracked F128, ignored EADD, type_changed EAE1, conflict EAFE,
--   submodule EAEC.
-- staged/unstaged are editor-local: §36 models staging as a two-column view,
-- which a single-symbol renderer (neo-tree) cannot express, so these use
-- nf-cod-check / nf-cod-edit and staging is otherwise carried by colour (§89).
M.git = {
	added = "",
	modified = "",
	deleted = "",
	renamed = "",
	copied = "",
	untracked = "",
	ignored = "",
	type_changed = "",
	conflict = "",
	submodule = "",
	staged = "",
	unstaged = "",
}

-- Repository-level git chrome (DEV-TOOLS-DES-0004 §37).
--   repo F401 (nf-oct-repo), branch E0A0 (nf-pl-branch), tag F02B (nf-fa-tag),
--   stash F487 (nf-oct-package); ahead/behind stay ASCII per the spec.
M.git_repo = {
	repo = "",
	branch = "",
	tag = "",
	stash = "",
	ahead = "↑",
	behind = "↓",
}

-- Other file-state glyphs.
--   readonly  nf-md-lock_outline  U+F033E  (spec §33 Read-only)
M.file = {
	readonly = "󰌾",
	modified = "[+]",
}

-- LSP completion / symbol kinds (blink.cmp). Not governed by
-- DEV-TOOLS-DES-0004 (it defines no completion-kind vocabulary), but kept
-- here as the single source of truth. Function/Method use md-function_variant
-- (U+F0871) rather than md-function (U+F0295) to avoid clashing with the
-- .sig/.sign file glyph in ftype_icons (§29).
M.lsp_kind = {
	Text = "󰉿",
	Method = "󰡱",
	Function = "󰡱",
	Constructor = "󰒓",
	Field = "󰜢",
	Variable = "󰆦",
	Property = "󰖷",
	Class = "󱡠",
	Interface = "󱡠",
	Struct = "󱡠",
	Module = "󰅩",
	Unit = "󰪚",
	Value = "󰦨",
	Enum = "󰦨",
	EnumMember = "󰦨",
	Keyword = "󰻾",
	Constant = "󰏿",
	Snippet = "󱄽",
	Color = "󰏘",
	File = "󰈔",
	Reference = "󰬲",
	Folder = "󰉋",
	Event = "󱐋",
	Operator = "󰪚",
	TypeParameter = "󰬛",
}

-- Autoformat (format-on-save) status indicator -- editor-local. Shown in
-- the statusline: on = nf-md-auto_fix (U+F0068), off = nf-md-cancel /
-- slashed (U+F073A), so the state reads without relying on colour.
M.autoformat = { on = "󰁨", off = "󰜺" }

return M
