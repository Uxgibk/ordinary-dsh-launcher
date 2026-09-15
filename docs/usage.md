# 使用详解

本页收录 `[6]` 子菜单的逐项说明、环境自检项目与可配置项。

---

## `[6]` 子菜单

| 选项 | 作用 |
|---|---|
| `[1]` 运行环境自检 | 10 项检查，见[环境自检项目](#环境自检项目) |
| `[2]` 修复 / 重新安装 dsh | 先 `npx -y @deepseek-ai/dsh@latest` 刷新缓存副本，再可选 `npm install -g` 全局重装（本地入口被删/损坏时的真正修复手段），最后用入口实跑 `--version` 如实报告结果 |
| `[3]` 查看运行中的 GUI | PID、端口、运行时长、内存、日志路径、相关 node 进程 |
| `[4]` 停止运行中的 GUI | 先温和结束，再强制结束进程树；随后清洗该次日志的 token |
| `[5]` 查看 GUI 日志 | **只读**，不改动任何文件：取 `state.json` 里的 `outLog`（没有运行中的实例时退而取 `logs\` 中最新的 `*.out.log`）。显示顺序：**文件大小 / 行数 / 时间 + 内容构成统计**（值得看的行 vs 第三方噪声各占多少，并报告同批 `.err.log` 是否非空）→ **「值得看的行」带行号单独列出**（最多 20 行）→ **折叠掉连续重复的尾部**。随后还可选 `[1]` 原始尾部 40 行 / `[2]` 文件开头 20 行 / `[3]` 搜索关键词。全程 token 打码 |
| `[6]` 清理日志文件 | 界面上会**先按类型统计、再把每个实际文件名逐个列出来**（超过 20 个只列前 20 个并注明），并写明不会删什么，然后才问 `y/N`。删除范围 = `.dsh-launcher\logs\` 下**所有 `*.log`**（`web-*.out/err.log`、`gui-restart-*.log`、`gui-restart-*.launcher-*.out/err.log`）。**不动** `state.json`、`.gitignore`、`*.preflight.txt` 以及 `logs\` 之外的任何文件。运行中实例正持有的那两个文件会单独点名，通常删不掉——此时其余照删，并逐个报告结果，不会整批中断 |

> `[5]` 与 `[6]` 到底碰哪些文件，`ordinary-dsh-launcher.ps1` 里
> `Show-GuiLog` / `Clear-Logs` 两个函数的注释头部有逐文件的说明。

---

## 环境自检项目

自检会提前发现导致启动失败的原因，而不是等启动炸掉：

1. PowerShell 版本与 LanguageMode
2. Node.js 是否可用
3. dsh 入口解析结果（本地 / npx 回退）
4. `DSH_HOME` 是否存在**且可写**（dsh 启动要重写 profile 配置，不可写必失败）
5. `web` profile 是否完整
6. 前端资源 `dsh-web-frontend/dist` 是否已构建
7. 默认端口占用情况（能报出占用进程名与 PID）
8. 是否有由本启动器启动的 GUI 在运行
9. API 凭据 `.credentials.yaml` 是否存在
10. 日志里是否残留明文 token（只扫**本启动器自己**的 `logs\`）

---

## 配置

### 启动器身份（名字 / 版本 / 副标题）

在 `ordinary-dsh-launcher.ps1` **最上方**（`param` 块之后）改这三行，横幅与窗口标题都会跟着变，
`.cmd` 和本文档不需要跟着改：

```powershell
$Script:LauncherName    = 'ordinary dsh launcher'        # 横幅第一行的名字
$Script:LauncherVersion = '0.2.0914'                     # 横幅第一行的版本号
$Script:LauncherTagline = 'DeepSeek Harness 快速启动器'   # 横幅第二行的副标题
```

### 其他配置

继续往下是同一文件的「配置区」：

```powershell
$Script:DefaultWorkspace = $Script:LauncherDir   # 默认工作目录 = 启动器所在文件夹
$Script:DefaultPort      = 3080                  # 默认端口
$Script:UrlWaitSeconds   = 90                    # 等待就绪的超时
$Script:ProgressFullSecs = 20                    # 进度条填满所需秒数
```

> **工作目录很重要**：dsh 把「运行命令时所在的目录」当作 workspace 根目录，也就是 agent 默认操作的项目目录。
> 默认就是启动器自己所在的文件夹（自包含、拷走即用）；想固定指向别的项目，改上面 `DefaultWorkspace` 一行，
> 或者用 `[3]` 自定义参数启动临时指定。`-Workspace` 开关可以覆盖本次运行。
