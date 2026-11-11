#!/usr/bin/env bash
set -euo pipefail

LISTEN_PORT="${ALMA_FORWARD_PORT:-23001}"
UPSTREAM_PORT="${ALMA_PORT:-23002}"

mkdir -p "${ALMA_DATA_DIR:-$HOME/.local/share/alma}" \
         "$HOME/.config/alma" "$HOME/.local/bin" /workspace

# 挂进来的仓库属主经常和容器用户对不上，省得 git 天天喊 dubious ownership
git config --global --add safe.directory /workspace 2>/dev/null || true
git config --global --add safe.directory "*" 2>/dev/null || true

# alma-server 只会 bind 127.0.0.1，容器外面连不到，
# 所以在 0.0.0.0:23001 起一个 socat 转发到它。
# 已经有进程占了 23001（比如你自己改成了 --port 23001）就不起。
if ! nc -z 127.0.0.1 "${LISTEN_PORT}" >/dev/null 2>&1; then
  socat "TCP-LISTEN:${LISTEN_PORT},fork,reuseaddr,bind=0.0.0.0" \
        "TCP:127.0.0.1:${UPSTREAM_PORT}" &
fi

if [ "$#" -eq 0 ]; then
  set -- serve
fi

case "$1" in
  serve|pair|unpair|status|chat|help|version|--version|-v|--*)
    exec alma-server "$@" ;;
  *)
    exec "$@" ;;
esac
