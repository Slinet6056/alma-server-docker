# syntax=docker/dockerfile:1
#
# Alma server + 常用开发环境，容器化跑。
# 镜像里是官方的 headless alma-server（Node 守护进程），不需要桌面 / 物理机。
#
#   docker compose up -d --build
#   open http://127.0.0.1:23001
#
FROM debian:bookworm-slim

ARG ALMA_VERSION=0.4.567
ARG TARGETARCH
ARG NODE_VERSION=26.13.0
ARG GO_VERSION=1.27.4
ARG GRADLE_VERSION=9.9.1
ARG JAVA_MAJOR=21
ARG PUID=1000
ARG PGID=1000
# 关掉某个工具链可以 --build-arg WITH_RUST=0 之类，能省掉一大坨体积
ARG WITH_RUST=1
ARG WITH_GO=1
ARG WITH_JVM=1
ARG RUSTUP_MIRROR

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# ---- 基础工具链 -------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git openssh-client gnupg \
      build-essential pkg-config libssl-dev zlib1g-dev libffi-dev libreadline-dev \
      python3 python3-venv python3-pip pipx \
      jq less unzip zip xz-utils procps file sudo \
      tmux vim ripgrep fd-find tree htop bind9-dnsutils iproute2 netcat-openbsd \
      fish zsh socat tini \
      libatomic1 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd

# ---- Node（Alma 自带 node 只给它自己用，开发用这份） -------------------------
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in arm64) NARCH=arm64 ;; *) NARCH=x64 ;; esac; \
    curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
      "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NARCH}.tar.xz" -o /tmp/node.tar.xz; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
        --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md; \
    rm /tmp/node.tar.xz; \
    npm install -g pnpm@latest typescript tsx

# ---- Go --------------------------------------------------------------------
RUN set -eux; \
    if [ "${WITH_GO}" = "1" ]; then \
      case "${TARGETARCH:-amd64}" in arm64) GARCH=arm64 ;; *) GARCH=amd64 ;; esac; \
      curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
        "https://go.dev/dl/go${GO_VERSION}.linux-${GARCH}.tar.gz" -o /tmp/go.tgz; \
      tar -xzf /tmp/go.tgz -C /usr/local; \
      rm /tmp/go.tgz; \
    fi

# ---- JVM：Temurin JDK + Gradle --------------------------------------------
RUN set -eux; \
    if [ "${WITH_JVM}" = "1" ]; then \
      case "${TARGETARCH:-amd64}" in arm64) JARCH=aarch64 ;; *) JARCH=x64 ;; esac; \
      mkdir -p /opt/java; \
      curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
        "https://api.adoptium.net/v3/binary/latest/${JAVA_MAJOR}/ga/linux/${JARCH}/jdk/hotspot/normal/eclipse" -o /tmp/jdk.tar.gz; \
      tar -xzf /tmp/jdk.tar.gz -C /opt/java --strip-components=1; \
      rm /tmp/jdk.tar.gz; \
      ln -sf /opt/java/bin/java /usr/local/bin/java; \
      ln -sf /opt/java/bin/javac /usr/local/bin/javac; \
      curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
        "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip; \
      unzip -q /tmp/gradle.zip -d /opt; \
      rm /tmp/gradle.zip; \
      ln -sf "/opt/gradle-${GRADLE_VERSION}/bin/gradle" /usr/local/bin/gradle; \
    fi

# ---- Alma server（官方 headless 包，自带 node / bun / uv / web UI） -----------
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in arm64) AARCH=arm64 ;; *) AARCH=x64 ;; esac; \
    mkdir -p /opt/alma-server; \
    curl -fL --retry 5 --retry-all-errors --retry-delay 2 \
      "https://github.com/yetone/alma-releases/releases/download/v${ALMA_VERSION}/alma-server-${ALMA_VERSION}-linux-${AARCH}.tar.gz" \
      | tar -xz -C /opt/alma-server --strip-components=1; \
    ln -sf /opt/alma-server/bin/alma-server /usr/local/bin/alma-server; \
    ln -sf /opt/alma-server/resources/cli/alma /usr/local/bin/alma; \
    ln -sf /opt/alma-server/resources/bun/bun /usr/local/bin/bun; \
    ln -sf /opt/alma-server/resources/uv/uv /usr/local/bin/uv; \
    chmod +x /opt/alma-server/bin/alma-server /opt/alma-server/resources/cli/alma

# ---- 用户 ------------------------------------------------------------------
RUN set -eux; \
    groupadd -g "${PGID}" alma; \
    useradd -m -u "${PUID}" -g "${PGID}" -s /usr/bin/fish alma; \
    echo "alma ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/alma; \
    mkdir -p /workspace /home/alma/.local/share/alma /home/alma/.config/alma /home/alma/.local/bin; \
    chown -R alma:alma /workspace /home/alma

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER alma

# alma-server 只监听回环（没有 --host / --bind 参数），所以让它用 23002，
# entrypoint 用 socat 从 0.0.0.0:23001 转发进去。
# ALMA_HEADLESS + ALMA_WEB_DIR 才会把自带的 web 界面挂到 / 上。
ENV HOME=/home/alma \
    USER=alma \
    SHELL=/usr/bin/fish \
    GOPATH=/home/alma/go \
    CARGO_HOME=/home/alma/.cargo \
    RUSTUP_HOME=/home/alma/.rustup \
    PYTHONDONTWRITEBYTECODE=1 \
    PIPX_HOME=/home/alma/.local/pipx \
    PIPX_BIN_DIR=/home/alma/.local/bin \
    ALMA_PORT=23002 \
    ALMA_FORWARD_PORT=23001 \
    ALMA_TOOL_APPROVAL=auto \
    ALMA_DATA_DIR=/home/alma/.local/share/alma \
    ALMA_HEADLESS=1 \
    ALMA_WEB_DIR=/opt/alma-server/resources/web \
    PATH=/home/alma/.local/bin:/home/alma/.cargo/bin:/home/alma/go/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ---- Rust 最后装，改动最频繁 -----------------------------------------------
RUN set -eux; \
    if [ "${WITH_RUST}" = "1" ]; then \
      case "${TARGETARCH:-amd64}" in arm64) TRIPLE=aarch64-unknown-linux-gnu ;; *) TRIPLE=x86_64-unknown-linux-gnu ;; esac; \
      RUSTUP_DIST_SERVER="${RUSTUP_MIRROR:-https://static.rust-lang.org}"; \
      ok=0; \
      for i in 1 2 3 4 5; do \
        if curl -fL --retry 3 --retry-all-errors --retry-delay 3 --connect-timeout 15 -m 180 \
             "${RUSTUP_DIST_SERVER}/rustup/dist/${TRIPLE}/rustup-init" -o /tmp/rustup-init; then ok=1; break; fi; \
        echo "rustup-init 下载失败，第 $i 次重试…"; sleep 5; \
      done; \
      if [ "$ok" != "1" ]; then \
        curl -fL --retry 3 --retry-all-errors --retry-delay 3 -m 600 \
             "https://static.rust-lang.org/rustup/dist/${TRIPLE}/rustup-init" -o /tmp/rustup-init; \
      fi; \
      chmod +x /tmp/rustup-init; \
      RUSTUP_DIST_SERVER="${RUSTUP_DIST_SERVER}" RUSTUP_UPDATE_ROOT="${RUSTUP_DIST_SERVER}/rustup" \
        /tmp/rustup-init -y --profile minimal --default-toolchain stable --no-modify-path; \
      rm /tmp/rustup-init; \
      rustc --version; cargo --version; \
    fi

WORKDIR /workspace
EXPOSE 23001
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
