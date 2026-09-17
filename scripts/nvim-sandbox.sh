#!/usr/bin/env bash
#
# Boot this config in a throwaway sandbox.
#
# The repo is not at ~/.config/nvim (in the dev container it is bind-mounted at
# /workspaces/<repo>), and booting it *in place* has a cost: lazy.nvim writes
# lazy-lock.json into stdpath('config'), so any headless check would rewrite
# the committed lockfile -- and with $NVIM_TS_PARSERS set the config takes its
# NixOS path, mason.lua returns {}, and the boot deletes the mason entries from
# that lockfile. So: copy the repo, point XDG_CONFIG_HOME at the copy, and let
# the boot scribble there.
#
#   scripts/nvim-sandbox.sh                 # headless smoke boot, reports errors
#   scripts/nvim-sandbox.sh --lua 'io.stderr:write(vim.g.colors_name)'
#       (write to stderr -- print() is swallowed in a headless boot that
#        quits from a timer, and a chunk that throws fails the run)
#   scripts/nvim-sandbox.sh -- some/file.lua   # real (interactive) nvim on the copy
#   scripts/nvim-sandbox.sh --clean         # also isolate plugin/mason/parser state
#
# By default only the *config* is isolated; plugin, mason and treesitter state
# is shared with the real data dir, so a boot takes seconds instead of
# re-cloning every plugin and recompiling ~50 parsers. --clean isolates
# everything, which is the honest from-scratch test and needs network.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
NVIM="${NVIM:-nvim}"
TIMEOUT_MS="${SANDBOX_MS:-8000}"

clean=0
lua_snippet=""
declare -a nvim_args=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	--clean) clean=1; shift ;;
	--lua) lua_snippet="${2:?--lua needs a chunk}"; shift 2 ;;
	--timeout) TIMEOUT_MS="${2:?--timeout needs milliseconds}"; shift 2 ;;
	--) shift; nvim_args=("$@"); break ;;
	-h | --help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) echo "sandbox: unknown option: $1 (use -- to pass nvim args)" >&2; exit 2 ;;
	esac
done

command -v "${NVIM}" >/dev/null 2>&1 || {
	echo "sandbox: ${NVIM} not found on PATH" >&2
	exit 2
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/nvim-sandbox.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

mkdir -p "${tmp}/cfg/nvim"
tar -C "${REPO}" --exclude=.git -cf - . | tar -C "${tmp}/cfg/nvim" -xf -

export XDG_CONFIG_HOME="${tmp}/cfg"
if [[ ${clean} -eq 1 ]]; then
	export XDG_DATA_HOME="${tmp}/data" XDG_STATE_HOME="${tmp}/state" XDG_CACHE_HOME="${tmp}/cache"
fi

# Passthrough mode: a real nvim (UI or not) against the copy.
if [[ ${#nvim_args[@]} -gt 0 ]]; then
	exec "${NVIM}" "${nvim_args[@]}"
fi

# Otherwise: boot headless, run the optional chunk, and quit. `qa!` (never
# `qa`) -- a modified listed buffer would block headless on the unsaved-changes
# prompt and hang forever.
probe="${tmp}/probe.lua"
cat >"${probe}" <<LUA
local user = [==[${lua_snippet}]==]
vim.defer_fn(function()
	if #user > 0 then
		local chunk, err = loadstring(user)
		if not chunk then
			io.stderr:write("sandbox: bad --lua chunk: " .. tostring(err) .. "\n")
			vim.cmd("cq")
		end
		local ok, ferr = pcall(chunk)
		if not ok then
			-- A chunk that throws is a failed check, not a footnote.
			io.stderr:write("sandbox: --lua error: " .. tostring(ferr) .. "\n")
			vim.cmd("cq")
		end
	end
	local ok, cfg = pcall(require, "lazy.core.config")
	local n = ok and vim.tbl_count(cfg.plugins) or -1
	local loaded = 0
	if ok then
		for _, p in pairs(cfg.plugins) do
			if p._.loaded then
				loaded = loaded + 1
			end
		end
	end
	io.stderr:write(("<<SANDBOX>> plugins=%d loaded=%d\n"):format(n, loaded))
	vim.cmd("qa!")
end, ${TIMEOUT_MS})
LUA

log="${tmp}/boot.log"
set +e
"${NVIM}" --headless -c "luafile ${probe}" >"${log}" 2>&1
status=$?
set -e

summary="$(grep -o '<<SANDBOX>> plugins=[0-9-]* loaded=[0-9]*' "${log}" || true)"
# Anything that looks like a Lua/Vim error in a boot that is supposed to be silent.
errors="$(grep -nE 'E[0-9]{3,4}:|Error detected while processing|Error executing|stack traceback|Failed to (run|source|load)' "${log}" || true)"

if [[ -n "${errors}" ]]; then
	echo "sandbox: errors during boot:" >&2
	printf '%s\n' "${errors}" >&2
	exit 1
fi

if [[ ${status} -ne 0 ]]; then
	echo "sandbox: nvim exited ${status}" >&2
	tail -n 40 "${log}" >&2
	exit 1
fi

if [[ -z "${summary}" ]]; then
	echo "sandbox: config never reached the probe (boot hung or died early)" >&2
	tail -n 40 "${log}" >&2
	exit 1
fi

# The config's own output (:messages, notify) is worth seeing on success too.
grep -v '<<SANDBOX>>' "${log}" | sed '/^$/d' || true
echo "sandbox: clean boot -- ${summary#<<SANDBOX>> }"
