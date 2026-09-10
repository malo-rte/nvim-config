# Base build environment for this Neovim config's dev container.
#
# Owns the toolchains the config's tooling needs to build things locally:
# compilers and dev headers for treesitter parsers and native plugin bits,
# Rust, and Python. Developer ergonomics (shell tools, Neovim itself, Claude
# Code, gpg, ssh, smartcard runtime, ghcup, ...) live in nvim-config-dev,
# which FROMs this image -- and which docker/enter-dev-container.sh builds
# immediately after this one, tagging both by those names.

FROM debian:13

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
    file \
    git \
    locales \
    pkg-config \
    python3 \
    python3-yaml \
    wget \
    xz-utils \
    libxkbcommon-dev \
    libwayland-dev \
    libpcsclite-dev \
    libusb-1.0-0-dev \
    asciidoctor \
    ruby \
    ruby-dev \
    default-jre-headless \
    graphviz \
    libarchive-tools \
    device-tree-compiler \
    poppler-utils \
    ffmpeg \
"

RUN apt-get update && \
    apt-get install --no-install-recommends -y ${BUILD_PACKAGES} && \
    localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

# AsciiDoc gems: PDF output (asciidoctor-pdf + rouge for syntax highlighting),
# inline diagrams (asciidoctor-diagram + plantuml bridge).
RUN gem install --no-document \
    asciidoctor-pdf \
    rouge \
    asciidoctor-diagram \
    asciidoctor-diagram-plantuml

# Non-root user matching the host UID/GID so bind-mounted source files
# don't show up as root-owned inside the container.
RUN groupadd -g ${USER_GID} ${USER_NAME} && \
    useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USER_NAME}

USER ${USER_NAME}

# Rust toolchain via rustup, per-user. The dev image inherits this via
# /home/dev/.cargo/ so the toolchain isn't reinstalled in the next layer.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --default-toolchain stable --profile default --no-modify-path
ENV PATH="/home/${USER_NAME}/.cargo/bin:${PATH}"
