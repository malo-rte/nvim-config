# Developer convenience layer on top of dev-tools-build.
#
# Adds what makes interactive work pleasant but is not required to build:
#   - shell tools (less, nvim, tmux, starship, direnv, kitty-terminfo)
#   - gpg + ssh client + sudo for ad-hoc work
#   - smartcard runtime helpers (pcscd, pcsc-tools, yubikey-manager,
#     pinentry-tty) for hands-on mpass YubiKey work
#   - the age-plugin-yubikey runtime binary mpass shells out to
#   - Claude Code CLI
#
# Anything actually needed to compile workspace crates or render the
# docs already lives in dev-tools-build.

FROM dev-tools-build:latest
ARG USER_NAME=dev
USER root

ARG DEV_PACKAGES="\
    less \
    tmux \
    starship \
    direnv \
    kitty-terminfo \
    iputils-ping \
    gnupg \
    openssh-client \
    sudo \
    pcscd \
    pcsc-tools \
    yubikey-manager \
    pinentry-tty \
"

RUN apt-get update && \
    apt-get install --no-install-recommends -y ${DEV_PACKAGES} && \
    rm -rf /var/lib/apt/lists/*

# Neovim from the upstream release tarball instead of Debian apt. The apt
# package (0.10.x on trixie) lags several minor versions behind, while the
# config targets 0.11+ APIs (vim.lsp.enable, vim.hl.on_yank,
# vim.diagnostic.jump, nvim-treesitter's main branch). Pinned to a 0.12
# release via NVIM_VERSION; bump this ARG to move along the 0.12.x line.
# (Don't use the "stable" tag -- it jumps to 0.13 once that releases.)
ARG NVIM_VERSION=v0.12.4
RUN set -eux; \
    case "$(uname -m)" in \
      x86_64)  asset="nvim-linux-x86_64" ;; \
      aarch64) asset="nvim-linux-arm64"  ;; \
      *)       echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/nvim.tar.gz \
      "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${asset}.tar.gz"; \
    tar -C /opt -xzf /tmp/nvim.tar.gz; \
    rm /tmp/nvim.tar.gz; \
    ln -sf "/opt/${asset}/bin/nvim" /usr/local/bin/nvim; \
    nvim --version | head -1

RUN set -eux; \
    usermod -aG sudo "${USER_NAME}"; \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER_NAME}"; \
    chmod 0440 "/etc/sudoers.d/${USER_NAME}"; \
    visudo -c

USER ${USER_NAME}

# Claude Code native binary (the npm install path is deprecated).
RUN curl -fsSL https://claude.ai/install.sh | bash

# age-plugin-yubikey: runtime tool that mpass shells out to at
# decrypt time for YubiKey-backed identities (ADR 0003 + the M3
# subsection in decisions/). The build deps (Rust toolchain,
# libpcsclite-dev, libusb-1.0-0-dev) come from dev-tools-build.
RUN cargo install --locked age-plugin-yubikey

# tree-sitter CLI: nvim-treesitter's main branch shells out to it to
# compile parsers. In this portable/container path lua/plugins/treesitter.lua
# calls require("nvim-treesitter").install(langs); without the CLI every
# parser build fails with ENOENT. (On NixOS parsers come from nix instead,
# so this isn't needed there.) build-essential (gcc) comes from
# dev-tools-build for the actual compilation step.
RUN cargo install --locked tree-sitter-cli

ENV CLAUDE_CONFIG_DIR="/home/${USER_NAME}/.claude"

RUN mkdir -p \
    /home/${USER_NAME}/.config \
    /home/${USER_NAME}/.claude

COPY starship.toml   /home/${USER_NAME}/.config/
COPY bash_rc         /home/${USER_NAME}/.bashrc
COPY dot_gitconfig   /home/${USER_NAME}/.gitconfig
