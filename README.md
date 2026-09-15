# ordinary dsh launcher  v0.2.0914

双击 **`ordinary-dsh-launcher.cmd`** 即可启动 DeepSeek Harness Web UI。

一个菜单驱动的启动器，把「启动 dsh」这件事从记命令行参数变成按键选择，并附带版本查询、环境自检和进程管理。

---

## 快速开始

1. 双击 `ordinary-dsh-launcher.cmd`
2. 选 `[1]` 启动 Web UI
3. 浏览器会自动打开；关闭启动器窗口不影响 GUI

> 首次启动会初始化 profile，可能稍慢。启动时会显示进度条与实时耗时。
> 想从浏览器以外的地方访问，用 `[9]` 查看带 token 的完整地址。

---

## 必需文件

```
ordinary-dsh-launcher\                ← 整个文件夹可以整体拷走
├─ ordinary-dsh-launcher.cmd          双击入口（必需）
├─ ordinary-dsh-launcher.ps1          全部逻辑（必需）
├─ README.md                          本说明（可选）
└─ .dsh-launcher\                     运行时自动生成的数据目录（非必需，可删）
   ├─ .gitignore                      自动生成，防止凭据被误提交
   ├─ state.json                      当前 GUI 状态（含访问地址，供 [9] 使用）
   └─ logs\                           每次启动的 stdout / stderr 日志
      ├─ web-<时间戳>.out.log         dsh web 的 stdout（[6]→[5] 看的就是它）
      └─ web-<时间戳>.err.log         dsh web 的 stderr（通常 0 字节）
```

| 文件 | 是否必需 | 缺了会怎样 |
|---|---|---|
| `ordinary-dsh-launcher.cmd` | ✅ 必需 | 没有它就只能用 PowerShell 手动跑 `.ps1`，不能双击启动 |
| `ordinary-dsh-launcher.ps1` | ✅ 必需 | `.cmd` 会报 `No .ps1 script found next to this launcher` 并退出 |

- 两个必需文件**必须放在同一个文件夹里**，只复制其中一个不行。

> 其余文件、`.dsh-launcher\` 数据目录里每个文件的用途，以及能否搬走 / 改名 / 分享，
> 见 [docs/data-and-files.md](docs/data-and-files.md)。

---

## 菜单说明

| 选项 | 作用 |
|---|---|
| `[1]` 启动 Web UI（默认，自动打开浏览器） | 用默认端口 3080 启动，自动开浏览器 |
| `[2]` 启动 Web UI（不自动打开浏览器） | 启动后询问是否用浏览器打开 |
| `[3]` 自定义参数启动 | 手动指定工作目录与任意 `dsh web` 参数 |
| `[4]` 查看当前安装版本 | dsh 入口、版本、`DSH_HOME`、可用 profile |
| `[5]` 查看最新可用版本 | 查询 npm registry（带 30 秒超时） |
| `[6]` 环境自检与进程管理 | 见下 |
| `[7]` 打开工作目录 | 在资源管理器中打开当前工作目录 |
| `[8]` 打开官方文档 | GitHub 仓库 / 快速开始 / npm 页面 |
| `[9]` 查看访问地址与 Token | **唯一**显示完整访问地址的地方，可按需复制 |
| `[0]` 退出启动器 | GUI 会继续在后台运行 |

[6] 子菜单逐项说明 → [docs/usage.md](docs/usage.md)

---

## 命令行用法（可选）

```cmd
ordinary-dsh-launcher.cmd -SelfTest            :: 只跑环境自检，不进菜单
ordinary-dsh-launcher.cmd -Action 9            :: 直接执行菜单项 [9] 后退出
ordinary-dsh-launcher.cmd -Workspace D:\proj   :: 覆盖本次工作目录
```

`-Action` 便于给常用操作单独建桌面快捷方式。

---

## 依赖

| 依赖 | 说明 |
|---|---|
| Windows PowerShell 5.1 | 系统自带；有 PowerShell 7 会自动优先使用 |
| Node.js | dsh 的运行前提 |
| `@deepseek-ai/dsh` | 本机已装或用 npx 自动拉取 |

已验证环境：Windows 11 + Windows PowerShell 5.1 + Node v24.20.0。

---

## 安全摘要

- `[9]` 里的完整地址等同于登录凭据：不要截图、不要发聊天记录、不要提交进仓库。
- 启动器默认全部脱敏，只在 `[9]` 里按需展示；**不会**自动写剪贴板。
- 每次重启 GUI 都会换新 token，旧地址立即失效。
- 分享启动器给别人之前，先删掉 `.dsh-launcher\`。
- 完整说明 → [docs/security.md](docs/security.md)

---

## 文档

| 文件 | 内容 |
|---|---|
| [docs/usage.md](docs/usage.md) | `[6]` 子菜单逐项说明、环境自检项目、可配置项 |
| [docs/data-and-files.md](docs/data-and-files.md) | 必需文件、可移植性 / 改名 / 分享、`.dsh-launcher\` 数据目录详解 |
| [docs/security.md](docs/security.md) | token 是什么、启动器怎么处理它、残留风险与建议 |
| [docs/design.md](docs/design.md) | 性能设计取舍与各菜单项的耗时显示 |
| [docs/faq.md](docs/faq.md) | 常见问题（乱码、端口占用、`EPERM`、日志噪声等） |
