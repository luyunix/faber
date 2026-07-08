# Faber Workspace

Faber 是一个类 Manus 的 AI Agent 工作台。这个根目录是本地开发编排层，下面的三个子项目各自保持独立 Git 仓库，根仓库只负责说明、启动脚本和协作入口。

## 子项目

| 路径 | 作用 | 默认端口 |
| --- | --- | --- |
| `api/` | FastAPI 后端。负责用户登录注册、会话管理、Agent 调度、配置管理、文件存储、SSE 流式事件和 VNC WebSocket 代理。 | `8000` |
| `ui/` | Next.js 前端。负责登录注册、会话列表、任务详情、工具调用可视化、设置面板、文件预览和远程桌面入口。 | `3000` |
| `sandbox/` | 隔离执行沙箱。提供文件读写、Shell 执行、Chromium 浏览器、CDP、VNC/noVNC 等 Agent 工具运行环境。 | `8080`, `9222`, `5900`, `5901` |

## 依赖

本地开发建议准备：

- Docker Desktop
- Python 3.12+
- Node.js 22+
- npm
- `uv`（推荐，用于 Python 依赖管理）

## 一键启动

```bash
./scripts/dev.sh
```

脚本会按顺序处理：

1. 启动 Postgres/pgvector：`api/docker-compose.yml`
2. 启动 Redis：使用 `redis:7-alpine` 容器映射到本地 `6379`
3. 启动固定沙箱：`sandbox/docker-compose.yml`
4. 执行 API 数据库迁移：`alembic upgrade head`
5. 启动 API：`http://localhost:8000`
6. 启动 UI：`http://localhost:3000`

启动后直接访问：

```text
http://localhost:3000
```

API 文档：

```text
http://localhost:8000/docs
```

## 手动启动

### 1. 基础服务

```bash
cd api
docker compose up -d postgres

docker run -d \
  --name faber-redis \
  -p 6379:6379 \
  --restart unless-stopped \
  redis:7-alpine
```

### 2. 沙箱

```bash
cd sandbox
docker compose up -d --build
```

### 3. 后端

```bash
cd api
source .venv/bin/activate
alembic upgrade head
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### 4. 前端

```bash
cd ui
npm install
npm run dev
```

## 常用排查

- `api/.env` 中数据库默认使用 `localhost:5432`，Redis 默认使用 `localhost:6379`。
- 如果沙箱使用固定容器，`api/.env` 中 `SANDBOX_ADDRESS` 应指向 `localhost:8080` 或对应容器地址。
- 如果 `5432`、`6379`、`8080`、`3000` 端口被占用，先停掉占用进程或调整对应配置。
- 根仓库不会提交 `api/`、`ui/`、`sandbox/` 内部代码；这三个目录分别在自己的仓库中提交。
