# Git 提交推送工作流

## 触发时机

当用户说出以下关键词时，**立即执行提交推送**：

- `提交`
- `推送`
- `提交并推送`
- `保存代码`
- `git save`
- `git push`

---

## 仓库信息

| 字段 | 值 |
|------|-----|
| 远程仓库 | https://github.com/CS-LX/HaiRiver-Rush.git |
| 主分支 | `main` |
| 用户名 | Maker |
| 邮箱 | maker@example.com |

---

## 执行步骤

### 第一次使用（检查是否需要初始化）

```bash
# 检查 .git 是否存在
ls /workspace/.git 2>&1
```

如果不存在，先初始化：

```bash
cd /workspace
git init
git config user.name "Maker"
git config user.email "maker@example.com"
git config --local http.proxy http://127.0.0.1:1080
git config --local https.proxy http://127.0.0.1:1080
git remote add origin "https://<TOKEN>@github.com/CS-LX/HaiRiver-Rush.git"
git branch -M main
```

> **注意**：`<TOKEN>` 需要用户提供 GitHub Personal Access Token（格式：`ghp_xxxx`）。

### 日常提交推送

每次用户触发关键词时，执行：

```bash
cd /workspace
git add -A
git commit -m "<提交信息>"
git push origin main 2>&1
```

---

## 提交信息规范

根据操作时机选择合适的前缀：

| 时机 | 前缀 | 示例 |
|------|------|------|
| 新功能完成 | `feat:` | `feat: 新增障碍物碰撞检测` |
| BUG 修复 | `fix:` | `fix: 修复船只穿地面问题` |
| 开发前备份 | `backup:` | `backup: 开发新功能前备份` |
| 代码优化 | `refactor:` | `refactor: 优化水面渲染性能` |
| 文档更新 | `docs:` | `docs: 更新 README` |
| 项目初始化 | `init:` | `init: 项目初始化` |

如果用户没有指定提交信息，默认使用：`feat: 更新代码`

---

## 注意事项

1. **沙箱环境必须配置代理**：`http://127.0.0.1:1080`，否则无法连接 GitHub。
2. **Token 嵌入 URL**：格式为 `https://<TOKEN>@github.com/...`，避免交互式输入。
3. **不提交引擎内部目录**：`.gitignore` 已排除 `engine-docs/`、`examples/`、`urhox-libs/` 等引擎目录。
4. **只提交用户代码**：主要是 `scripts/`、`assets/`、`.project/`、`docs/` 目录。

---

## 快速脚本

```bash
# 一键提交推送（替换 <提交信息>）
cd /workspace && git add -A && git commit -m "<提交信息>" && git push origin main 2>&1
```
