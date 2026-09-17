# Dev container for maintaining this Neovim config.
#
# Everything here exists to edit, run, lint or test the config itself:
#   - Neovim 0.12 + the tree-sitter CLI the portable path compiles parsers with
#   - the maintenance toolkit the config and its scripts shell out to:
#     ripgrep + fd (telescope), stylua + luacheck (this repo's .stylua.toml /
#     .luacheckrc), shellcheck + shfmt, jq, node/npm (mason's node servers,
#     prettierd/eslint_d, markmap-cli)
#   - kdlfmt + kdl-lsp, built in the throwaway rust-tools stage below so the
#     runtime image ships the two binaries instead of a ~1.5 GB rustup tree
#   - shell ergonomics (tmux, starship, direnv), gpg + ssh, Claude Code
#
# `nvim` in this container loads *this repo* as its config, via the
# ~/.config/nvim symlink created below -- so editing a file and restarting is
# the whole test loop. Checks that must not touch live state (and must not
# rewrite lazy-lock.json) boot a copy instead: scripts/nvim-sandbox.sh.
#
# Anything needed to *compile* things at runtime (cc, python venv, git)
# already lives in nvim-config-build.

# ---------------------------------------------------------------------------
# rust-tools: build the two Rust binaries the config needs, then throw the
# toolchain away. kdlfmt is the KDL formatter conform.nvim runs on save
# (lua/plugins/conform.lua) and kdl-lsp is the KDL language server (lsp/kdl.lua);
# neither is a mason package, and on NixOS both come from nix instead.
# ---------------------------------------------------------------------------
# Same pinned base as nvim-config-build (see the note there); bump together.
FROM debian:13.6@sha256:f324c7ff54321e8d9c588493a20244965938ce0aa50bbd1022d38010e9ffc4b1 AS rust-tools

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install --no-install-recommends -y build-essential ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --profile minimal: no rust-docs/clippy/rustfmt, none of which a build needs.
ARG RUST_TOOLCHAIN=stable
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --default-toolchain "${RUST_TOOLCHAIN}" --profile minimal --no-modify-path

RUN cargo install --locked --root /out kdlfmt kdl-lsp && \
    { strip /out/bin/* || true; }

# ---------------------------------------------------------------------------
# The image people actually run.
# ---------------------------------------------------------------------------
FROM nvim-config-build:latest
ARG USER_NAME=dev
# Where enter-dev-container.sh bind-mounts the repo; the config symlink points
# here. Kept in sync by that script's --build-arg REPO_DIR.
ARG REPO_DIR=/workspaces/nvim
USER root

ARG DEV_PACKAGES="\
    less \
    tmux \
    starship \
    direnv \
    kitty-terminfo \
    gnupg \
    openssh-client \
    sudo \
    nodejs \
    npm \
    ripgrep \
    fd-find \
    jq \
    shellcheck \
    shfmt \
    lua-check \
"

# The `fd` symlink matters: Debian ships the binary as `fdfind`, and telescope
# and neo-tree look for `fd`. The version calls are a build-time assertion that
# the toolkit is actually callable.
RUN apt-get update && \
    apt-get install --no-install-recommends -y ${DEV_PACKAGES} && \
    rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    fd --version && rg --version | head -1 && luacheck --version

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
# which the image doesn't have. build-essential (gcc) from nvim-config-build
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

# stylua: this repo's own Lua formatter (.stylua.toml is committed, .autoformat
# turns format-on-save on, conform maps lua -> stylua). Not in Debian, and
# leaving it to mason means it is missing from the *shell*, where
# scripts/check.sh needs `stylua --check`. Upstream release binary.
ARG STYLUA_VERSION=v2.5.2
RUN set -eux; \
    case "$(uname -m)" in \
      x86_64)  sl_arch="x86_64"  ;; \
      aarch64) sl_arch="aarch64" ;; \
      *)       echo "unsupported arch: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/stylua.zip \
      "https://github.com/JohnnyMorganz/StyLua/releases/download/${STYLUA_VERSION}/stylua-linux-${sl_arch}.zip"; \
    unzip -q -d /usr/local/bin /tmp/stylua.zip stylua; \
    rm /tmp/stylua.zip; \
    chmod +x /usr/local/bin/stylua; \
    stylua --version

# markmap-cli: markmap.nvim shells out to it to render markdown as a browser
# mindmap. Installed globally from the node/npm added to DEV_PACKAGES. NixOS
# should provide markmap-cli via nix instead.
RUN set -eux; \
    npm install -g markmap-cli; \
    markmap --version

COPY --from=rust-tools /out/bin/kdlfmt  /usr/local/bin/kdlfmt
COPY --from=rust-tools /out/bin/kdl-lsp /usr/local/bin/kdl-lsp
# kdl-lsp is a bare language server with no --version, so just prove both
# landed and are runnable.
RUN kdlfmt --version && test -x /usr/local/bin/kdl-lsp

# Optional Haskell toolchain (ghc + cabal + haskell-language-server) so
# lsp/hls.lua's wrapper can actually start. Off by default: it is a multi-GB
# layer for one of 19 language servers, and lua/plugins/mason.lua already
# handles its absence deliberately -- no ghcup on PATH means hls is reported
# as skipped once instead of being retried on every startup. Turn it on with
#   docker build --build-arg WITH_HASKELL=1 ...
# GHC_VERSION accepts a version, "recommended", or "latest".
ARG WITH_HASKELL=0
ARG GHC_VERSION=recommended
RUN set -eux; \
    if [ "${WITH_HASKELL}" = "1" ]; then \
      apt-get update; \
      apt-get install --no-install-recommends -y \
        libgmp-dev libffi-dev libncurses-dev zlib1g-dev libnuma-dev; \
      rm -rf /var/lib/apt/lists/*; \
    fi

RUN set -eux; \
    usermod -aG sudo "${USER_NAME}"; \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USER_NAME}"; \
    chmod 0440 "/etc/sudoers.d/${USER_NAME}"; \
    visudo -c

USER ${USER_NAME}

RUN set -eux; \
    if [ "${WITH_HASKELL}" = "1" ]; then \
      export BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
             BOOTSTRAP_HASKELL_GHC_VERSION="${GHC_VERSION}" \
             BOOTSTRAP_HASKELL_INSTALL_HLS=1 \
             BOOTSTRAP_HASKELL_ADJUST_BASHRC=0 \
             GHCUP_INSTALL_BASE_PREFIX="/home/${USER_NAME}"; \
      curl --proto '=https' --tlsv1.2 -sSf \
        https://raw.githubusercontent.com/haskell/ghcup-hs/master/scripts/bootstrap/bootstrap-haskell | sh; \
      "/home/${USER_NAME}/.ghcup/bin/ghc" --version; \
      "/home/${USER_NAME}/.ghcup/bin/haskell-language-server-wrapper" --version; \
    fi
ENV PATH="/home/${USER_NAME}/.local/bin:/home/${USER_NAME}/.ghcup/bin:/home/${USER_NAME}/.cabal/bin:${PATH}"

# Claude Code native binary (the npm install path is deprecated).
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV CLAUDE_CONFIG_DIR="/home/${USER_NAME}/.claude"
ENV EDITOR=nvim
ENV VISUAL=nvim

# These are the mount points enter-dev-container.sh hangs named volumes on, so
# lazy's plugins, mason's servers and the ~50 compiled treesitter parsers
# survive `docker run --rm`. Creating them here (as the dev user) is what makes
# a fresh volume inherit the right ownership.
RUN mkdir -p \
    /home/${USER_NAME}/.config \
    /home/${USER_NAME}/.claude \
    /home/${USER_NAME}/.local/share/nvim \
    /home/${USER_NAME}/.local/state/nvim \
    /home/${USER_NAME}/.cache/nvim

# Make plain `nvim` load the repo under test. The repo is bind-mounted at
# REPO_DIR (not ~/.config/nvim), so without this every invocation would need
# an XDG_CONFIG_HOME dance. Dangling until the mount exists, which is fine.
# Note that a boot through this symlink writes lazy-lock.json into the repo --
# that is what you want interactively; checks use scripts/nvim-sandbox.sh.
RUN ln -sfn "${REPO_DIR}" /home/${USER_NAME}/.config/nvim

COPY starship.toml   /home/${USER_NAME}/.config/
COPY bash_rc         /home/${USER_NAME}/.bashrc
COPY dot_gitconfig   /home/${USER_NAME}/.gitconfig
