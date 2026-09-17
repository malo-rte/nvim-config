# Base build environment for this Neovim config's dev container.
#
# Owns only the toolchains something in the config compiles or runs *at
# runtime*:
#   - a C toolchain, because the portable path compiles ~50 treesitter parsers
#     locally (tree-sitter CLI shells out to cc) and telescope-fzf-native runs
#     `make`
#   - python3 + venv, because mason installs its PyPI packages (pylsp, ...)
#     into a venv -- without python3-venv there is no ensurepip and those
#     installs fail
#   - git/curl/ca-certificates, because lazy.nvim clones and mason downloads
#
# Developer ergonomics (Neovim itself, the maintenance toolkit, Claude Code,
# node, gpg/ssh, ...) live in nvim-config-dev, which FROMs this image -- and
# which docker/enter-dev-container.sh builds immediately after this one,
# tagging both by those names.

# Pinned to a Debian point release by digest, not the floating `debian:13`
# tag: the base image is the one thing a rebuild months later can change
# underneath the config without anything in this repo moving. Bump both
# Dockerfiles together (docker/nvim-config-build, docker/nvim-config-dev)
# when moving to a newer point release; apt still pulls current packages
# on every build, so pinning costs no security updates.
# Bump with the digest of the new point release's multi-arch manifest:
#   curl -fsSL https://hub.docker.com/v2/repositories/library/debian/tags/<tag> \
#     | python3 -c 'import json,sys; print(json.load(sys.stdin)["digest"])'
# (a 404 there means the official image for that release is not published yet).
# debian 13.6 (trixie), 2026-08-25
FROM debian:13.6@sha256:f324c7ff54321e8d9c588493a20244965938ce0aa50bbd1022d38010e9ffc4b1

ARG USER_NAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.utf8

ARG BUILD_PACKAGES="\
    bash \
    build-essential \
    ca-certificates \
    curl \
    git \
    locales \
    pkg-config \
    python3 \
    python3-venv \
    unzip \
    xz-utils \
"

RUN apt-get update && \
    apt-get install --no-install-recommends -y ${BUILD_PACKAGES} && \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

# Non-root user matching the host UID/GID so bind-mounted source files
# don't show up as root-owned inside the container.
RUN groupadd -g ${USER_GID} ${USER_NAME} && \
    useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USER_NAME}

USER ${USER_NAME}
