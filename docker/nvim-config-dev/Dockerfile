# Developer convenience layer on top of dev-tools-build.
#
# Adds what makes interactive work pleasant but is not required to build:
#   - shell tools (less, nvim, tmux, starship, direnv, kitty-terminfo)
#   - gpg + ssh client + sudo for ad-hoc work
#   - smartcard runtime helpers (pcscd, pcsc-tools, yubikey-manager,
#     pinentry-tty) for hands-on mpass YubiKey work
#   - the age-plugin-yubikey runtime binary mpass shells out to
#   - Claude Code CLI
#   - Haskell toolchain via ghcup (ghc, cabal, haskell-language-server)
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
    libgmp-dev \
    libffi-dev \
    libncurses-dev \
    zlib1g-dev \
    libnuma-dev \
    nodejs \
    npm \
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

# tree-sitter CLI: nvim-treesitter's main branch shells out to it to compile
# parsers. In this portable/container path lua/plugins/treesitter.lua calls
# require("nvim-treesitter").install(langs); without the CLI every parser
# build fails with ENOENT: 'tree-sitter'. Use the upstream prebuilt binary --
# `cargo install tree-sitter-cli` would pull in bindgen and need libclang,
# which the image doesn't have. build-essential (gcc) from dev-tools-build
# still does the actual parser compile. NixOS gets parsers from nix instead,
# so this isn't needed there.
ARG TREE_SITTER_VERSION=v0.26.11
RUN set -eux; \
    case "$(uname -m)" in \
      x86_64)  ts_arch="linux-x64"   ;; \
      aarch64) ts_arch="linux-arm64" ;; \
      *)       echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/tree-sitter.gz \
      "https://github.com/tree-sitter/tree-sitter/releases/download/${TREE_SITTER_VERSION}/tree-sitter-${ts_arch}.gz"; \
    gunzip -c /tmp/tree-sitter.gz > /usr/local/bin/tree-sitter; \
    rm /tmp/tree-sitter.gz; \
    chmod +x /usr/local/bin/tree-sitter; \
    tree-sitter --version

# markmap-cli: markmap.nvim shells out to it to render markdown as a browser
# mindmap. Installed globally from the node/npm added to DEV_PACKAGES. NixOS
# should provide markmap-cli via nix instead.
RUN set -eux; \
    npm install -g markmap-cli; \
    markmap --version

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

# Haskell toolchain via ghcup: ghc + cabal + haskell-language-server, so
# lsp/hls.lua's haskell-language-server-wrapper can actually start. Large
# layer (GHC + HLS are multi-GB). The GHC bindist's link/runtime libs
# (libgmp, libffi, ncurses/libtinfo, zlib, libnuma) come from DEV_PACKAGES;
# build-essential is inherited from dev-tools-build. NixOS provides this
# toolchain via nix instead, so it's container-only. GHC_VERSION accepts a
# version, "recommended", or "latest"; bump/pin it as needed.
ARG GHC_VERSION=recommended
RUN set -eux; \
    export BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
           BOOTSTRAP_HASKELL_GHC_VERSION="${GHC_VERSION}" \
           BOOTSTRAP_HASKELL_INSTALL_HLS=1 \
           BOOTSTRAP_HASKELL_ADJUST_BASHRC=0 \
           GHCUP_INSTALL_BASE_PREFIX="/home/${USER_NAME}"; \
    curl --proto '=https' --tlsv1.2 -sSf \
      https://raw.githubusercontent.com/haskell/ghcup-hs/master/scripts/bootstrap/bootstrap-haskell | sh; \
    "/home/${USER_NAME}/.ghcup/bin/ghc" --version; \
    "/home/${USER_NAME}/.ghcup/bin/haskell-language-server-wrapper" --version
ENV PATH="/home/${USER_NAME}/.ghcup/bin:/home/${USER_NAME}/.cabal/bin:${PATH}"

ENV CLAUDE_CONFIG_DIR="/home/${USER_NAME}/.claude"

RUN mkdir -p \
    /home/${USER_NAME}/.config \
    /home/${USER_NAME}/.claude

COPY starship.toml   /home/${USER_NAME}/.config/
COPY bash_rc         /home/${USER_NAME}/.bashrc
COPY dot_gitconfig   /home/${USER_NAME}/.gitconfig
