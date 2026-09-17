#!/usr/bin/env  bash
#
# Build (if needed) and enter the dev container for this Neovim config.
#
#   ./docker/enter-dev-container.sh                 # interactive shell
#   ./docker/enter-dev-container.sh scripts/check.sh  # run one command, exit
#   SKIP_BUILD=1 ./docker/enter-dev-container.sh    # reuse the existing images
#   WITH_HASKELL=1 ./docker/enter-dev-container.sh  # include ghcup/ghc/hls
#
# Inside, plain `nvim` loads this repo (the image symlinks ~/.config/nvim at
# the bind mount), and lazy/mason/treesitter state lives in named volumes so
# the first-run install and the ~50 parser compiles happen once, not on every
# `docker run --rm`.
set -euo pipefail

BUILD_IMAGE="nvim-config-build"
DEV_IMAGE="nvim-config-dev"

MOUNT_SUFFIX=""
if [[ -f /sys/fs/selinux/enforce ]] && [[ "$(cat /sys/fs/selinux/enforce)" != "0" ]]; then
	MOUNT_SUFFIX=":z"
fi

REPO_DIR="$(git rev-parse --show-toplevel 2>/dev/null)"
REPO_NAME="$(basename "${REPO_DIR}")"

REPO_DIR_CONTAINER="${REPO_DIR_CONTAINER:-/workspaces/${REPO_NAME}}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

CLAUDE_STATE_HOST="${XDG_STATE_HOME:-$HOME/.local/state}/claude-dev/${REPO_NAME}"
CLAUDE_CONFIG_CONTAINER="/home/$(id -un)/.claude"

mkdir -p "${CLAUDE_STATE_HOST}"

CLAUDE_FLAGS=(-v "${CLAUDE_STATE_HOST}:${CLAUDE_CONFIG_CONTAINER}${MOUNT_SUFFIX}")

# Neovim's own state, kept in named volumes rather than thrown away with the
# container: lazy's plugin clones and lockfile-driven checkouts, mason's
# servers, and the treesitter parsers the portable path compiles locally
# (~50 of them -- minutes of cc on a cold start). The image pre-creates these
# paths as the dev user so a fresh volume inherits the right ownership.
# Drop them with: docker volume rm nvim-dev-${REPO_NAME}-{share,state,cache}
NVIM_HOME="/home/$(id -un)"
NVIM_STATE_FLAGS=(
	-v "nvim-dev-${REPO_NAME}-share:${NVIM_HOME}/.local/share/nvim${MOUNT_SUFFIX}"
	-v "nvim-dev-${REPO_NAME}-state:${NVIM_HOME}/.local/state/nvim${MOUNT_SUFFIX}"
	-v "nvim-dev-${REPO_NAME}-cache:${NVIM_HOME}/.cache/nvim${MOUNT_SUFFIX}"
)

SSH_FLAGS=()
if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
	SSH_FLAGS+=(-v "${SSH_AUTH_SOCK}:${SSH_AUTH_SOCK}" -e SSH_AUTH_SOCK)
	# Add the agent's group to avoid EACCES on the socket
	if command -v stat >/dev/null 2>&1; then
		SSH_GID="$(stat -c %g "$SSH_AUTH_SOCK" 2>/dev/null || echo "")"
		[[ -n "$SSH_GID" ]] && SSH_FLAGS+=(--group-add "$SSH_GID")
	fi
fi

# Mount user SSH config read-only into the container
if [[ -d "${HOME}/.ssh" ]]; then
	SSH_FLAGS+=(-v "${HOME}/.ssh:/home/$(id -un)/.ssh:ro${MOUNT_SUFFIX}")
fi

# build_container <image> [extra --build-arg ...]
# Only the args an image actually declares are passed; docker warns about
# unconsumed ones.
build_container() {
	local image="$1"
	shift

	docker build \
		--build-arg USER_NAME="$(id -un)" \
		--build-arg USER_UID="$(id -u)" \
		--build-arg USER_GID="$(id -g)" \
		"$@" \
		-f "${SCRIPT_DIR}/${image}/Dockerfile" \
		-t "${image}" \
		"${SCRIPT_DIR}/${image}"
}

run_container() {
	local image="$1"
	shift
	local tz_flags=()
	local locale_flags=()

	if [[ -f /etc/localtime ]]; then
		tz_flags+=(--volume "/etc/localtime:/etc/localtime:ro${MOUNT_SUFFIX}")
	fi

	if [[ -f /etc/timezone ]]; then
		local host_tz
		host_tz="$(tr -d '\n' </etc/timezone)"
		tz_flags+=(--volume "/etc/timezone:/etc/timezone:ro${MOUNT_SUFFIX}")
		[[ -n "${host_tz}" ]] && tz_flags+=(-e "TZ=${host_tz}")
	fi

	[[ -n "${LANG:-}" ]] && locale_flags+=(-e "LANG=${LANG}")
	[[ -n "${LC_ALL:-}" ]] && locale_flags+=(-e "LC_ALL=${LC_ALL}")
	[[ -n "${LC_TIME:-}" ]] && locale_flags+=(-e "LC_TIME=${LC_TIME}")

	# A command given on the command line runs non-interactively (no TTY when
	# stdout is a pipe, so CI-style `... scripts/check.sh > log` behaves).
	local tty_flags=(-i)
	[[ -t 0 && -t 1 ]] && tty_flags+=(-t)

	local cmd=("$@")
	[[ ${#cmd[@]} -eq 0 ]] && cmd=(bash)

	docker run --rm --init \
		"${tty_flags[@]}" \
		--user "$(id -u):$(id -g)" \
		"${CLAUDE_FLAGS[@]}" \
		"${NVIM_STATE_FLAGS[@]}" \
		"${SSH_FLAGS[@]}" \
		"${tz_flags[@]}" \
		"${locale_flags[@]}" \
		--volume "${REPO_DIR}:${REPO_DIR_CONTAINER}${MOUNT_SUFFIX}" \
		-w "${REPO_DIR_CONTAINER}" \
		"${image}:latest" "${cmd[@]}"
}

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
	build_container "${BUILD_IMAGE}"
	build_container "${DEV_IMAGE}" \
		--build-arg REPO_DIR="${REPO_DIR_CONTAINER}" \
		--build-arg WITH_HASKELL="${WITH_HASKELL:-0}"
fi

run_container "${DEV_IMAGE}" "$@"
