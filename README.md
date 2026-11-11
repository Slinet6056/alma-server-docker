# Alma Server Docker

本项目将 [Alma](https://github.com/yetone/alma-releases/releases) 官方发布的 Linux headless 服务端打包为 Docker 镜像，并提供常用开发工具链。项目不包含 Alma 桌面端，也不是 Alma 官方镜像。

## 功能

- 从 Alma Releases 下载指定版本的 `alma-server`，支持 `linux/amd64` 和 `linux/arm64`。
- 容器以非 root 用户运行，并提供 Node.js、Python、Go、Rust、JDK 等开发工具。
- 使用 Docker volume 保存 Alma 配置和数据；工作目录挂载到 `/workspace`。

## 镜像

Docker Hub：[`slinet6056/alma-server`](https://hub.docker.com/r/slinet6056/alma-server)，支持 `linux/amd64` 和 `linux/arm64`。

| 标签       | 说明                             |
| ---------- | -------------------------------- |
| `latest`   | 每日跟随 Alma 最新稳定版本构建   |
| `<版本号>` | 对应的 Alma 版本，例如 `0.4.571` |

同一版本标签可能随重新构建而更新；需要固定镜像内容时，请使用 digest。

## 快速开始

需要已安装并运行 Docker Engine。

```sh
mkdir -p workspace
docker volume create alma-home
docker run -d \
  --name alma-server \
  --restart unless-stopped \
  -p 127.0.0.1:23011:23001 \
  -v alma-home:/home/alma \
  -v "$PWD/workspace:/workspace" \
  slinet6056/alma-server:latest
```

Web 界面地址为 `http://127.0.0.1:23011`。首次使用时，在设置中配置模型服务商及凭据。Alma 数据和配置保存在 `alma-home` volume，项目文件保存在本地 `workspace` 目录。

## 端口与数据

- 容器端口 `23001`：Web/API 入口，示例映射到宿主机的 `127.0.0.1:23011`。
- `/workspace`：工作目录，建议绑定挂载项目目录。
- `/home/alma`：Alma 配置、凭据和会话数据，建议使用持久化 Docker volume。

`docker compose down -v` 会删除 Compose 管理的持久化 volume，其中可能包含 Alma 配置和会话数据。除非确实要清除这些数据，否则不要添加 `-v`。

## 常用操作

```sh
# 查看日志
docker logs -f alma-server

# 进入容器
docker exec -it alma-server bash

# 停止或启动容器
docker stop alma-server
docker start alma-server
```

## 远程访问

默认只将端口绑定到本机。不要未经认证直接暴露到公网；远程访问可使用 SSH 转发：

```sh
ssh -N -L 23011:127.0.0.1:23011 <用户>@<服务器地址>
```

然后在本机打开 `http://127.0.0.1:23011`。

## 本地构建

需要 Docker Engine 和 Docker Compose：

```sh
mkdir -p workspace
docker compose up -d --build
```

本地构建的 Alma 版本由 `docker-compose.yml` 中的 `ALMA_VERSION` 构建参数指定。构建其他版本时修改该值。构建完成后，可用 `docker compose logs -f` 查看日志，用 `docker compose down` 停止服务。

Linux 主机的 UID/GID 如果不是 `1000`，请将 Compose 中的 `PUID`、`PGID` 改为 `id -u`、`id -g` 的输出再构建，以便容器用户读写绑定挂载目录。预构建镜像默认使用 UID/GID `1000:1000`。

可通过 Docker build 参数关闭不需要的工具链以减少镜像体积：

```sh
docker compose build \
  --build-arg WITH_RUST=0 \
  --build-arg WITH_GO=0 \
  --build-arg WITH_JVM=0
```

| 构建参数                             | 默认值          | 用途                                     |
| ------------------------------------ | --------------- | ---------------------------------------- |
| `ALMA_VERSION`                       | `0.4.567`       | Alma 版本号，不带 `v` 前缀               |
| `NODE_VERSION`                       | `26.13.0`       | 开发用 Node.js 版本                      |
| `GO_VERSION`                         | `1.27.4`        | Go 版本                                  |
| `JAVA_MAJOR`                         | `21`            | Temurin JDK 主版本                       |
| `GRADLE_VERSION`                     | `9.9.1`         | Gradle 版本                              |
| `WITH_RUST` / `WITH_GO` / `WITH_JVM` | `1`             | 设为 `0` 时跳过对应工具链                |
| `RUSTUP_MIRROR`                      | 不设置          | 默认使用 Rust 官方源，可按需指定镜像地址 |
| `PUID` / `PGID`                      | `1000` / `1000` | 容器用户及用户组 ID                      |
