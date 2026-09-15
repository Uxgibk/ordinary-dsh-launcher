# 常见问题

## 中文显示成乱码，或者 `.cmd` 里冒出一堆 `'xxx' is not recognized`？
两个文件的编码要求**不一样**，存错就会出这两种症状：

| 文件 | 必须保存为 | 存错的后果 |
|---|---|---|
| `ordinary-dsh-launcher.ps1` | **UTF-8 with BOM** | 丢了 BOM，PowerShell 5.1 会按 ANSI 解析 → 中文乱码 + 语法错误 |
| `ordinary-dsh-launcher.cmd` | **UTF-8 without BOM + CRLF 换行** | 加了 BOM 会破坏 `@echo off`；改成 LF 换行、或把中文说明挪出「被 `goto` 跳过」的位置，cmd 解析多字节文本时会**失步**，开始把注释碎片当命令执行（实测每次运行冒出 8~18 行 `'...' is not recognized`） |

`.cmd` 顶部那句 `goto :launcher` 是**故意写的**：中文说明整块放在它后面，cmd 直接跳过去、永不解析那些行 ——
所以既能用记事本打开就看到，又不会干扰批处理解析。整理这个文件时**不要删掉那个 `goto`，
也不要把说明块挪到 `goto` 前面**（试过：UTF-8 长注释块放在解析路径里必炸，GBK 也一样）。

## 修改脚本后语法报错？
不要用「读入 → 正则替换 → 写回」的方式改这个文件：替换串里的 `$_` 会被 .NET
当成「整个匹配」的反向引用，把匹配文本又插回去，导致文件膨胀一倍。
请整体重写并重新保存为 UTF-8 with BOM。
（注意：BOM 很容易在编辑过程中被丢掉，改完请确认文件头仍是 `EF BB BF`。）

## 双击 `.cmd` 提示 `No .ps1 script found next to this launcher`？
说明 `.ps1` 不在 `.cmd` 旁边（或被移到了子目录）。把两个必需文件放回同一个文件夹即可。

## 退出启动器后想关掉 GUI？
重新打开启动器 → `[5]` → `[4]`。菜单顶部会显示当前 GUI 的 PID 和端口（token 已脱敏）。
停止后该次日志里的 token 会被自动清洗。
注意要用**当初启动它的那个启动器**（见[一份启动器 = 一份数据目录](data-and-files.md#一份启动器--一份数据目录)）。

## 端口 3080 被占用？
启动器会提示占用进程，并可选择停止它、改用空闲端口，或直接打开已在运行的实例。

## 把启动器复制给别人后，他那里提示端口被占用 / 打不开？
每个 dsh 实例的 token 与状态都在各自的 `.dsh-launcher\` 里，互不影响；
端口被占用时用 `[5]` → `[4]` 停掉旧实例，或让启动器自动换一个空闲端口。

## 启动失败提示 `EPERM ... profiles`？
`DSH_HOME\profiles` 不可写。用 `[5]` → `[1]` 自检确认，然后放宽该目录权限
（受限账户、沙箱环境、杀软拦截都可能造成）。

## `[5]` → `[2]` 报 `The variable '$Script:NpmPackage' cannot be retrieved ...`？
这不是网络问题，是 npm 的 PowerShell 垫片在搞鬼。PowerShell 5.1 会把裸 `npx` 解析成
`npx.ps1`（而不是同目录的 `npx.cmd`），而该垫片内部是 `Set-StrictMode -Version Latest`
加上「把调用行的源码原文 `Invoke-Expression` 重放到自己的作用域」——启动器写在参数里的
变量（`$Script:NpmPackage`、`$pkg` …）在垫片作用域里并不存在，于是直接抛错。
启动器现在只调用 `.cmd` / `.exe`（见 `ordinary-dsh-launcher.ps1` 里的 `Resolve-NpmExe` /
`Invoke-NpmTool`）。自己写脚本时同理：别用裸 `npx` / `npm`，用 `npx.cmd`；也别让全局
`$ErrorActionPreference = 'Stop'` 撞上 `2>&1`——npm 的进度与警告都走 stderr，
在 5.1 下会被升级成 terminating error，让成功的命令被误判成失败。

## `[4]` 查询最新版本失败？
网络不可达或代理拦截会走失败分支并提示手动命令。这不影响启动，已安装版本照常可用。

## 为什么错误信息里没有退出码？
PowerShell 5.1 的 `Start-Process -PassThru` 返回对象未关联进程句柄，
实测 `ExitCode` / `Refresh()` / `WaitForExit()` 三种方式都读不到。
启动器改为从 stderr 内容推断失败原因，比退出码更具体。

## `[5]` → `[5]` 里出现看不懂的重复行（例如 `SharedMemory read faild`）？
**不是启动器打印的，也不是 dsh 打印的**，是第三方程序借道落进来的噪声。以实测的一例说明：
`SharedMemory read faild`（注意它把 failed 拼错了）是**移动云盘 mCloud 的 Shell 扩展**
`mcloud_shell_ext_x64.dll` 里**硬编码的字符串** —— 同一段里紧挨着 `cornerMarkLog`、
`CommunicationSocket::setupUI` 和源码路径 `d:\work\cmic\830\pc_...`；
mCloud 自己的 `log\cornerMark\*.log` 也在同一秒记录了大量同样的行。

它为什么能跑进 GUI 日志：`web-*.out.log` 是 `dsh web` 的 **stdout** 重定向文件，
而 `dsh web` 会把一些子步骤（打开浏览器、打开文件管理器等）交给**继承自己 stdout** 的子进程
—— 见 `@deepseek-ai/dsh-web-app/lib/index.js` 里的 `stdio: ['ignore', 'inherit', 'pipe']`。
只要某个进程拿到了这个文件句柄，它写什么都会落进这份日志；而那个进程一旦加载了这种
「进程一附加就打印」的第三方 Shell 扩展（实测 `mcloud_shell_ext_x64.dll` 就挂在 `explorer.exe` 里），
日志里就会冒出它的输出。

怎么判别是这类噪声：

- 只出现在 `web-*.out.log`（stdout），而 `web-*.err.log` 仍然是 **0 字节**；
- 这句话在 dsh 安装目录、`.dsh` profile、已装插件里**搜不到**，但在某个**第三方软件目录**里能搜到；
- GUI 本身一切正常（`[5]` → `[3]` 进程活着、地址可用）。

处理办法：当噪声忽略，或 `[5]` → `[6]` 清掉。想从源头减少，就在那个第三方客户端里
关掉它的「资源管理器扩展 / 同步角标」之类的开关。
