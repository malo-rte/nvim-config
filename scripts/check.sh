#!/usr/bin/env bash
#
# Every check this config can run on itself, in one command.
#
#   scripts/check.sh              # run them all, report at the end
#   scripts/check.sh --list       # names only
#   scripts/check.sh format lua   # just these checks
#   scripts/check.sh --fix        # let the formatters write (stylua, shfmt)
#
# Meant for the dev container (docker/enter-dev-container.sh scripts/check.sh),
# where every tool below is on PATH. Outside it, a missing tool is reported as
# SKIP rather than failing the run -- the point is to be runnable anywhere, and
# honest about what it could not check.
#
# Exit 0 = everything that could run passed.
set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO}" || exit 2

FIX=0
declare -a WANT=()
for arg in "$@"; do
	case "${arg}" in
	--fix) FIX=1 ;;
	--list) sed -n 's/^check_\([a-z]*\)().*/\1/p' "${BASH_SOURCE[0]}"; exit 0 ;;
	-h | --help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
	-*) echo "check: unknown option ${arg}" >&2; exit 2 ;;
	*) WANT+=("${arg}") ;;
	esac
done

PASS=(); FAIL=(); SKIP=()
bold() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
pass() { PASS+=("$1"); printf '   ok: %s\n' "${2:-}"; }
fail() { FAIL+=("$1"); printf '   FAIL: %s\n' "${2:-}"; }
skip() { SKIP+=("$1"); printf '   skip: %s\n' "${2:-}"; }
have() { command -v "$1" >/dev/null 2>&1; }

LUA_FILES=(init.lua)
while IFS= read -r f; do LUA_FILES+=("$f"); done < <(find lua lsp -name '*.lua' | sort)
SH_FILES=(scripts/check.sh scripts/nvim-sandbox.sh docker/enter-dev-container.sh)

# --- format: stylua, against the committed .stylua.toml -------------------
check_format() {
	have stylua || { skip format "stylua not installed"; return; }
	if [[ ${FIX} -eq 1 ]]; then
		if stylua "${LUA_FILES[@]}"; then
			pass format "formatted"
		else
			fail format "stylua errored"
		fi
		return
	fi
	local out
	if out="$(stylua --check "${LUA_FILES[@]}" 2>&1)"; then
		pass format "${#LUA_FILES[@]} lua files match .stylua.toml"
	else
		printf '%s\n' "${out}" | head -40
		fail format "stylua --check (run scripts/check.sh --fix)"
	fi
}

# --- lua: syntax of every file, with no config loaded ---------------------
# Cheap and total: catches a typo in a file lazy only loads on some filetype.
# One nvim for the whole tree, `-u NONE` so nothing but the parser is involved.
check_lua() {
	have nvim || { skip lua "nvim not installed"; return; }
	local probe out
	probe="$(mktemp)"
	cat >"${probe}" <<'LUAPROBE'
local files = vim.fn.glob("init.lua", false, true)
vim.list_extend(files, vim.fn.glob("lua/**/*.lua", false, true))
vim.list_extend(files, vim.fn.glob("lsp/*.lua", false, true))
local bad = 0
for _, f in ipairs(files) do
	local chunk, err = loadfile(f)
	if not chunk then
		bad = bad + 1
		io.stderr:write(err .. "\n")
	end
end
io.stderr:write(("<<LUA>> files=%d bad=%d\n"):format(#files, bad))
vim.cmd(bad == 0 and "qa!" or "cq")
LUAPROBE
	out="$(nvim --headless -u NONE -c "luafile ${probe}" 2>&1)"
	local status=$?
	rm -f "${probe}"
	local summary="${out##*<<LUA>> }"
	if [[ ${status} -eq 0 ]]; then
		pass lua "${summary%%$'\n'*}"
	else
		printf '%s\n' "${out}" | grep -v '<<LUA>>' | head -20
		fail lua "syntax errors above"
	fi
}

# --- luacheck: the linter nvim-lint runs on this tree ---------------------
# Exit 1 is "warnings" (unused locals and friends) and is reported, not fatal;
# 2+ is a syntax or config error and is.
check_luacheck() {
	have luacheck || { skip luacheck "luacheck not installed"; return; }
	local out status
	out="$(luacheck --no-color --codes -q "${LUA_FILES[@]}" 2>&1)"; status=$?
	case ${status} in
	0) pass luacheck "clean" ;;
	1) printf '%s\n' "${out}" | tail -25; pass luacheck "warnings only (see above)" ;;
	*) printf '%s\n' "${out}" | tail -25; fail luacheck "exit ${status}" ;;
	esac
}

# --- icons: Plane-15 glyph inventory (CLAUDE.md icon rules) --------------
# nf-md-* glyphs (U+F0000+) do not render in the maintainer's terminal, so new
# status glyphs are meant to be BMP-PUA. Some existing tables use Plane-15 on
# purpose (lsp_kind, file.readonly), so this reports rather than fails -- the
# value is noticing when a *new* one appears. ftype_icons.lua is generated from
# the spec and is exempt.
check_icons() {
	local out
	out="$(python3 - <<'PYICONS'
import collections, pathlib
hits = collections.defaultdict(list)
for p in sorted(pathlib.Path(".").glob("lua/**/*.lua")) + sorted(pathlib.Path(".").glob("lsp/*.lua")):
    if p.name == "ftype_icons.lua":
        continue
    for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        for ch in line:
            if ord(ch) >= 0xF0000:
                hits[str(p)].append("%d:U+%X" % (n, ord(ch)))
                break
for f, where in sorted(hits.items()):
    head = ", ".join(where[:6]) + (", ..." if len(where) > 6 else "")
    print("%s: %d Plane-15 glyph(s) -- %s" % (f, len(where), head))
PYICONS
	)"
	if [[ -z "${out}" ]]; then
		pass icons "no Plane-15 glyphs outside the generated map"
	else
		printf '%s\n' "${out}"
		pass icons "Plane-15 glyphs present (listed above) -- prefer BMP-PUA for new ones"
	fi
}

# --- generated: ftype_icons.lua still matches the spec --------------------
check_generated() {
	have git || { skip generated "git not available"; return; }
	if ! git diff --quiet -- lua/utils/ftype_icons.lua; then
		skip generated "lua/utils/ftype_icons.lua already modified in the worktree"
		return
	fi
	if ! python3 scripts/gen_ftype_icons.py >/dev/null 2>&1; then
		fail generated "gen_ftype_icons.py errored"
		return
	fi
	if git diff --quiet -- lua/utils/ftype_icons.lua; then
		pass generated "ftype_icons.lua matches the spec"
	else
		git checkout -- lua/utils/ftype_icons.lua
		fail generated "ftype_icons.lua is stale (run python3 scripts/gen_ftype_icons.py)"
	fi
}

# --- shell: the scripts in this repo -------------------------------------
check_shell() {
	local f bad=0
	for f in "${SH_FILES[@]}"; do bash -n "${f}" || bad=1; done
	[[ ${bad} -eq 1 ]] && { fail shell "bash -n failed"; return; }
	if have shellcheck; then
		if shellcheck "${SH_FILES[@]}"; then
			pass shell "bash -n + shellcheck"
		else
			fail shell "shellcheck findings above"
		fi
	else
		pass shell "bash -n (shellcheck not installed)"
	fi
	if have shfmt && [[ ${FIX} -eq 1 ]]; then shfmt -w "${SH_FILES[@]}"; fi
}

# --- python: the two generator/audit scripts -----------------------------
check_python() {
	have python3 || { skip python "python3 not installed"; return; }
	if python3 -m py_compile scripts/*.py; then
		pass python "scripts compile"
	else
		fail python "syntax errors above"
	fi
	rm -rf scripts/__pycache__
}

# --- boot: the config actually starts ------------------------------------
check_boot() {
	have nvim || { skip boot "nvim not installed"; return; }
	if scripts/nvim-sandbox.sh; then
		pass boot "headless boot clean"
	else
		fail boot "see the boot errors above"
	fi
}

# --- keymaps: every mapping is named in README.md ------------------------
check_keymaps() {
	have nvim || { skip keymaps "nvim not installed"; return; }
	python3 scripts/audit_keymaps.py
	case $? in
	0) pass keymaps "all documented" ;;
	1) fail keymaps "undocumented mappings above" ;;
	*) fail keymaps "the audit itself could not run" ;;
	esac
}

ORDER=(format lua luacheck icons generated shell python boot keymaps)
[[ ${#WANT[@]} -gt 0 ]] && ORDER=("${WANT[@]}")

for name in "${ORDER[@]}"; do
	if ! declare -F "check_${name}" >/dev/null; then
		echo "check: no such check: ${name}" >&2
		exit 2
	fi
	bold "${name}"
	"check_${name}"
done

printf '\n\033[1m== summary\033[0m\n'
printf '   passed: %s\n' "${PASS[*]:-none}"
[[ ${#SKIP[@]} -gt 0 ]] && printf '   skipped: %s\n' "${SKIP[*]}"
if [[ ${#FAIL[@]} -gt 0 ]]; then
	printf '   FAILED: %s\n' "${FAIL[*]}"
	exit 1
fi
echo "   all good"
