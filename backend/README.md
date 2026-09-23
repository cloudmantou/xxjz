# 无忧书 后端服务（wuyoushu-config-server）

无忧书的后端配置与规则热更新服务，基于 Node.js + Express 构建。负责向 iOS 客户端下发关键词匹配规则和应用配置，支持在不发版的情况下更新自动记账分类规则。

---

## 目录

- [功能概述](#功能概述)
- [快速开始](#快速开始)
  - [PostgreSQL（推荐）](#postgresql推荐)
  - [MySQL](#mysql)
- [环境变量](#环境变量)
- [数据库命令](#数据库命令)
- [API 文档](#api-文档)
  - [公开接口](#公开接口)
  - [Admin 接口](#admin-接口)
- [鉴权说明](#鉴权说明)
- [请求头说明（客户端）](#请求头说明客户端)
- [规则响应格式](#规则响应格式)

---

## 功能概述

1. **规则版本管理**：发布、查看、回滚关键词匹配规则，支持全量发布和增量（patch）发布
2. **紧急屏蔽**：快速屏蔽某条规则，无需发布新版本
3. **配置热更新**：下发 OCR 正则、分类关键词等配置，客户端通过版本号做差量拉取
4. **增量更新优化**：客户端携带当前版本号，服务端返回 `304 Not Modified` 或差量数据，节省流量

---

## 快速开始

### PostgreSQL（推荐）

```bash
# 1. 复制环境变量文件
cp .env.example .env

# 2. 启动 PostgreSQL（Docker）
docker compose up -d postgres

# 3. 安装依赖
npm install

# 4. 初始化数据库表结构
npm run db:migrate

# 5. 写入初始规则数据
npm run db:seed

# 6. 启动开发服务器
npm run dev
```

服务默认监听 `http://localhost:9090`

### MySQL

```bash
# 1. 在 .env 中设置以下变量：
#    RULES_STORAGE=mysql
#    MYSQL_HOST=127.0.0.1
#    MYSQL_PORT=3306
#    MYSQL_USER=root
#    MYSQL_PASSWORD=secret
#    MYSQL_DATABASE=wuyoushu_rules

# 2. 安装依赖
npm install

# 3. 初始化数据库
npm run db:migrate

# 4. 写入初始数据
npm run db:seed

# 5. 启动服务
npm run dev
```

---

## 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `NODE_ENV` | `development` | 运行环境 |
| `PORT` | `9090` | 服务监听端口 |
| `APP_PUBLIC_BASE_URL` | `https://xx.cloudmantoua.top` | 对外访问域名（用于管理面板展示） |
| `RULES_STORAGE` | `postgres` | 存储后端：`postgres` / `mysql` / `json` / `memory` |
| `DATABASE_URL` | — | PostgreSQL 连接字符串 |
| `MYSQL_HOST` | — | MySQL 主机 |
| `MYSQL_PORT` | `3306` | MySQL 端口 |
| `MYSQL_USER` | — | MySQL 用户名 |
| `MYSQL_PASSWORD` | — | MySQL 密码 |
| `MYSQL_DATABASE` | — | MySQL 数据库名 |
| `ENABLE_ENCRYPTION` | `false` | 是否对配置数据启用 AES 加密 |
| `AES_KEY` | — | AES 加密密钥（16 字节） |
| `AES_IV` | — | AES 初始向量（16 字节） |
| `API_KEY` | — | Admin 接口鉴权密钥 |
| `ADMIN_PANEL_TOKEN` | — | `/admin` 管理面板鉴权密钥（生产环境必填） |
| `USAGE_ANALYTICS_MAX_EVENTS` | `5000` | 管理面板保留的最近请求事件数量上限 |
| `SIGN_SECRET` | — | 签名密钥（备用） |

---

## 数据库命令

```bash
npm run db:migrate          # 执行待执行的迁移
npm run db:migrate:status   # 查看迁移状态
npm run db:seed             # 写入初始规则数据
npm run db:reset            # 重置数据库并重新 seed（⚠️ 会清空所有数据）
```

> `db:seed` 会向数据库发布一条初始全量规则版本，使 `/api/KeyWordMatchingRule/List` 能立即返回有效数据。

---

## API 文档

### 公开接口

#### `GET /health`

健康检查，返回服务状态和当前配置版本。

**响应示例**
```json
{
  "status": "ok",
  "time": "2024-01-01T00:00:00.000Z",
  "configVersion": 5,
  "releaseCount": 12
}
```

---

#### `GET /privacy`

隐私政策页面地址，建议在 App 内或配置热更新中引用此 URL。

---

#### `GET /api/config/get`

获取最新应用配置。客户端携带 `X-Config-Version` 请求头，若版本已是最新则返回空数据。

**请求头**
| 名称 | 说明 |
|------|------|
| `X-Config-Version` | 客户端当前配置版本号 |

**响应示例**
```json
{
  "code": 200,
  "message": "success",
  "data": "{ ... }",
  "version": 5,
  "encrypted": false
}
```

若已是最新版本：
```json
{
  "code": 200,
  "message": "Already up to date",
  "data": "",
  "version": 5,
  "encrypted": false
}
```

---

#### `GET /api/config/version`

仅返回当前配置版本号。

```json
{
  "code": 200,
  "message": "success",
  "data": { "version": 5 }
}
```

---

#### `GET /api/Config/GetV2`

与 `/api/config/get` 功能相同，兼容旧版客户端路径。

---

#### `GET /api/KeyWordMatchingRule/List`

获取最新关键词匹配规则，供客户端自动记账分类使用。支持增量更新。

**请求头**
| 名称 | 说明 |
|------|------|
| `X-Rules-Version` | 客户端当前规则版本号 |
| `X-Rules-Config-Version` / `X-Config-Version` | 客户端当前配置版本 |
| `X-App-Version` | App 版本名称 |
| `X-Build` | App Build 号 |
| `X-Platform` | 平台（默认 `ios`） |
| `X-Channel` | 渠道标识 |
| `X-Cohort-Key` | 分组 Key（灰度发布用） |
| `X-Install-Id` | 安装 ID |
| `If-None-Match` | ETag 缓存协商 |

若内容未变化，返回 `304 Not Modified`。

---

### Admin 接口

> 所有 Admin 接口需在请求头中携带 `Authorization: Bearer <API_KEY>`

---

### Web 管理面板

- 路由：`/admin`
- 功能：查看用户数、24h 活跃、最近请求记录、Top 路由、当前记账参数，并支持：
  - 更新隐私政策 URL
  - 配置“我的”页外链列表（如抖音/小红书/公众号/B站/任意第三方网页）
- 生产环境访问方式（任选其一）：
  - Query：`/admin?token=<ADMIN_PANEL_TOKEN>`
  - Header：`X-Admin-Token: <ADMIN_PANEL_TOKEN>`
  - Bearer：`Authorization: Bearer <ADMIN_PANEL_TOKEN>`

示例：

```text
https://xx.cloudmantoua.top/admin?token=your-admin-token
```

---

#### `GET /api/admin/rules/releases`

获取所有规则版本列表。

```json
{
  "code": 0,
  "message": "success",
  "data": [ ... ]
}
```

---

#### `GET /api/admin/rules/releases/:id`

获取指定 ID 的规则版本详情。

---

#### `POST /api/admin/rules/releases/full`

发布全量规则版本。

**请求体**
```json
{
  "rules": [ ... ],
  "publish": true,
  "note": "更新餐饮分类关键词",
  "rolloutStrategy": null,
  "targetSelector": null
}
```

---

#### `POST /api/admin/rules/releases/patch`

发布增量（patch）规则版本，仅描述变更部分。

**请求体**
```json
{
  "patch": {
    "upsert": [ ... ],
    "deleteRuleIds": [],
    "deleteRuleKeys": [],
    "tombstones": [],
    "priorityAdjustments": [],
    "noiseKeywords": { "add": [], "remove": [] }
  },
  "publish": true,
  "note": "修正误分类规则"
}
```

---

#### `POST /api/admin/rules/releases/:id/publish`

将草稿版本发布为正式版本。

---

#### `POST /api/admin/rules/rollback`

回滚到指定版本。

**请求体**
```json
{
  "releaseId": "uuid-or-id",
  "releaseRef": null,
  "note": "回滚原因"
}
```

---

#### `GET /api/admin/rules/emergency-blocks`

获取当前紧急屏蔽规则列表。

---

#### `POST /api/admin/rules/emergency-blocks`

添加紧急屏蔽规则（立即对客户端生效，无需发布新版本）。

---

#### `DELETE /api/admin/rules/emergency-blocks/:fingerprint`

移除指定紧急屏蔽规则。

---

## 鉴权说明

Admin 接口使用 API Key 鉴权，通过以下任意方式传递：

```
Authorization: Bearer <API_KEY>
```

或

```
X-Api-Key: <API_KEY>
```

`API_KEY` 在 `.env` 文件中配置。

---

## 规则响应格式

客户端规则 API 响应支持两种格式，通过查询参数 `?format=legacy` 或请求头 `X-Response-Format: legacy` 切换到旧版格式；默认为标准格式。
