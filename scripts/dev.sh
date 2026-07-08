#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="$ROOT_DIR/api"
UI_DIR="$ROOT_DIR/ui"
SANDBOX_DIR="$ROOT_DIR/sandbox"
LOG_DIR="$ROOT_DIR/logs"

mkdir -p "$LOG_DIR"

API_PID=""
UI_PID=""

info() {
  printf "\033[1;34m[dev]\033[0m %s\n" "$*"
}

warn() {
  printf "\033[1;33m[dev]\033[0m %s\n" "$*"
}

die() {
  printf "\033[1;31m[dev]\033[0m %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

cleanup() {
  info "正在停止前端/API 开发进程..."
  if [[ -n "${UI_PID:-}" ]] && kill -0 "$UI_PID" >/dev/null 2>&1; then
    kill "$UI_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${API_PID:-}" ]] && kill -0 "$API_PID" >/dev/null 2>&1; then
    kill "$API_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

start_redis() {
  if docker ps --format '{{.Names}}' | grep -qx 'faber-redis'; then
    info "Redis 已运行"
    return
  fi

  if docker ps -a --format '{{.Names}}' | grep -qx 'faber-redis'; then
    info "启动已有 Redis 容器"
    docker start faber-redis >/dev/null
    return
  fi

  info "创建并启动 Redis 容器"
  docker run -d \
    --name faber-redis \
    -p 6379:6379 \
    --restart unless-stopped \
    redis:7-alpine >/dev/null
}

python_bin() {
  if [[ -x "$API_DIR/.venv/bin/python" ]]; then
    echo "$API_DIR/.venv/bin/python"
  else
    command -v python3
  fi
}

ensure_api_env() {
  if [[ ! -f "$API_DIR/.env" && -f "$API_DIR/.env.example" ]]; then
    warn "api/.env 不存在，已从 api/.env.example 复制一份"
    cp "$API_DIR/.env.example" "$API_DIR/.env"
  fi
}

install_api_deps_if_needed() {
  if [[ -x "$API_DIR/.venv/bin/python" ]]; then
    return
  fi

  warn "api/.venv 不存在，正在创建并安装依赖"
  need_cmd python3
  python3 -m venv "$API_DIR/.venv"

  if command -v uv >/dev/null 2>&1; then
    (cd "$API_DIR" && uv pip install -e .)
  else
    "$API_DIR/.venv/bin/python" -m pip install -U pip
    "$API_DIR/.venv/bin/python" -m pip install -e "$API_DIR"
  fi
}

install_ui_deps_if_needed() {
  if [[ -d "$UI_DIR/node_modules" ]]; then
    return
  fi

  warn "ui/node_modules 不存在，正在执行 npm install"
  (cd "$UI_DIR" && npm install)
}

need_cmd docker
need_cmd npm

ensure_api_env

info "启动 Postgres"
(cd "$API_DIR" && docker compose up -d postgres)

start_redis

info "启动 Sandbox"
(cd "$SANDBOX_DIR" && docker compose up -d --build)

install_api_deps_if_needed
install_ui_deps_if_needed

PYTHON_BIN="$(python_bin)"

info "执行数据库迁移"
(cd "$API_DIR" && "$PYTHON_BIN" -m alembic upgrade head)

info "启动 API: http://localhost:8000"
(
  cd "$API_DIR"
  "$PYTHON_BIN" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
) >"$LOG_DIR/api.log" 2>&1 &
API_PID=$!

info "启动 UI: http://localhost:3000"
(
  cd "$UI_DIR"
  npm run dev
) >"$LOG_DIR/ui.log" 2>&1 &
UI_PID=$!

info "日志文件:"
info "  API: $LOG_DIR/api.log"
info "  UI : $LOG_DIR/ui.log"
info "按 Ctrl+C 停止前端和 API。Postgres/Redis/Sandbox 容器会保持运行。"

wait "$API_PID" "$UI_PID"
