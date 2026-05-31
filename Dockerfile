# syntax=docker/dockerfile:1.7
FROM ubuntu:26.04

ARG TARGETOS
ARG TARGETARCH

ENV LANG="C.UTF-8"
ENV HOME=/root
ENV DEBIAN_FRONTEND=noninteractive

### BASE ###

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        binutils \
        sudo \
        build-essential \
        bzr \
        curl \
        default-libmysqlclient-dev \
        bind9-dnsutils \
        fd-find \
        gettext \
        git \
        git-lfs \
        gnupg \
        inotify-tools \
        iputils-ping \
        jq \
        libbz2-dev \
        libc6 \
        libc6-dev \
        libcurl4-openssl-dev \
        libdb-dev \
        libedit2 \
        libffi-dev \
        libgcc-15-dev \
        libgdbm-compat-dev \
        libgdbm-dev \
        libgdiplus \
        libgssapi-krb5-2 \
        liblzma-dev \
        libncurses-dev \
        libnss3-dev \
        libpq-dev \
        libpsl-dev \
        libpython3-dev \
        libreadline-dev \
        libsqlite3-dev \
        libssl-dev \
        libstdc++-15-dev \
        libunwind8 \
        libuuid1 \
        libxml2-dev \
        libz3-dev \
        make \
        moreutils \
        netcat-openbsd \
        openssh-client \
        pkg-config \
        protobuf-compiler \
        ripgrep \
        rsync \
        software-properties-common \
        sqlite3 \
        swig \
        tk-dev \
        tzdata \
        universal-ctags \
        unixodbc-dev \
        unzip \
        uuid-dev \
        wget \
        xz-utils \
        zip \
        zlib1g \
        zlib1g-dev \
        fd-find \
        universal-ctags \
    && rm -rf /var/lib/apt/lists/*

### MISE ###

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    install -dm 0755 /etc/apt/keyrings \
    && curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --batch --yes --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg \
    && chmod 0644 /etc/apt/keyrings/mise-archive-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg] https://mise.jdx.dev/deb stable main" > /etc/apt/sources.list.d/mise.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends mise/stable \
    && rm -rf /var/lib/apt/lists/* \
    && echo 'eval "$(mise activate bash)"' >> /etc/profile \
    && mise settings set experimental true \
    && mise settings set override_tool_versions_filenames none \
    && mise settings add idiomatic_version_file_enable_tools "[]" \
    && mise settings add disable_backends asdf \
    && mise settings add disable_backends vfox

ENV PATH=$HOME/.local/share/mise/shims:$PATH

### LLVM ###

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        cmake \
        ccache \
        ninja-build \
        nasm \
        yasm \
        gawk \
        lsb-release \
    && rm -rf /var/lib/apt/lists/* \
    && bash -c "$(curl -fsSL https://apt.llvm.org/llvm.sh)"

### PYTHON ###

ARG PYTHON_VERSIONS="3.14 3.13 3.12 3.11 3.10"

# Install pyenv
ENV PYENV_ROOT=/root/.pyenv
ENV PATH=$PYENV_ROOT/bin:$PATH
RUN git -c advice.detachedHead=0 clone --depth 1 https://github.com/pyenv/pyenv.git "$PYENV_ROOT" \
    && echo 'export PYENV_ROOT="$HOME/.pyenv"' >> /etc/profile \
    && echo 'export PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH"' >> /etc/profile \
    && echo 'eval "$(pyenv init - bash)"' >> /etc/profile \
    && cd "$PYENV_ROOT" \
    && src/configure \
    && make -C src \
    && pyenv install $PYTHON_VERSIONS \
    && rm -rf "$PYENV_ROOT/cache"

# Install pipx for common global package managers (e.g. poetry)
ENV PIPX_BIN_DIR=/root/.local/bin
ENV PATH=$PIPX_BIN_DIR:$PATH
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip \
    --mount=type=cache,target=/root/.cache/pipx \
    apt-get update \
    && apt-get install -y --no-install-recommends pipx \
    && rm -rf /var/lib/apt/lists/* \
    && pipx install --pip-args="--no-cache-dir --no-compile --root-user-action=ignore" poetry==2.1.* uv==0.7.* \
    && for pyv in "${PYENV_ROOT}/versions/"*; do \
         "$pyv/bin/python" -m pip install --no-cache-dir --no-compile --root-user-action=ignore --upgrade pip && \
         "$pyv/bin/pip" install --no-cache-dir --no-compile --root-user-action=ignore ruff black mypy pyright isort pytest; \
       done

# Reduce the verbosity of uv - impacts performance of stdout buffering
ENV UV_NO_PROGRESS=1

### NODE ###

ARG NVM_VERSION=v0.40.2
ARG NODE_VERSION=22

ENV NVM_DIR=/root/.nvm
# Corepack tries to do too much - disable some of its features:
# https://github.com/nodejs/corepack/blob/main/README.md
ENV COREPACK_DEFAULT_TO_LATEST=0
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
ENV COREPACK_ENABLE_AUTO_PIN=0
ENV COREPACK_ENABLE_STRICT=0

RUN --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/root/.cache/yarn \
    --mount=type=cache,target=/root/.local/share/pnpm/store \
    git -c advice.detachedHead=0 clone --branch "$NVM_VERSION" --depth 1 https://github.com/nvm-sh/nvm.git "$NVM_DIR" \
    && echo 'source $NVM_DIR/nvm.sh' >> /etc/profile \
    && echo "prettier\neslint\ntypescript" > $NVM_DIR/default-packages \
    && . $NVM_DIR/nvm.sh \
    # The latest versions of npm aren't supported on node 18, so we install each set differently
    && nvm install 18 && nvm use 18 && npm install -g npm@10.9 pnpm@10.12 && corepack enable && corepack install -g yarn \
    && nvm install 20 && nvm use 20 && npm install -g npm@11.4 pnpm@10.12 && corepack enable && corepack install -g yarn \
    && nvm install 22 && nvm use 22 && npm install -g npm@11.4 pnpm@10.12 && corepack enable && corepack install -g yarn \
    && nvm install 24 && nvm use 24 && npm install -g npm@11.4 pnpm@10.12 && corepack enable && corepack install -g yarn \
    && nvm alias default "$NODE_VERSION" \
    && nvm cache clear \
    && npm cache clean --force || true \
    && pnpm store prune || true \
    && yarn cache clean || true

### BUN ###

ARG BUN_VERSION=1.2.14
RUN --mount=type=cache,target=/root/.cache/mise \
    mise use --global "bun@${BUN_VERSION}" \
    && mise cache clear || true

### JAVA ###

ARG GRADLE_VERSION=8.14
ARG MAVEN_VERSION=3.9.10
# OpenJDK 11 is not available for arm64. Codex Web only uses amd64 which
# does support 11.
ARG AMD_JAVA_VERSIONS="25 24 23 22 21 17 11"
ARG ARM_JAVA_VERSIONS="25 24 23 22 21 17"

RUN --mount=type=cache,target=/root/.cache/mise \
    JAVA_VERSIONS="$( [ "$TARGETARCH" = "arm64" ] && echo "$ARM_JAVA_VERSIONS" || echo "$AMD_JAVA_VERSIONS" )" \
    && for v in $JAVA_VERSIONS; do mise install "java@${v}"; done \
    && mise use --global "java@${JAVA_VERSIONS%% *}" \
    && mise use --global "gradle@${GRADLE_VERSION}" \
    && mise use --global "maven@${MAVEN_VERSION}" \
    && mise cache clear || true

### SWIFT ###
# Swift is intentionally omitted from this fork to keep the cloud development
# image smaller and avoid downloading the ~1GB Swift toolchain during builds.

### RUST ###

ARG RUST_VERSIONS="1.95.0 1.94.0 1.93.0 1.92.0 1.91.1 1.90.0 1.89.0 1.88.0 1.87.0 1.86.0 1.85.1 1.84.1 1.83.0"
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none \
    && . "$HOME/.cargo/env" \
    && echo 'source $HOME/.cargo/env' >> /etc/profile \
    && rustup toolchain install $RUST_VERSIONS --profile minimal --component rustfmt --component clippy \
    && rustup default ${RUST_VERSIONS%% *}

### RUBY ###

ARG RUBY_VERSIONS="3.4.4 3.3.8 3.2.3"
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.cache/mise \
    apt-get update && apt-get install -y --no-install-recommends \
    libyaml-dev \
    libgmp-dev \
    && rm -rf /var/lib/apt/lists/* \
    && for v in $RUBY_VERSIONS; do mise install "ruby@${v}"; done \
    && mise use --global "ruby@${RUBY_VERSIONS%% *}" \
    && mise cache clear || true;

### C++ ###
# gcc is already installed via apt-get above, so these are just additional linters, etc.
RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=cache,target=/root/.cache/pipx \
    pipx install --pip-args="--no-cache-dir --no-compile --root-user-action=ignore" cpplint==2.0.* clang-tidy==20.1.* clang-format==20.1.* cmakelang==0.6.*

### BAZEL ###

ARG BAZELISK_VERSION=v1.26.0

RUN curl -L --fail https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-${TARGETOS}-${TARGETARCH} -o /usr/local/bin/bazelisk \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel

### GO ###

ARG GO_VERSIONS="1.25.1 1.24.3 1.23.8 1.22.12"
ARG GOLANG_CI_LINT_VERSION=2.1.6

# Go defaults GOROOT to /usr/local/go - we just need to update PATH
ENV PATH=/usr/local/go/bin:$HOME/go/bin:$PATH
RUN --mount=type=cache,target=/root/.cache/mise \
    for v in $GO_VERSIONS; do mise install "go@${v}"; done \
    && mise use --global "go@${GO_VERSIONS%% *}" \
    && mise use --global "golangci-lint@${GOLANG_CI_LINT_VERSION}" \
    && mise cache clear || true

### PHP ###

ARG PHP_VERSIONS="8.5 8.4 8.3 8.2"
ENV PHPENV_ROOT=/root/.phpenv
ENV PATH=/root/.phpenv/bin:/root/.phpenv/shims:$PATH

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential pkg-config ccache \
        autoconf bison re2c \
        libgd-dev libedit-dev libicu-dev libjpeg-dev \
        libonig-dev libpng-dev libzip-dev \
        libssl-dev zlib1g-dev libcurl4-openssl-dev libreadline-dev libtidy-dev libxslt1-dev \
    && rm -rf /var/lib/apt/lists/* \
    && git clone https://github.com/phpenv/phpenv.git /root/.phpenv \
    && git clone https://github.com/php-build/php-build.git /root/.phpenv/plugins/php-build \
    && echo 'eval "$(phpenv init - bash)"' >> /etc/profile \
    && bash -lc '\
        eval "$(phpenv init -)" && \
        for v in $PHP_VERSIONS; do \
            phpenv install -s "${v}snapshot"; \
        done && \
        phpenv rehash && \
        phpenv global "${PHP_VERSIONS%% *}snapshot" \
    ' \
    && rm -rf /root/.phpenv/cache

# Composer
RUN curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer

### ELIXIR ###

ARG ERLANG_VERSION=27.1.2
ARG ELIXIR_VERSION=1.18.3
RUN --mount=type=cache,target=/root/.cache/mise \
    mise install "erlang@${ERLANG_VERSION}" "elixir@${ELIXIR_VERSION}-otp-27" \
    && mise use --global "erlang@${ERLANG_VERSION}" "elixir@${ELIXIR_VERSION}-otp-27" \
    && mise cache clear || true

### SETUP SCRIPTS ###

COPY setup_universal.sh /opt/codex/setup_universal.sh
RUN chmod +x /opt/codex/setup_universal.sh

### VERIFICATION SCRIPT ###

COPY verify.sh /opt/verify.sh
RUN chmod +x /opt/verify.sh \
    && PYTHON_VERSIONS="$PYTHON_VERSIONS" \
        NODE_VERSIONS="24 22 20 18" \
        RUST_VERSIONS="$RUST_VERSIONS" \
        GO_VERSIONS="$GO_VERSIONS" \
        RUBY_VERSIONS="$RUBY_VERSIONS" \
        PHP_VERSIONS="$PHP_VERSIONS" \
        JAVA_VERSIONS="$( [ "$TARGETARCH" = "arm64" ] && echo "$ARM_JAVA_VERSIONS" || echo "$AMD_JAVA_VERSIONS" )" \
        "/opt/verify.sh"

### ENTRYPOINT ###

COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

ENTRYPOINT  ["/opt/entrypoint.sh"]
