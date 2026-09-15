# Technology Profiles

本项目是 Flutter/Dart 原生 Android 应用。

## Applicability Rules

1. 检查 `pubspec.yaml`、源码、构建配置确认技术栈
2. 每个 profile 标记：适用 / 不适用 / 待验证
3. 替换候选命令为仓库中验证过的精确版本
4. 产品历史、模块名、项目特定架构不放入可复用 profile

## Profiles

### ✅ 适用

- [Flutter / Dart](./flutter-dart.md) — 主要技术栈

### ❌ 不适用

| Profile | 原因 |
|---------|------|
| [Python](./python.md) | 本项目无 Python 代码（脚本仅 PowerShell） |
| [TypeScript](./typescript.md) | 本项目无 TypeScript 代码 |
| [Node.js](./nodejs.md) | 本项目无 Node.js 代码 |
| [MCP](./mcp.md) | 本项目不使用 MCP 协议 |
| [Prisma](./prisma.md) | 本项目无数据库 ORM |

> 以上 profile 保留作为通用基线模板，不在本项目中应用。
