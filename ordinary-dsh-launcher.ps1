<#
================================================================================
 ordinary dsh launcher
================================================================================
 启动器身份（名字 / 版本 / 副标题）定义在本文件最上方的
 「启动器身份（改这里就够了）」三行常量里。

 双击 ordinary-dsh-launcher.cmd 运行。菜单驱动，覆盖启动 / 版本 / 自检 / 进程管理。

 文件与可移植性（详见 docs/data-and-files.md）
   - 必需文件：ordinary-dsh-launcher.cmd（双击入口）+ ordinary-dsh-launcher.ps1
     （全部逻辑）。两者必须放在同一个文件夹里。
   - 可整体移动到任意路径：所有路径都以本文件所在目录为基准解析，
     没有硬编码绝对路径。
   - 两个文件都可以改名：.cmd 先找同名 .ps1，再退回「同目录下唯一的 .ps1」。
   - .dsh-launcher\ 是运行时自动生成的数据目录，不是必需文件，可随时删除；
     它会跟着启动器文件夹一起搬迁。首次运行由 Initialize-DataDir 建出
     .dsh-launcher\ + logs\ + .gitignore，此后每启动一次 GUI 就新增一对带
     时间戳的日志（只增不减，除非用 [5][6] 清理）。
     一定会出现：
       .gitignore                        内容 * 与 !.gitignore，防凭据被误提交
       state.json                        启动成功后写；[5][3]/[4] 与 [8] 的数据来源
       logs\web-<stamp>.out.log          dsh web 的 stdout（[5][5] 读的就是它）
       logs\web-<stamp>.err.log          dsh web 的 stderr（正常 0 字节）
     可能出现（不是本脚本生成的，脚本内无任何引用，删掉无影响）：
       logs\gui-restart-*.log            外部 GUI 重启助手的日志
       logs\gui-restart-*.launcher-*.out/err.log  同上，重定向的启动器输出
       logs\gui-restart-*.preflight.txt  同上，重启前的环境快照
       restart-gui.ps1 / restart-stdin.txt / *.bak  该助手脚本与手工留档

  菜单项与文件的对应（[5] 子菜单，详见 Show-GuiLog / Clear-Logs 的注释）
   - [5] → [5] 查看 GUI 日志：只读，不改动任何文件。读 state.json 的 outLog；没有存活实例
     或该文件已被删，则退回 logs\ 下最后写入的 *.out.log。显示顺序是：文件大小/行数/
     时间 + 内容构成统计 → 「值得看的行」（带行号）→ 折叠掉连续重复的尾部，
     另给 [1] 原始尾部 / [2] 文件开头 / [3] 搜索关键词 三个入口。全程打码 token。
   - [5] → [6] 清理日志文件：删 logs\ 下所有 *.log（web-*、gui-restart-*、
     gui-restart-*.launcher-*）；不删 state.json、.gitignore、logs\*.preflight.txt，
     以及 logs\ 之外的任何文件。

 安全约定（重要）
   - token 等同于登录凭据：默认界面一律掩码显示，只在 [8] 里按需展示。
   - 不自动写剪贴板；复制动作必须由用户在 [8] 里显式选择。
   - 启动成功后清洗日志里的 token；展示日志时再打码一次。
   - .dsh-launcher\ 自动写入 .gitignore，避免状态/日志被误提交。

 性能约定
   - 端口探测以 netstat 全表为主并缓存数秒；绝不逐端口调用
     Get-NetTCPConnection（实测本机每次失败要 ~840ms）。
   - dsh 入口解析走「命中即返回」快路径并缓存结果，
     避免无谓的 npm root -g（实测 ~970ms）。

 兼容性
   - 目标为 Windows PowerShell 5.1（不使用 ?? / 三元运算符）。
   - 本文件必须保存为 UTF-8 with BOM，否则 5.1 会把中文读成乱码。
   - 改动请整体重写并重存为 UTF-8 with BOM。不要用「读入 → 正则替换 → 写回」：
     替换串里的 $_ 会被 .NET 当成「整个匹配」的反向引用，导致文件膨胀。

 命令行开关（可选）
   -SelfTest          只跑环境自检并输出结果，不进菜单
   -Action 1          直接执行某个菜单项后退出（便于做桌面快捷方式）
   -Workspace <path>  覆盖默认工作目录
================================================================================
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$Action,
    [string]$Workspace
)

# ═══════════════════════════ 启动器身份（改这里就够了）═══════════════════════════
# 下面三行是启动器的唯一身份来源：横幅、窗口标题都用它们。
# 改名字 / 升版本 / 换副标题，只改这三行，其他文件无需改动。
$Script:LauncherName    = 'ordinary dsh launcher'
$Script:LauncherVersion = '0.3.2'
$Script:LauncherTagline = 'DeepSeek Harness 快速启动器'

$ErrorActionPreference = 'Stop'

# 窗口标题也用同一份身份，避免在 .cmd 里再写一遍名字和版本
try { $Host.UI.RawUI.WindowTitle = "$($Script:LauncherName) v$($Script:LauncherVersion)" } catch { }

# 中文输出：控制台按 UTF-8 处理（.cmd 入口已 chcp 65001）
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ─────────────────────────────── 配置区（可按需修改）───────────────────────────────

# 启动器身份（名字 / 版本 / 副标题）见本文件最上方的「启动器身份」三行常量。

$Script:LauncherDir      = $PSScriptRoot
if (-not $Script:LauncherDir) { $Script:LauncherDir = (Get-Location).Path }

# 默认工作目录：dsh 以「运行命令时所在的目录」作为 workspace 根目录。
# 启动器是自包含的：默认就把「启动器自己所在的文件夹」当作 workspace，
# 这样把整个文件夹拷给别人，对方双击即可开工，无需改配置。
$Script:DefaultWorkspace = $Script:LauncherDir

$Script:DefaultPort      = 3080          # dsh web-app 的内置默认端口
$Script:NpmPackage       = '@deepseek-ai/dsh'
# 官方入口集合：菜单 [7] 直接遍历这个数组渲染，增删链接只改这里。
# 顺序即显示顺序，索引从 1 开始（0 保留给「返回」）。
$Script:OfficialLinks    = @(
    [pscustomobject]@{ Title = '官方产品页';          Url = 'https://www.deepseek.com/harness' }
    [pscustomobject]@{ Title = 'GitHub 主仓库';       Url = 'https://github.com/deepseek-ai/deepseek-harness' }
    [pscustomobject]@{ Title = '官方社区插件 Topic';  Url = 'https://github.com/topics/dsh-plugin' }
    [pscustomobject]@{ Title = '官方文档';            Url = 'https://deepseek-harness.github.io/deepseek-harness/' }
)

$Script:DataDir          = Join-Path $Script:LauncherDir '.dsh-launcher'
$Script:LogDir           = Join-Path $Script:DataDir 'logs'
$Script:StateFile        = Join-Path $Script:DataDir 'state.json'
$Script:UrlWaitSeconds   = 90            # 等待 `dsh web:` URL 出现的最长秒数
$Script:ProgressFullSecs = 20            # 进度条按此秒数填满（视觉估计，不是剩余时间承诺）

if ($Workspace) { $Script:DefaultWorkspace = $Workspace }

# dsh 家目录
$Script:DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }

# 进程内缓存
$Script:DshCache      = $null
$Script:NpmCmdCache   = @{}
$Script:ListenerMap   = $null
$Script:ListenerMapAt = [datetime]::MinValue

# ─────────────────────────────── 输出辅助 ───────────────────────────────

function Get-DisplayWidth {
    <# 估算字符串在控制台上的显示列宽：CJK / 全角字符按 2 列计 #>
    param([string]$Text)
    if (-not $Text) { return 0 }
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        $c = [int]$ch
        if (($c -ge 0x1100 -and $c -le 0x115F) -or
            ($c -ge 0x2E80 -and $c -le 0xA4CF) -or
            ($c -ge 0xAC00 -and $c -le 0xD7A3) -or
            ($c -ge 0xF900 -and $c -le 0xFAFF) -or
            ($c -ge 0xFE30 -and $c -le 0xFE6F) -or
            ($c -ge 0xFF00 -and $c -le 0xFF60) -or
            ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { $w += 2 } else { $w += 1 }
    }
    return $w
}

function Format-BannerLine {
    <# 把一行文字居中放进横幅内框（按显示列宽而非字符数对齐） #>
    param([string]$Text, [int]$Width = 58)
    $pad = $Width - (Get-DisplayWidth -Text $Text)
    if ($pad -lt 0) { $pad = 0 }
    $left  = [Math]::Floor($pad / 2)
    $right = $pad - $left
    return '  ║' + (' ' * $left) + $Text + (' ' * $right) + '║'
}

function Write-Banner {
    Write-Host ''
    Write-Host '  ╔══════════════════════════════════════════════════════════╗' -ForegroundColor DarkCyan
    Write-Host (Format-BannerLine "$($Script:LauncherName)   v$($Script:LauncherVersion)") -ForegroundColor Cyan
    Write-Host (Format-BannerLine $Script:LauncherTagline) -ForegroundColor DarkCyan
    Write-Host '  ╚══════════════════════════════════════════════════════════╝' -ForegroundColor DarkCyan
}

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host "  ── $Text " -ForegroundColor DarkCyan -NoNewline
    Write-Host ('─' * [Math]::Max(1, 56 - $Text.Length)) -ForegroundColor DarkCyan
}

function Write-Ok    { param([string]$T) Write-Host "  [ OK ] " -ForegroundColor Green    -NoNewline; Write-Host $T }
function Write-Bad   { param([string]$T) Write-Host "  [FAIL] " -ForegroundColor Red      -NoNewline; Write-Host $T }
function Write-Warn2 { param([string]$T) Write-Host "  [WARN] " -ForegroundColor Yellow   -NoNewline; Write-Host $T }
function Write-Info  { param([string]$T) Write-Host "  [INFO] " -ForegroundColor DarkGray -NoNewline; Write-Host $T }
function Write-Hint  { param([string]$T) Write-Host "         $T" -ForegroundColor DarkGray }

# ─────────────────────────────── 耗时显示 ───────────────────────────────
# 约定：「会等」的操作一律计时。用户既能分清「慢」和「卡死」，
#       也能看出时间花在哪一步（联网、进程启动，还是本地 I/O）。
#       不涉及等待的菜单项（看日志、清屏、打开浏览器）不加，避免噪声。

function Format-Duration {
    <# 把秒数格式化成中文时长：毫秒 / 秒 / 分秒 #>
    param([double]$Seconds)
    if ($Seconds -lt 1)  { return ('{0:N0} 毫秒' -f ($Seconds * 1000)) }
    if ($Seconds -lt 60) { return ('{0:N2} 秒' -f $Seconds) }
    $m = [Math]::Floor($Seconds / 60)
    return ('{0:N0} 分 {1:N1} 秒' -f $m, ($Seconds - ($m * 60)))
}

function Write-Elapsed {
    <# 统一耗时输出（暗灰缩进行） #>
    param(
        [Parameter(Mandatory = $true)][double]$Seconds,
        [string]$Label = '耗时'
    )
    Write-Hint ("{0}：{1}" -f $Label, (Format-Duration -Seconds $Seconds))
}

function Pause-Any {
    Write-Host ''
    Write-Host '  按 Enter 返回菜单…' -ForegroundColor DarkGray -NoNewline
    try { [void](Read-Host) } catch { }
}

function Clear-Screen {
    # Clear-Host 在输出被重定向（非交互宿主）时会抛异常，这里静默降级
    try { Clear-Host } catch { }
}

# ─────────────────────────── npm / npx 调用 ───────────────────────────

# 为什么不能直接写 `& npx ...` / `& npm ...`（Windows PowerShell 5.1 实测）
#   npm 会在同一目录同时安装 npx.cmd 与 npx.ps1，而 PowerShell 的命令解析优先
#   选中 npx.ps1（ExternalScript）。npm 的 .ps1 垫片开头是
#   `Set-StrictMode -Version 'Latest'`，随后在「-Command 分支」里把调用方的源码
#   行原文解析出来，再用 Invoke-Expression 在自己的作用域里重放；调用方写在参数
#   里的变量（$Script:NpmPackage、$pkg …）在垫片作用域里并不存在，于是直接抛
#     The variable '$Script:NpmPackage' cannot be retrieved because it has not been set.
#   所以启动器一律显式调用 .cmd / .exe（CommandType Application），绕开 .ps1 垫片。
#
# 第二个坑：全局 $ErrorActionPreference = 'Stop' 下，原生命令写到 stderr 的内容
#   一旦经 2>&1 并入成功流就会变成 ErrorRecord，并被升级为 terminating error
#   （RemoteException）。npm/npx 的下载进度与警告都走 stderr —— 明明成功也会被判成
#   失败。统一走 Invoke-NativeCaptured：只在函数作用域内临时降级 EAP，并如实返回退出码。

function Resolve-NpmExe {
    <# 返回 npm/npx 的 .cmd / .exe 全路径；找不到返回 $null（结果进程内缓存）。 #>
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Script:NpmCmdCache.ContainsKey($Name)) { return $Script:NpmCmdCache[$Name] }

    $hit = $null
    foreach ($cand in @("$Name.cmd", "$Name.exe")) {
        $c = Get-Command $cand -CommandType Application -ErrorAction SilentlyContinue |
             Select-Object -First 1
        if ($c) { $hit = $c.Source; break }
    }
    $Script:NpmCmdCache[$Name] = $hit
    return $hit
}

function Invoke-NativeCaptured {
    <#
      执行原生命令并完整捕获输出（stdout + stderr）。
      返回 [pscustomobject]@{ ExitCode; Output（字符串数组）; Ok }
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # 仅本函数作用域降级，见本节说明
    try {
        $raw  = @(& $FilePath @Arguments 2>&1)
        $code = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $code
            Output   = @($raw | ForEach-Object { "$_" })
            Ok       = ($code -eq 0)
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = -1
            Output   = @($_.Exception.Message)
            Ok       = $false
        }
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

function Invoke-NpmTool {
    <# 运行 npm / npx 并捕获输出（永远避开 .ps1 垫片）。 #>
    param(
        [Parameter(Mandatory = $true)][ValidateSet('npm', 'npx')][string]$Name,
        [string[]]$Arguments = @()
    )

    $exe = Resolve-NpmExe -Name $Name
    if ($exe) { return Invoke-NativeCaptured -FilePath $exe -Arguments $Arguments }

    # 兜底：PATH 上只有 .ps1 垫片时交给 cmd.exe（cmd 按 PATHEXT 会挑 .cmd）
    $comspec = 'cmd.exe'
    if ($env:ComSpec) { $comspec = $env:ComSpec }
    $quoted = @($Arguments | ForEach-Object {
        if ("$_" -match '[\s"]') { '"' + ("$_" -replace '"', '\"') + '"' } else { "$_" }
    })
    $line = "$Name $($quoted -join ' ')".Trim()
    return Invoke-NativeCaptured -FilePath $comspec -Arguments @('/d', '/c', $line)
}

# ─────────────────────────────── 安全辅助 ───────────────────────────────

function Get-TokenFromUrl {
    <# 从访问地址里取出 token；没有则返回 $null #>
    param([string]$Url)
    if (-not $Url) { return $null }
    $m = [regex]::Match($Url, '[?&]token=([^&\s]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-MaskedUrl {
    <# 把地址里的 token 换成掩码，用于任何默认可见的输出 #>
    param([string]$Url)
    if (-not $Url) { return '' }
    $tok = Get-TokenFromUrl -Url $Url
    if (-not $tok) { return $Url }
    return $Url.Replace($tok, '••••••••')
}

function Get-OriginUrl {
    <# 只保留 scheme://host:port，用于「可安全展示」的地址 #>
    param([string]$Url)
    if (-not $Url) { return '' }
    $m = [regex]::Match($Url, '^(https?://[^/?#]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $Url
}

function Protect-LogToken {
    <#
      清洗日志文件里的 token。dsh 启动时会把带 token 的 URL 打进 stdout，
      日志一落盘就等于凭据落盘，这里在拿到地址后立刻抹掉。
    #>
    param([string[]]$Paths)

    $res = [pscustomobject]@{ Cleaned = 0; Locked = 0 }
    foreach ($f in $Paths) {
        if (-not $f -or -not (Test-Path $f)) { continue }
        try {
            $text = Get-Content $f -Raw -Encoding UTF8 -ErrorAction Stop
            if (-not $text) { continue }
            $new = [regex]::Replace($text, '(?<=[?&]token=)[^&\s]+', 'REDACTED')
            if ($new -ne $text) {
                Set-Content -Path $f -Value $new -Encoding UTF8 -NoNewline -ErrorAction Stop
                $res.Cleaned++
            }
        } catch {
            # 正在运行的 dsh 仍持有自己的 stdout 句柄，写入会被拒绝（实测 IOException）
            $res.Locked++
        }
    }
    return $res
}

function Clear-StaleLogTokens {
    <#
      清洗所有「当前没有进程占用」的历史日志。
      正在运行的 dsh 会锁住自己的 stdout 文件，只能等它停止后再洗；
      因此调用点有两个：启动新实例之前、以及停止 GUI 之后。
    #>
    $files = @(Get-ChildItem $Script:LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
               Select-Object -ExpandProperty FullName)
    if ($files.Count -eq 0) { return $null }
    return (Protect-LogToken -Paths $files)
}

# ─────────────────────────────── 环境探测 ───────────────────────────────

function Get-PackageJsonVersion {
    param([string]$PackageDir)
    try {
        $pj = Join-Path $PackageDir 'package.json'
        if (Test-Path $pj) {
            return (Get-Content $pj -Raw -Encoding UTF8 | ConvertFrom-Json).version
        }
    } catch { }
    return $null
}

function Test-DshBinJs {
    <# 校验一个候选 bin.js；有效则返回入口对象，否则 $null #>
    param([string]$Candidate, [string]$NodeExe)
    if (-not $NodeExe) { return $null }
    try {
        $full = [System.IO.Path]::GetFullPath($Candidate)
        if (Test-Path $full) {
            return [pscustomobject]@{
                Mode    = 'node'
                NodeExe = $NodeExe
                BinJs   = $full
                CmdShim = $null
                Source  = $full
                # <root>\node_modules\@deepseek-ai\dsh\lib\bin.js → 上溯两层即包目录
                Version = (Get-PackageJsonVersion (Split-Path (Split-Path $full -Parent) -Parent))
            }
        }
    } catch { }
    return $null
}

function Resolve-Dsh {
    <#
      解析可用的 dsh 入口，结果进程内缓存。
      Mode: 'node' → node + lib/bin.js（首选，进程树干净）
            'cmd'  → dsh.cmd 垫片
            'npx'  → npx -y @deepseek-ai/dsh（兜底）
    #>
    param([switch]$Force)

    if (-not $Force -and $Script:DshCache) { return $Script:DshCache }

    $node    = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    $nodeExe = if ($node) { $node.Source } else { $null }

    # ── 快路径：PATH 上的 dsh 垫片，命中即返回 ──
    foreach ($name in @('dsh.cmd', 'dsh.ps1', 'dsh')) {
        $c = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $c) { continue }
        $dir = Split-Path $c.Source -Parent

        $cands = @()
        # <...>\node_modules\.bin\dsh.cmd → <...>\node_modules\@deepseek-ai\dsh\lib\bin.js
        if ((Split-Path $dir -Leaf) -eq '.bin') {
            $cands += (Join-Path $dir "..\@deepseek-ai\dsh\lib\bin.js")
        }
        $cands += (Join-Path $dir "@deepseek-ai\dsh\lib\bin.js")

        foreach ($cand in $cands) {
            $hit = Test-DshBinJs -Candidate $cand -NodeExe $nodeExe
            if ($hit) { $Script:DshCache = $hit; return $hit }
        }
    }

    # ── 慢路径 1：全局 npm root ──
    $npmRoot = $null
    try {
        $npmRootRes = Invoke-NpmTool -Name npm -Arguments @('root', '-g')
        if ($npmRootRes.Ok -and $npmRootRes.Output.Count -gt 0) {
            $npmRoot = "$($npmRootRes.Output[0])".Trim()
        }
    } catch { }
    if ($npmRoot) {
        $hit = Test-DshBinJs -Candidate (Join-Path $npmRoot "@deepseek-ai\dsh\lib\bin.js") -NodeExe $nodeExe
        if ($hit) { $Script:DshCache = $hit; return $hit }
    }

    # ── 慢路径 2：npx 缓存 ──
    $npxRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
    if (Test-Path $npxRoot) {
        foreach ($d in (Get-ChildItem $npxRoot -Directory -ErrorAction SilentlyContinue)) {
            $hit = Test-DshBinJs -Candidate (Join-Path $d.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js') -NodeExe $nodeExe
            if ($hit) { $Script:DshCache = $hit; return $hit }
        }
    }

    # ── cmd 垫片兜底 ──
    $shim = Get-Command dsh.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($shim) {
        $r = [pscustomobject]@{
            Mode = 'cmd'; NodeExe = $null; BinJs = $null
            CmdShim = $shim.Source; Source = $shim.Source; Version = $null
        }
        $Script:DshCache = $r
        return $r
    }

    $r = [pscustomobject]@{
        Mode = 'npx'; NodeExe = $nodeExe; BinJs = $null
        CmdShim = $null; Source = "npx -y $Script:NpmPackage"; Version = $null
    }
    $Script:DshCache = $r
    return $r
}

function Get-ListenerMap {
    <#
      返回 @{ 端口 = PID } 的监听端口表，带数秒缓存。
      一次 netstat -ano 拿全表只要 ~21ms；而逐端口 Get-NetTCPConnection
      在本机每次失败要 ~840ms —— 20 个端口的循环会差出十几秒。
    #>
    param([switch]$Force)

    if (-not $Force -and $Script:ListenerMap -and
        ((Get-Date) - $Script:ListenerMapAt).TotalSeconds -lt 3) {
        return $Script:ListenerMap
    }

    $map = @{}
    try {
        foreach ($line in (netstat -ano 2>$null)) {
            if ($line -match '^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)') {
                $map[[int]$Matches[1]] = [int]$Matches[2]
            }
        }
    } catch { }

    # netstat 完全没结果时才退回 Get-NetTCPConnection（慢，但聊胜于无）
    if ($map.Count -eq 0) {
        try {
            Get-NetTCPConnection -State Listen -ErrorAction Stop | ForEach-Object {
                $map[[int]$_.LocalPort] = [int]$_.OwningProcess
            }
        } catch { }
    }

    $Script:ListenerMap   = $map
    $Script:ListenerMapAt = Get-Date
    return $map
}

function Get-ListenerPid {
    param([int]$Port)
    $map = Get-ListenerMap
    if ($map.ContainsKey($Port)) { return $map[$Port] }
    return $null
}

function Test-PortInUse {
    param([int]$Port)

    $map = Get-ListenerMap
    if ($map.ContainsKey($Port)) { return $true }
    # 端口表非空 = netstat 可用且没有该端口 → 结论可信，无需再探测
    if ($map.Count -gt 0) { return $false }

    # 端口表为空：探测手段都不可用，退回直接建立 TCP 连接
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(500)
        if ($ok) { $client.EndConnect($iar); return $true }
        return $false
    } catch {
        return $false
    } finally {
        if ($client) { try { $client.Close() } catch { } }
    }
}

function Get-PortOwner {
    param([int]$Port)
    $ownerPid = Get-ListenerPid -Port $Port
    if (-not $ownerPid) { return $null }
    try {
        $p = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ProcessId = $ownerPid
            Name      = if ($p) { $p.ProcessName } else { '未知' }
            Path      = if ($p) { $p.Path } else { $null }
        }
    } catch {
        return [pscustomobject]@{ ProcessId = $ownerPid; Name = '未知'; Path = $null }
    }
}

# ─────────────────────────────── 状态文件 ───────────────────────────────

function Initialize-DataDir {
    foreach ($d in @($Script:DataDir, $Script:LogDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    # state.json / 日志都含访问凭据，别让它们被误提交
    $gi = Join-Path $Script:DataDir '.gitignore'
    if (-not (Test-Path $gi)) {
        try { Set-Content -Path $gi -Value "*`n!.gitignore`n" -Encoding ASCII -ErrorAction Stop } catch { }
    }
}

function Read-LauncherState {
    if (-not (Test-Path $Script:StateFile)) { return $null }
    try { return (Get-Content $Script:StateFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Save-LauncherState {
    param($State)
    Initialize-DataDir
    $State | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:StateFile -Encoding UTF8
}

function Clear-LauncherState {
    if (Test-Path $Script:StateFile) { Remove-Item $Script:StateFile -Force -ErrorAction SilentlyContinue }
}

function Get-LiveGuiState {
    <# 读取 state.json 并验证进程是否仍存活；不存活则清理并返回 $null #>
    $st = Read-LauncherState
    if (-not $st) { return $null }
    $proc = Get-Process -Id $st.pid -ErrorAction SilentlyContinue
    if (-not $proc) { Clear-LauncherState; return $null }
    return [pscustomobject]@{ State = $st; Process = $proc }
}

# ─────────────────────────────── 启动 Web UI ───────────────────────────────

function Clear-ProgressLine {
    Write-Host ("`r" + (' ' * 60) + "`r") -NoNewline
}

function Wait-ForWebUrl {
    <#
      轮询日志等待 `dsh web: <url>` 行出现。
      带可视化进度：spinner + 进度条 + 实时耗时，避免用户以为卡死。
      进度条按 $ProgressFullSecs 秒填满，纯属视觉估计，不是剩余时间承诺。
    #>
    param(
        [string]$OutLog,
        [string]$ErrLog,
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSec = 90,
        [switch]$ShowProgress
    )
    $esc      = [char]27
    $ansi     = [regex]::Escape($esc) + '\[[0-9;]*[A-Za-z]'
    $start    = Get-Date
    $deadline = $start.AddSeconds($TimeoutSec)
    $spin     = @('|', '/', '-', '\')
    $i        = 0
    $lastDraw = [datetime]::MinValue

    while ((Get-Date) -lt $deadline) {
        foreach ($f in @($OutLog, $ErrLog)) {
            if ($f -and (Test-Path $f)) {
                try {
                    $text = Get-Content $f -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if ($text) {
                        $clean = $text -replace $ansi, ''
                        $m = [regex]::Match($clean, 'dsh web:\s*(https?://\S+)')
                        if ($m.Success) {
                            if ($ShowProgress) { Clear-ProgressLine }
                            return $m.Groups[1].Value.Trim()
                        }
                    }
                } catch { }
            }
        }

        $exited = $false
        if ($Process) {
            try { if ($Process.HasExited) { $exited = $true } } catch { }
        }
        if ($exited) {
            if ($ShowProgress) { Clear-ProgressLine }
            return $null
        }

        if ($ShowProgress) {
            $now = Get-Date
            # 约 8 帧/秒即可，避免刷新本身成为开销
            if (($now - $lastDraw).TotalMilliseconds -ge 120) {
                $elapsed = ($now - $start).TotalSeconds
                $width   = 22
                $pct     = [Math]::Min(1.0, $elapsed / [double]$Script:ProgressFullSecs)
                $filled  = [int][Math]::Round($pct * $width)
                $bar     = ('█' * $filled) + ('░' * ($width - $filled))
                Write-Host ("`r         {0} [{1}] {2,6:N1}s" -f $spin[$i % 4], $bar, $elapsed) -NoNewline
                $lastDraw = $now
            }
        }

        $i++
        Start-Sleep -Milliseconds 250
    }

    if ($ShowProgress) { Clear-ProgressLine }
    return $null
}

function Start-DshWeb {
    <#
      以独立进程启动 dsh web。
      返回 @{ Ok; Pid; Url; Log; ErrLog; Error; Elapsed }
      Ok=$false 表示启动确实失败（进程已退出且没打印 URL）。
    #>
    param(
        [int]$Port,
        [switch]$NoOpen,
        [string[]]$ExtraArgs = @(),
        [string]$WorkDir,
        [int]$WaitSeconds = $Script:UrlWaitSeconds,
        [switch]$ShowProgress
    )

    Initialize-DataDir
    $dsh = Resolve-Dsh

    $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outLog  = Join-Path $Script:LogDir "web-$stamp.out.log"
    $errLog  = Join-Path $Script:LogDir "web-$stamp.err.log"
    $started = Get-Date

    # dsh web 的应用参数
    $appArgs = @('web')
    if ($Port -gt 0) { $appArgs += @('--port', "$Port") }
    if ($NoOpen)     { $appArgs += '--no-open' }
    if ($ExtraArgs)  { $appArgs += $ExtraArgs }

    try {
        if ($dsh.Mode -eq 'node') {
            $exe = $dsh.NodeExe
            # 显式加引号：Start-Process 只用空格拼接 ArgumentList，不自动转义
            $argList = @("`"$($dsh.BinJs)`"") + $appArgs
        } elseif ($dsh.Mode -eq 'cmd') {
            $exe = $dsh.CmdShim
            $argList = $appArgs
        } else {
            # 兜底模式：显式走 npx.cmd，避免 Start-Process 挑到 npm 的 .ps1 垫片
            $exe = Resolve-NpmExe -Name npx
            if (-not $exe) { $exe = 'npx.cmd' }
            $argList = @('-y', $Script:NpmPackage) + $appArgs
        }

        $proc = Start-Process -FilePath $exe -ArgumentList $argList `
            -WorkingDirectory $WorkDir `
            -RedirectStandardOutput $outLog `
            -RedirectStandardError $errLog `
            -WindowStyle Hidden -PassThru

        $url = Wait-ForWebUrl -OutLog $outLog -ErrLog $errLog -Process $proc `
            -TimeoutSec $WaitSeconds -ShowProgress:$ShowProgress

        $elapsed = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)

        # 拿到地址就立刻把日志里的凭据抹掉
        if ($url) { [void](Protect-LogToken -Paths @($outLog, $errLog)) }

        # 关键：区分「还在启动」和「已经崩溃」。
        # 没有 URL 且进程已退出 = 启动失败，必须如实报告，否则用户会以为成功了。
        $exited   = $false
        $exitCode = $null
        try {
            if ($proc.HasExited) {
                $exited = $true
                # 进程已退出时先 WaitForExit，否则 ExitCode 可能读不到
                try { [void]$proc.WaitForExit(2000) } catch { }
                try { $exitCode = $proc.ExitCode } catch { }
            }
        } catch { }

        if ($exited -and -not $url) {
            if ($ShowProgress) { Clear-ProgressLine }
            $codeText = if ($null -ne $exitCode) { '（退出码 ' + $exitCode + '）' } else { '' }
            return [pscustomobject]@{
                Ok      = $false
                Error   = "dsh 进程已退出$codeText，未打印 dsh web: URL。"
                Log     = $outLog
                ErrLog  = $errLog
                Elapsed = $elapsed
            }
        }

        $state = [pscustomobject]@{
            pid       = $proc.Id
            port      = $Port
            url       = $url
            workspace = $WorkDir
            startedAt = (Get-Date).ToString('s')
            outLog    = $outLog
            errLog    = $errLog
            mode      = $dsh.Mode
            entry     = $dsh.Source
            appArgs   = $appArgs
            elapsed   = $elapsed
        }
        Save-LauncherState $state

        return [pscustomobject]@{
            Ok = $true; Pid = $proc.Id; Url = $url
            Log = $outLog; ErrLog = $errLog; Proc = $proc
            Mode = $dsh.Mode; Elapsed = $elapsed
        }
    } catch {
        if ($ShowProgress) { Clear-ProgressLine }
        return [pscustomobject]@{
            Ok = $false; Error = $_.Exception.Message
            Log = $outLog; ErrLog = $errLog
            Elapsed = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    }
}

function Show-LaunchError {
    param($Result, [int]$Port)
    Write-Host ''
    Write-Bad '启动失败。'
    if ($Result.Error) { Write-Hint "原因：$($Result.Error)" }

    # 汇总两份日志用于诊断
    $allText = ''
    foreach ($f in @($Result.ErrLog, $Result.Log)) {
        if ($f -and (Test-Path $f)) {
            $allText += (Get-Content $f -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        }
    }

    if ($allText -match 'EPERM' -and $allText -match 'profiles') {
        Write-Host ''
        Write-Hint "诊断：dsh 无法写入 $($Script:DshHome)\profiles —— 权限被拒绝。"
        Write-Hint 'dsh 启动时要重写 profile 配置，该目录必须可写。'
        Write-Hint '可运行 [5] → [1] 环境自检确认；若在沙箱 / 受限账户下运行，请放宽该目录权限。'
    } elseif ($allText -match 'EADDRINUSE') {
        Write-Host ''
        Write-Hint '诊断：端口已被占用（EADDRINUSE）—— 换一个端口再试。'
    } elseif ($allText -match 'frontend|dist.*not|not built') {
        Write-Host ''
        Write-Hint '诊断：前端资源缺失 —— 源码 checkout 需先运行 pnpm run build。'
    } elseif ($allText -match 'credentials|api.?key|401|403') {
        Write-Host ''
        Write-Hint '诊断：可能是 API 凭据问题 —— 检查 DSH_HOME 下的 .credentials.yaml。'
    }

    foreach ($f in @($Result.ErrLog, $Result.Log)) {
        if ($f -and (Test-Path $f)) {
            $tail = Get-Content $f -Tail 20 -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($tail) {
                Write-Section "日志尾部：$(Split-Path $f -Leaf)"
                # 打码：日志里可能残留 token
                $tail | ForEach-Object { Write-Host "    $(Get-MaskedUrl -Url $_)" -ForegroundColor DarkGray }
                break
            }
        }
    }
    Write-Hint "完整错误输出：$($Result.ErrLog)"
    Write-Hint "完整标准输出：$($Result.Log)"
    if ($Port -gt 0 -and (Test-PortInUse -Port $Port)) {
        Write-Hint "提示：端口 $Port 目前已被占用。"
    }
}

# ─────────────────────────────── 菜单动作 ───────────────────────────────

function Get-FreePortSuggestion {
    param([int]$Start = 3080, [int]$Count = 20)
    # 走缓存的端口表，20 次查询≈零成本
    for ($p = $Start + 1; $p -le $Start + $Count; $p++) {
        if (-not (Test-PortInUse -Port $p)) { return $p }
    }
    return 0
}

function Stop-GuiProcess {
    param($State)
    if (-not $State) { return $false }
    try {
        $proc = Get-Process -Id $State.pid -ErrorAction SilentlyContinue
        if (-not $proc) {
            Write-Info "PID $($State.pid) 已不存在。"
            Clear-LauncherState
            return $true
        }
        Stop-Process -Id $State.pid -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 600
        if (Get-Process -Id $State.pid -ErrorAction SilentlyContinue) {
            # taskkill 的失败原因写在 stderr 上：不能再让全局 EAP=Stop 把它升级成异常
            $tk = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            if (-not (Test-Path $tk)) { $tk = 'taskkill.exe' }
            [void](Invoke-NativeCaptured -FilePath $tk -Arguments @('/PID', "$($State.pid)", '/T', '/F'))
            Start-Sleep -Milliseconds 400
        }
        if (Get-Process -Id $State.pid -ErrorAction SilentlyContinue) {
            Write-Bad "无法停止 PID $($State.pid)。"
            return $false
        }
        Write-Ok "已停止 Web UI（PID $($State.pid)）。"
        Clear-LauncherState
        # 进程已退出，句柄释放，现在才洗得掉它日志里的 token
        [void](Protect-LogToken -Paths @($State.outLog, $State.errLog))
        # 端口表已过期，强制刷新
        [void](Get-ListenerMap -Force)
        return $true
    } catch {
        Write-Bad "停止失败：$($_.Exception.Message)"
        return $false
    }
}

function Invoke-LaunchWeb {
    param([switch]$NoOpen, [string[]]$ExtraArgs = @(), [int]$PortOverride = 0, [string]$WorkDir)

    if (-not $WorkDir) { $WorkDir = $Script:DefaultWorkspace }

    $port = if ($PortOverride -gt 0) { $PortOverride } else { $Script:DefaultPort }

    # 启动前强制刷新一次端口表，避免用到过期结论
    [void](Get-ListenerMap -Force)
    # 旧实例已退出，趁现在把历史日志里的 token 洗掉
    [void](Clear-StaleLogTokens)

    # ── 端口占用检查 ──
    if (Test-PortInUse -Port $port) {
        $owner = Get-PortOwner -Port $port
        $live  = Get-LiveGuiState
        $freeP = 0
        Write-Host ''
        Write-Warn2 "端口 $port 已被占用。"
        if ($owner) { Write-Hint "占用进程：$($owner.Name) (PID $($owner.ProcessId))" }

        if ($live -and $live.State.port -eq $port) {
            Write-Hint '这看起来就是本启动器先前启动的 Web UI。'
            Write-Host ''
            Write-Host '    [1] 打开它（在浏览器中）' -ForegroundColor White
            Write-Host '    [2] 停止它，然后重新启动' -ForegroundColor White
            Write-Host '    [3] 另起一个实例（自动选空闲端口）' -ForegroundColor White
            Write-Host '    [0] 取消' -ForegroundColor White
            $sel = Read-Host '  请选择'
            switch ($sel) {
                '1' {
                    if ($live.State.url) {
                        Write-Info "正在打开 http://127.0.0.1:$($live.State.port)/"
                        Start-Process $live.State.url | Out-Null
                    } else {
                        Write-Warn2 "未记录访问地址，可尝试 http://127.0.0.1:$($live.State.port)/"
                    }
                    Pause-Any
                    return
                }
                '2' { [void](Stop-GuiProcess -State $live.State); Write-Info '已停止，继续启动新的实例…' }
                '3' {
                    $freeP = Get-FreePortSuggestion -Start $port
                    if ($freeP -le 0) { Write-Bad '未找到可用端口。'; Pause-Any; return }
                    $port = $freeP
                    Write-Info "改用端口 $port"
                }
                default { return }
            }
        } else {
            $freeP = Get-FreePortSuggestion -Start $port
            Write-Host ''
            Write-Host "    [1] 改用空闲端口 $freeP" -ForegroundColor White
            Write-Host "    [2] 仍然尝试用端口 $port 启动（可能失败）" -ForegroundColor White
            Write-Host '    [0] 取消' -ForegroundColor White
            $sel = Read-Host '  请选择'
            switch ($sel) {
                '1' {
                    if ($freeP -le 0) { Write-Bad '未找到可用端口。'; Pause-Any; return }
                    $port = $freeP
                }
                '2' { }
                default { return }
            }
        }
    }

    # ── 启动 ──
    Write-Host ''
    $modeText = if ($NoOpen) { '不自动打开浏览器' } else { '自动打开浏览器' }
    Write-Info "启动 Web UI · 端口 $port · $modeText"
    Write-Hint "工作目录：$WorkDir"

    $res = Start-DshWeb -Port $port -NoOpen:$NoOpen -ExtraArgs $ExtraArgs -WorkDir $WorkDir -ShowProgress

    if (-not $res.Ok) {
        Show-LaunchError -Result $res -Port $port
        Write-Elapsed -Seconds $res.Elapsed -Label '启动耗时（已失败并退出）'
        Pause-Any
        return
    }

    if (-not $res.Url) {
        Write-Host ''
        Write-Warn2 "进程已启动（PID $($res.Pid)），但暂未捕获到 dsh web: URL。"
        Write-Hint '它可能仍在启动中（首次启动会初始化 profile，较慢）。'
        Write-Hint '稍后可用 [5] → [3] 查看状态、[5] → [5] 查看日志。'
        Write-Hint "日志：$($res.Log)"
        Write-Elapsed -Seconds $res.Elapsed -Label '已等待耗时'
        Pause-Any
        return
    }

    # ── 成功：默认只显示脱敏地址 ──
    Write-Host ''
    Write-Ok "Web UI 已启动（PID $($res.Pid) · 耗时 $(Format-Duration -Seconds $res.Elapsed)）"
    Write-Host ''
    Write-Host "  地址：$(Get-OriginUrl -Url $res.Url)" -ForegroundColor Green
    Write-Host '        ?token=••••••••   （已隐藏）' -ForegroundColor DarkGray
    Write-Host ''
    Write-Hint '完整访问地址（含 token）请用菜单 [8] 查看 / 复制。'
    Write-Hint 'token 等同于登录凭据：不要截图或分享。'

    if ($NoOpen) {
        $ans = Read-Host '  现在就用默认浏览器打开它？[Y/n]'
        if ($ans -notmatch '^[Nn]') {
            Start-Process $res.Url | Out-Null
            Write-Info '已交给默认浏览器。'
        }
    }
    Write-Hint '启动器可以退出了，GUI 会继续在后台运行。'
    Write-Hint "日志：$($res.Log)"
    Pause-Any
}

function Show-AccessInfo {
    <# [8] 访问地址与 Token —— 唯一显示完整凭据的地方，需要用户主动进入 #>
    Write-Section '访问地址与 Token'

    $live = Get-LiveGuiState
    if (-not $live) {
        Write-Info '当前没有由本启动器启动的 GUI 在运行。'
        Write-Host ''
        Write-Hint 'token 由每个 GUI 进程单独生成，进程停止后立即失效。'
        Write-Hint '需要访问地址请先用 [1] 或 [2] 启动 Web UI。'
        Pause-Any
        return
    }

    $st  = $live.State
    $url = $st.url

    Write-Ok "运行中：PID $($st.pid) · 端口 $($st.port)"
    Write-Hint "工作目录：$($st.workspace)"
    Write-Host ''

    if (-not $url) {
        Write-Warn2 '本次启动没有捕获到带 token 的地址。'
        Write-Hint "可尝试直接访问 http://127.0.0.1:$($st.port)/"
        Pause-Any
        return
    }

    Write-Host '  完整访问地址（含 token）：' -ForegroundColor Yellow
    Write-Host "  $url" -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  这个地址等同于登录凭据：' -ForegroundColor DarkYellow
    Write-Hint '· 不要截图、发聊天记录或提交进代码仓库'
    Write-Hint '· 只在本机浏览器使用，不要转发给别人'
    Write-Hint '· 停止 GUI 后 token 立即失效'
    Write-Host ''

    $tok = Get-TokenFromUrl -Url $url
    Write-Host '    [1] 复制完整地址到剪贴板' -ForegroundColor White
    Write-Host '    [2] 在默认浏览器中打开' -ForegroundColor White
    Write-Host '    [3] 只复制 token' -ForegroundColor White
    Write-Host '    [0] 返回（同时清屏，避免凭据留在屏幕上）' -ForegroundColor DarkGray
    Write-Host ''

    $c = Read-Host '  请选择'
    switch ($c) {
        '1' {
            try { Set-Clipboard -Value $url; Write-Ok '完整地址已复制到剪贴板。' }
            catch { Write-Bad "复制失败：$($_.Exception.Message)" }
            Pause-Any
        }
        '2' {
            try { Start-Process $url | Out-Null; Write-Ok '已交给默认浏览器。' }
            catch { Write-Bad "打开失败：$($_.Exception.Message)" }
            Pause-Any
        }
        '3' {
            if ($tok) {
                try { Set-Clipboard -Value $tok; Write-Ok 'token 已复制到剪贴板。' }
                catch { Write-Bad "复制失败：$($_.Exception.Message)" }
            } else {
                Write-Bad '未能从地址中解析出 token。'
            }
            Pause-Any
        }
        default { }
    }
}

function Show-CurrentVersion {
    Write-Section '当前安装版本'
    $tAll        = Get-Date
    $tResolve    = Get-Date
    $dsh         = Resolve-Dsh
    $resolveSecs = ((Get-Date) - $tResolve).TotalSeconds

    try {
        $node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($node) {
            Write-Ok "Node.js $(& node -v 2>$null)  ($($node.Source))"
        } else {
            Write-Bad 'Node.js 未找到 —— dsh 需要 Node 才能运行。'
        }
    } catch { Write-Warn2 "无法读取 Node 版本：$($_.Exception.Message)" }

    Write-Host ''
    Write-Info "dsh 入口模式：$($dsh.Mode)"
    Write-Hint "入口：$($dsh.Source)"
    if ($dsh.Version) { Write-Ok "已安装版本：$($dsh.Version)" }

    # 用 dsh 自身输出复核（--version 只读，不写 profile）
    $tRun = Get-Date
    try {
        if ($dsh.Mode -eq 'node') {
            $r = Invoke-NativeCaptured -FilePath $dsh.NodeExe -Arguments @($dsh.BinJs, '--version')
        } elseif ($dsh.Mode -eq 'cmd') {
            $r = Invoke-NativeCaptured -FilePath $dsh.CmdShim -Arguments @('--version')
        } else {
            $r = Invoke-NpmTool -Name npx -Arguments @('-y', $Script:NpmPackage, '--version')
        }
        $vText = (@($r.Output) -join "`n").Trim()
        if ($r.Ok -and $vText) {
            Write-Ok "dsh --version → $vText"
        } elseif ($vText) {
            Write-Warn2 "dsh --version 退出码 $($r.ExitCode)：$vText"
        } else {
            Write-Warn2 "dsh --version 没有输出（退出码 $($r.ExitCode)）。"
        }
    } catch {
        Write-Warn2 "无法执行 dsh --version：$($_.Exception.Message)"
    }
    $runSecs = ((Get-Date) - $tRun).TotalSeconds

    Write-Host ''
    Write-Hint "DSH_HOME：$($Script:DshHome)"
    $profiles = Join-Path $Script:DshHome 'profiles'
    if (Test-Path $profiles) {
        # node_modules 是依赖目录，不是 profile，需要排除
        $names = @(Get-ChildItem $profiles -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -ne 'node_modules' } |
                   Select-Object -ExpandProperty Name) -join ', '
        if ($names) { Write-Hint "可用 profile：$names" }
    }

    Write-Host ''
    Write-Elapsed -Seconds $resolveSecs -Label '入口解析耗时'
    Write-Elapsed -Seconds $runSecs -Label 'dsh --version 耗时'
    Write-Elapsed -Seconds ((Get-Date) - $tAll).TotalSeconds -Label '本项总耗时'
    Pause-Any
}

function Show-LatestVersion {
    Write-Section '最新可用版本'
    Write-Info '正在查询 npm registry（最多等 30 秒）…'
    $tAll = Get-Date

    # ── 1) registry 查询（子进程 + 30 秒硬超时）──
    $tQuery = Get-Date
    $job = Start-Job -ScriptBlock {
        param($exe, $pkg)
        # 子进程里没有启动器的函数，这里自行兜底；同样避开 npm.ps1 垫片
        if (-not $exe) { $exe = 'npm.cmd' }
        $ErrorActionPreference = 'Continue'
        $out = & $exe view $pkg version --fetch-timeout=15000 --fetch-retries=1 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) { ($out | Select-Object -Last 1).ToString().Trim() }
    } -ArgumentList (Resolve-NpmExe -Name npm), $Script:NpmPackage

    $latest   = $null
    $timedOut = $false
    if (Wait-Job $job -Timeout 30) {
        $latest = Receive-Job $job
    } else {
        $timedOut = $true
        Stop-Job $job -ErrorAction SilentlyContinue
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $querySecs = ((Get-Date) - $tQuery).TotalSeconds

    # ── 2) 本地入口解析（可能触发 npm root -g，约 1 秒）──
    $tResolve    = Get-Date
    $cur         = (Resolve-Dsh).Version
    $resolveSecs = ((Get-Date) - $tResolve).TotalSeconds

    if ($latest) {
        Write-Ok "npm 上最新版本：$latest"
        if ($cur) {
            Write-Hint "本机已安装：$cur"
            if ($cur -eq $latest) {
                Write-Ok '已是最新。'
            } else {
                Write-Warn2 '本机版本与最新版本不同。'
                Write-Hint "升级：npx -y $Script:NpmPackage@latest --version"
            }
        }
    } else {
        if ($timedOut) {
            Write-Bad '查询超时：等待 30 秒仍未返回，已停止查询进程。'
        } else {
            Write-Bad '查询失败（网络不可达、代理拦截，或 npm 不在 PATH 上）。'
        }
        Write-Hint "可手动执行：npm view $($Script:NpmPackage) version"
        Write-Hint "或在浏览器打开：https://www.npmjs.com/package/$($Script:NpmPackage)"
        Write-Hint '查询失败不影响启动，已安装的版本仍可正常使用。'
    }

    Write-Host ''
    Write-Elapsed -Seconds $querySecs -Label $(if ($timedOut) { '查询耗时（超时上限 30 秒）' } else { '查询耗时' })
    Write-Elapsed -Seconds $resolveSecs -Label '本地入口解析耗时'
    Write-Elapsed -Seconds ((Get-Date) - $tAll).TotalSeconds -Label '本项总耗时'
    Pause-Any
}

function Invoke-SelfCheck {
    param([switch]$Quiet)

    $issues = New-Object System.Collections.Generic.List[string]
    Write-Section '环境自检'
    $tAll = Get-Date

    # 1. PowerShell / 语言模式
    $psv  = $PSVersionTable.PSVersion.ToString()
    $lang = $ExecutionContext.SessionState.LanguageMode
    Write-Ok "PowerShell $psv（LanguageMode: $lang）"

    # 2. Node.js
    $node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($node) {
        Write-Ok "Node.js $(& node -v 2>$null) → $($node.Source)"
    } else {
        Write-Bad 'Node.js 未找到：dsh 无法运行。'
        $issues.Add('安装 Node.js 后重试')
    }

    # 3. dsh 入口（首次解析可能触发 npm root -g，实测约 1 秒）
    $tResolve    = Get-Date
    $dsh         = Resolve-Dsh
    $resolveSecs = ((Get-Date) - $tResolve).TotalSeconds
    if ($dsh.Mode -eq 'npx') {
        Write-Warn2 '未在本地找到 dsh 入口，启动时会回退到 npx（每次可能较慢）。'
        Write-Hint "修复：npx -y $Script:NpmPackage@latest --version"
        $issues.Add('dsh 未本地安装')
    } else {
        Write-Ok "dsh 入口（$($dsh.Mode)）：$($dsh.Source)"
        if ($dsh.Version) { Write-Info "版本：$($dsh.Version)" }
    }

    # 4. DSH_HOME
    if (Test-Path $Script:DshHome) {
        Write-Ok "DSH_HOME 存在：$($Script:DshHome)"
        $probe = Join-Path $Script:DshHome (".launcher-write-probe-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            Set-Content -Path $probe -Value 'probe' -Encoding UTF8 -ErrorAction Stop
            Remove-Item $probe -Force -ErrorAction SilentlyContinue
            Write-Ok 'DSH_HOME 可写。'
        } catch {
            Write-Bad "DSH_HOME 不可写：$($_.Exception.Message)"
            Write-Hint 'dsh 启动时会重写 profile 配置，不可写会直接导致启动失败。'
            $issues.Add('DSH_HOME 不可写')
        }
    } else {
        Write-Warn2 "DSH_HOME 不存在：$($Script:DshHome)"
        Write-Hint '首次启动 dsh 时会自动创建。'
    }

    # 5. web profile
    $webProfile = Join-Path $Script:DshHome 'profiles\web'
    if (Test-Path $webProfile) {
        Write-Ok "web profile 存在：$webProfile"
        $missing = @()
        foreach ($f in @('package.json', 'cordis.yml', 'cordis.patch.yml')) {
            if (-not (Test-Path (Join-Path $webProfile $f))) { $missing += $f }
        }
        if ($missing.Count -gt 0) {
            Write-Warn2 "profile 缺少文件：$($missing -join ', ')（首次启动会自动补齐）"
        }
    } else {
        Write-Warn2 'web profile 尚未初始化（首次启动 dsh web 会自动创建）。'
    }

    # 6. 前端资源
    $feFound = $false
    $nmRoots = @()
    if ($dsh.Mode -eq 'node') {
        # <...>\node_modules\@deepseek-ai\dsh\lib\bin.js → <...>\node_modules
        $nmRoots += (Split-Path (Split-Path (Split-Path (Split-Path $dsh.BinJs -Parent) -Parent) -Parent) -Parent)
    }
    $nmRoots += (Join-Path $Script:DshHome 'profiles\node_modules')
    foreach ($root in ($nmRoots | Select-Object -Unique)) {
        $fe = Join-Path $root '@deepseek-ai\dsh-web-frontend'
        if (Test-Path $fe) {
            $dist = Join-Path $fe 'dist'
            if (Test-Path $dist) {
                Write-Ok "前端资源已构建：$dist"
            } else {
                Write-Warn2 "前端包存在但未见 dist：$fe"
                Write-Hint '若启动时报「前端未构建」，需在源码 checkout 中运行 pnpm run build。'
                $issues.Add('前端未构建')
            }
            $feFound = $true
            break
        }
    }
    if (-not $feFound) { Write-Warn2 '未定位到 dsh-web-frontend 包（通常仍可正常启动）。' }

    # 7. 端口
    [void](Get-ListenerMap -Force)
    $port = $Script:DefaultPort
    if (Test-PortInUse -Port $port) {
        $owner = Get-PortOwner -Port $port
        $live  = Get-LiveGuiState
        if ($live -and $live.State.port -eq $port) {
            Write-Ok "端口 $port 上运行着本启动器启动的 Web UI（PID $($live.State.pid)）。"
        } else {
            $who = if ($owner) { "$($owner.Name) PID $($owner.ProcessId)" } else { '未知进程' }
            Write-Warn2 "端口 $port 被占用（$who）。启动时会提示改用其他端口。"
        }
    } else {
        Write-Ok "端口 $port 空闲。"
    }

    # 8. 运行状态
    $live2 = Get-LiveGuiState
    if ($live2) {
        Write-Ok "检测到运行中的 GUI：PID $($live2.State.pid)，端口 $($live2.State.port)"
    } else {
        Write-Info '当前没有由本启动器启动的 GUI 在运行。'
    }

    # 9. API 凭据
    $cred = Join-Path $Script:DshHome '.credentials.yaml'
    if (Test-Path $cred) {
        Write-Ok 'API 凭据文件存在。'
    } else {
        Write-Warn2 '未找到 .credentials.yaml —— 首次使用时需要在 GUI 中配置 API key。'
        $issues.Add('未配置 API 凭据')
    }

    # 10. 本地凭据暴露面
    #     检测明文必须用负向断言 token=(?!REDACTED)。
    #     曾写成 token=[^R] 是错的 —— token 本身可能以 R 开头，会整片漏报。
    $leakyLogs = New-Object System.Collections.Generic.List[string]
    foreach ($lf in (Get-ChildItem $Script:LogDir -Filter '*.log' -ErrorAction SilentlyContinue)) {
        try {
            if ((Get-Content $lf.FullName -Raw -Encoding UTF8) -match 'token=(?!REDACTED)') {
                $leakyLogs.Add($lf.Name)
            }
        } catch { }
    }
    if ($leakyLogs.Count -gt 0) {
        Write-Warn2 "$($leakyLogs.Count) 个日志文件含明文 token。"
        Write-Hint '这些多半来自旧版本（当时还没有日志清洗）。'
        Write-Hint '可用 [5] → [6] 清理日志。'
        $issues.Add('日志含 token')
    } else {
        Write-Ok '日志中未发现明文 token。'
    }
    # state.json 保存访问地址是 [8] 的功能前提，不算缺陷，只作说明
    if (Test-Path $Script:StateFile) {
        Write-Info 'state.json 保存访问地址（[8] 的数据来源），已由 .gitignore 保护。'
    }

    Write-Host ''
    if ($issues.Count -eq 0) {
        Write-Ok '自检完成：未发现阻塞性问题。'
    } else {
        Write-Warn2 "自检完成：$($issues.Count) 项需要留意 —— $($issues -join '；')"
    }
    Write-Host ''
    Write-Elapsed -Seconds $resolveSecs -Label 'dsh 入口解析耗时（可用 npm root -g 触发）'
    Write-Elapsed -Seconds ((Get-Date) - $tAll).TotalSeconds -Label '自检总耗时'
    if (-not $Quiet) { Pause-Any }
    return $issues
}

function Repair-Dsh {
    Write-Section '修复 / 重新安装 dsh'
    # 只累计「真正在干活」的步骤耗时：y/N 提示等的是人，不该算进去
    $opSecs = 0.0

    $dsh = Resolve-Dsh
    if ($dsh.Mode -ne 'npx') { Write-Info "当前入口（$($dsh.Mode)）：$($dsh.Source)" }
    if ($dsh.Version) { Write-Info "当前版本：$($dsh.Version)" }
    Write-Hint '注意：这一步会从网络下载并执行官方 npm 包，请确认网络环境可信。'

    $npmExe = Resolve-NpmExe -Name npm
    $npxExe = Resolve-NpmExe -Name npx
    if (-not $npxExe) {
        Write-Warn2 '未在 PATH 上找到 npx.cmd / npx.exe。'
        Write-Hint 'npm 自带的 npx.ps1 垫片无法被启动器安全调用（它会用调用行原文重放参数），'
        Write-Hint '若只有 .ps1 垫片，请修复 npm 安装后重试。'
    }

    # ── 1) 刷新 npx 缓存里的副本 ──
    Write-Host ''
    $ans = Read-Host "  用 npx 重新拉取 $($Script:NpmPackage)@latest？[y/N]"
    if ($ans -match '^[Yy]') {
        Write-Info "正在运行：npx -y $($Script:NpmPackage)@latest --version"
        Write-Hint '这会刷新 npx 缓存中的副本，需要联网，可能等待 1–3 分钟。'
        Write-Host ''
        $tStep    = Get-Date
        $r        = Invoke-NpmTool -Name npx -Arguments @('-y', "$($Script:NpmPackage)@latest", '--version')
        $stepSecs = ((Get-Date) - $tStep).TotalSeconds
        $opSecs  += $stepSecs
        foreach ($line in @($r.Output)) {
            if ("$line".Trim()) { Write-Host "    $line" -ForegroundColor DarkGray }
        }
        Write-Host ''
        if ($r.Ok) {
            Write-Ok 'npx 拉取完成。'
        } else {
            Write-Bad "拉取失败（退出码 $($r.ExitCode)）。"
            Write-Hint '检查网络 / 代理设置，或手动执行该命令查看详细报错：'
            Write-Hint "npx -y $($Script:NpmPackage)@latest --version"
        }
        Write-Elapsed -Seconds $stepSecs -Label 'npx 拉取耗时'
    }

    # ── 2) npm 全局安装：这才是「本地入口缺失 / 被删」的真正修复手段 ──
    Write-Host ''
    $dsh2 = Resolve-Dsh -Force
    if ($dsh2.Mode -eq 'npx') {
        Write-Warn2 '没有可用的本地 dsh 入口（目前只能回退到 npx，每次启动都慢）。'
    } else {
        Write-Info "重新解析后入口（$($dsh2.Mode)）：$($dsh2.Source)"
        if ($dsh2.Version) { Write-Ok "版本：$($dsh2.Version)" }
    }

    Write-Host ''
    Write-Hint 'npx 只刷新缓存副本；本地入口被删或损坏时，需要用 npm 全局重装。'
    $ans2 = Read-Host "  用 npm 全局安装 / 重装 $($Script:NpmPackage)@latest？[y/N]"
    if ($ans2 -match '^[Yy]') {
        if (-not $npmExe) {
            Write-Bad '未在 PATH 上找到 npm.cmd / npm.exe，无法执行全局安装。'
        } else {
            Write-Info "正在运行：npm install -g $($Script:NpmPackage)@latest"
            Write-Host ''
            $tStep    = Get-Date
            $ri       = Invoke-NpmTool -Name npm -Arguments @('install', '-g', "$($Script:NpmPackage)@latest")
            $stepSecs = ((Get-Date) - $tStep).TotalSeconds
            $opSecs  += $stepSecs
            foreach ($line in @($ri.Output)) {
                if ("$line".Trim()) { Write-Host "    $line" -ForegroundColor DarkGray }
            }
            Write-Host ''
            if ($ri.Ok) {
                Write-Ok 'npm 全局安装完成。'
            } else {
                Write-Bad "全局安装失败（退出码 $($ri.ExitCode)）。"
                Write-Hint '常见原因：没有写权限（用管理员 PowerShell 重试）、代理拦截、npm 前缀不可写。'
            }
            Write-Elapsed -Seconds $stepSecs -Label 'npm 全局安装耗时'
        }
    }

    # ── 3) 结论：用真实入口跑一次 --version，如实报告能否使用 ──
    Write-Host ''
    $dsh3 = Resolve-Dsh -Force
    if ($dsh3.Mode -eq 'npx') {
        Write-Warn2 '最终没有本地 dsh 入口；启动时会回退到 npx（可用但较慢）。'
        Write-Hint "可手动执行：npm install -g $($Script:NpmPackage)@latest"
    } else {
        Write-Info "入口（$($dsh3.Mode)）：$($dsh3.Source)"
        $tVer = Get-Date
        if ($dsh3.Mode -eq 'node') {
            $vr = Invoke-NativeCaptured -FilePath $dsh3.NodeExe -Arguments @($dsh3.BinJs, '--version')
        } else {
            $vr = Invoke-NativeCaptured -FilePath $dsh3.CmdShim -Arguments @('--version')
        }
        $verSecs  = ((Get-Date) - $tVer).TotalSeconds
        $opSecs  += $verSecs
        $vText = (@($vr.Output) -join ' ').Trim()
        if ($vr.Ok -and $vText) {
            Write-Ok "dsh --version → $vText"
        } elseif ($vText) {
            Write-Bad "入口不可用（退出码 $($vr.ExitCode)）：$vText"
            Write-Hint '删过安装目录的话，先执行上面的 npm 全局重装。'
        } else {
            Write-Bad "入口不可用（退出码 $($vr.ExitCode)，无输出）。"
        }
        Write-Elapsed -Seconds $verSecs -Label '入口 --version 复核耗时'
    }

    Write-Hint '入口路径若发生变化，后续启动会自动使用新路径。'
    Write-Host ''
    if ($opSecs -gt 0) {
        Write-Elapsed -Seconds $opSecs -Label '本项耗时合计（不含等待输入）'
    } else {
        Write-Hint '本项耗时合计：未执行任何下载 / 安装步骤。'
    }
    Pause-Any
}

function Show-RunningGui {
    Write-Section '运行中的 GUI'
    $tAll = Get-Date

    $live = Get-LiveGuiState
    if ($live) {
        $st = $live.State
        $uptime = ''
        try {
            $started = [datetime]::Parse($st.startedAt)
            $uptime = '（已运行 {0:hh\:mm\:ss}）' -f ((Get-Date) - $started)
        } catch { }

        Write-Ok "本启动器启动的 Web UI：PID $($st.pid) $uptime"
        Write-Hint "端口：$($st.port)"
        Write-Hint "工作目录：$($st.workspace)"
        if ($st.url) { Write-Hint "地址：$(Get-MaskedUrl -Url $st.url)（完整地址见 [8]）" }
        Write-Hint "日志：$($st.outLog)"
        Write-Hint "入口：$($st.entry)"
        $mem = [Math]::Round($live.Process.WorkingSet64 / 1MB, 1)
        Write-Hint "内存：${mem} MB"
    } else {
        Write-Info '没有由本启动器启动的 GUI 在运行。'
    }

    Write-Host ''
    Write-Info "端口 $($Script:DefaultPort) 检查："
    [void](Get-ListenerMap -Force)
    if (Test-PortInUse -Port $Script:DefaultPort) {
        $owner = Get-PortOwner -Port $Script:DefaultPort
        if ($owner) {
            Write-Warn2 "被占用：$($owner.Name) PID $($owner.ProcessId)"
            if ($owner.Path) { Write-Hint $owner.Path }
            if (-not $live) { Write-Hint '这可能是手动启动的 dsh，本启动器无法用 [5] → [4] 停止它。' }
        } else {
            Write-Warn2 '被占用（无法确定占用进程）。'
        }
    } else {
        Write-Ok '空闲。'
    }

    Write-Host ''
    Write-Info '相关 node 进程：'
    $found = $false
    Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        $cl = $_.CommandLine
        if ($cl -and ($cl -match 'dsh' -or $cl -match 'deepseek')) {
            $found = $true
            $short = if ($cl.Length -gt 110) { $cl.Substring(0, 110) + '…' } else { $cl }
            Write-Hint "PID $($_.ProcessId)：$short"
        }
    }
    if (-not $found) { Write-Hint '（无）' }

    Write-Host ''
    Write-Elapsed -Seconds ((Get-Date) - $tAll).TotalSeconds -Label '本项总耗时（netstat + CIM 查询）'
    Pause-Any
}

function Stop-GuiInteractive {
    Write-Section '停止 GUI'
    $live = Get-LiveGuiState
    if (-not $live) {
        Write-Info '没有由本启动器启动的 GUI 在运行。'
        [void](Get-ListenerMap -Force)
        if (Test-PortInUse -Port $Script:DefaultPort) {
            $owner = Get-PortOwner -Port $Script:DefaultPort
            if ($owner -and $owner.Name -match 'node') {
                $ans = Read-Host "  端口 $($Script:DefaultPort) 上有 node 进程 PID $($owner.ProcessId)，停止它？[y/N]"
                if ($ans -match '^[Yy]') {
                    $tStop = Get-Date
                    try {
                        Stop-Process -Id $owner.ProcessId -Force -ErrorAction Stop
                        Write-Ok "已停止 PID $($owner.ProcessId)。"
                    } catch { Write-Bad "停止失败：$($_.Exception.Message)" }
                    Write-Elapsed -Seconds ((Get-Date) - $tStop).TotalSeconds -Label '停止耗时'
                }
            }
        }
        Pause-Any
        return
    }

    $st = $live.State
    Write-Info "将停止：PID $($st.pid) · 端口 $($st.port) · 工作目录 $($st.workspace)"
    $ans = Read-Host '  确认停止？[y/N]'
    if ($ans -match '^[Yy]') {
        $tStop = Get-Date
        [void](Stop-GuiProcess -State $st)
        Write-Host ''
        Write-Elapsed -Seconds ((Get-Date) - $tStop).TotalSeconds -Label '停止耗时（含进程收尾与日志清洗）'
    } else {
        Write-Info '已取消。'
    }
    Pause-Any
}

function Get-LogNoisePatterns {
    <#
      已知的「第三方噪声行」正则表。[5] → [5] 用它把 GUI 日志拆成
      「值得看的行」与「噪声」两部分。

      为什么需要它：web-*.out.log 只是 dsh web 的 stdout 重定向文件，任何拿到
      这个句柄的子进程写什么都会落进来。实测某个实例的 285 行里有 283 行是
      移动云盘 mCloud 的 Shell 扩展（mcloud_shell_ext_x64.dll）刷的
      SharedMemory read faild —— 只看尾部 40 行会 100% 落在噪声里，等于没看。
      加新条目时请同时在 docs/faq.md 的《[5] → [5] 里出现看不懂的重复行》里记一笔。
    #>
    return @(
        '^\s*SharedMemory read faild\s*$'
    )
}

function Show-LogLines {
    <# 打印日志行：token 一律经 Get-MaskedUrl 打码。
       -Collapse   把连续重复的行折成一行「×N」
       -FirstNumber 大于 0 时给每行加行号（从该数字开始，需连续行） #>
    param(
        [string[]]$Lines,
        [switch]$Collapse,
        [int]$FirstNumber = 0
    )
    if (-not $Lines -or $Lines.Count -eq 0) {
        Write-Hint '（没有可显示的行）'
        return
    }
    $i = 0
    while ($i -lt $Lines.Count) {
        $j = $i
        if ($Collapse) {
            while ((($j + 1) -lt $Lines.Count) -and ($Lines[$j + 1] -ceq $Lines[$i])) { $j++ }
        }
        $times = $j - $i + 1
        $text  = Get-MaskedUrl -Url $Lines[$i]
        if ($Collapse -and $times -gt 1) {
            Write-Host ("    ×{0,-5} {1}" -f $times, $text) -ForegroundColor DarkGray
        } elseif ($FirstNumber -gt 0) {
            Write-Host ("    {0,5}  {1}" -f ($FirstNumber + $i), $text) -ForegroundColor DarkGray
        } else {
            Write-Host ("           {0}" -f $text) -ForegroundColor DarkGray
        }
        $i = $j + 1
    }
}

function Show-GuiLog {
    <#
      [5] → [5] 查看 GUI 日志 —— 纯只读：不创建、不删除、不改写任何文件。

      读的是哪一个文件（按优先级）：
        1. state.json 的 outLog 字段，即当前运行中实例的
           .dsh-launcher\logs\web-<yyyyMMdd-HHmmss>.out.log
        2. 若没有存活的实例，或上面那个文件已被删掉：退回 .dsh-launcher\logs\ 下
           「最后写入的 *.out.log」（按 LastWriteTime 倒序取第一个）
        3. 两者都没有 → 提示「还没有日志文件（尚未启动过 GUI）」

      为什么不再只显示「尾部 40 行」：
        这个文件只是 `dsh web` 的 stdout 重定向。实测其内容分布是
        「开头两行启动信息 + 后面成百上千行第三方噪声」（噪声模式见
        Get-LogNoisePatterns），所以尾部 40 行会 100% 落在噪声里 —— 用户反馈
        「打开日志什么都没有」，原因就在这里。改为：
          文件大小 / 行数 / 时间 + 构成统计
          → 单独列出「值得看的行」（带行号，最多 20 行）
          → 折叠掉连续重复后的尾部
          → [1] 原始尾部 / [2] 文件开头 / [3] 搜索关键词 三个入口
      并顺带报告同批 .err.log 是否非空。

      这个日志什么时候真的有用：启动失败时（失败原因写在这里，
      stderr 的原因写在同名 .err.log 里）。正常运行时它基本只有开头两行。
      历史对话与工具调用不在这里，别指望用它回放会话。
    #>
    Write-Section 'GUI 日志'

    $live = Get-LiveGuiState
    $log = $null
    if ($live) { $log = $live.State.outLog }
    if (-not $log -or -not (Test-Path $log)) {
        $latest = Get-ChildItem $Script:LogDir -Filter '*.out.log' -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $log = $latest.FullName }
    }
    if (-not $log -or -not (Test-Path $log)) {
        Write-Info '还没有日志文件（尚未启动过 GUI）。'
        Write-Hint '先用 [1] / [2] 启动一次 GUI，这里就有东西看了。'
        return (Pause-Any)
    }

    # 同批 stderr：.out.log → .err.log（不用 ChangeExtension，那会变成 .out.err.log）
    $errPath = $log
    if ($errPath.EndsWith('.out.log')) {
        $errPath = $errPath.Substring(0, $errPath.Length - '.out.log'.Length) + '.err.log'
    }

    $item = Get-Item $log
    Write-Info "日志：$log"
    Write-Host ''

    # 第三方噪声可以无限刷，查看日志时别被超大文件拖死
    if ($item.Length -gt 32MB) {
        Write-Warn2 ("文件已达 {0} MB，太大，只显示开头与结尾各 40 行。" -f [Math]::Round($item.Length / 1MB, 1))
        Write-Hint '建议用 [5] → [6] 清理日志，或停掉 GUI 后重开。'
        Write-Host ''
        Show-LogLines -Lines @(Get-Content $log -Encoding UTF8 -TotalCount 40 -ErrorAction SilentlyContinue) -FirstNumber 1
        Write-Host ''
        Write-Hint '……（中间省略）'
        Show-LogLines -Lines @(Get-Content $log -Encoding UTF8 -Tail 40 -ErrorAction SilentlyContinue)
        return (Pause-Any)
    }

    $all = @(Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) {
        Write-Hint '（文件是空的：dsh web 启动后还没打印过任何东西）'
        return (Pause-Any)
    }

    $patterns = @(Get-LogNoisePatterns)
    $worth = New-Object System.Collections.ArrayList
    $noiseCount = 0
    $no = 0
    foreach ($line in $all) {
        $no++
        $isNoise = $false
        foreach ($p in $patterns) { if ($line -match $p) { $isNoise = $true; break } }
        if ($isNoise) { $noiseCount++ } else { [void]$worth.Add([pscustomobject]@{ No = $no; Text = $line }) }
    }

    Write-Host ("  大小 {0} KB · 共 {1} 行 · 创建 {2} · 最后写入 {3}" -f `
        [Math]::Round($item.Length / 1KB, 1), $all.Count, `
        $item.CreationTime.ToString('MM-dd HH:mm:ss'), $item.LastWriteTime.ToString('MM-dd HH:mm:ss')) -ForegroundColor Gray
    if ($noiseCount -gt 0) {
        Write-Host ("  构成：值得看 {0} 行 · 第三方噪声 {1} 行（占 {2}%）" -f `
            $worth.Count, $noiseCount, [Math]::Round(100 * $noiseCount / $all.Count)) -ForegroundColor Gray
    }
    if (Test-Path $errPath) {
        $errLen = (Get-Item $errPath).Length
        if ($errLen -gt 0) {
            Write-Host ("  同批 stderr（.err.log）：$errLen 字节 —— 有内容，值得看一眼") -ForegroundColor Yellow
        } else {
            Write-Host '  同批 stderr（.err.log）：0 字节（正常）' -ForegroundColor Gray
        }
    }

    Write-Host ''
    Write-Host ("  ── 值得看的行（共 {0} 行，最多显示 20 行）" -f $worth.Count) -ForegroundColor White
    if ($worth.Count -eq 0) {
        Write-Hint '没有。这份日志除了噪声就是空的 —— 正常运行时就是如此。'
    } else {
        foreach ($w in ($worth | Select-Object -First 20)) {
            Write-Host ("    {0,5}  {1}" -f $w.No, (Get-MaskedUrl -Url $w.Text)) -ForegroundColor Gray
        }
        if ($worth.Count -gt 20) {
            Write-Hint "…… 另外还有 $($worth.Count - 20) 行，用下面的 [3] 搜索关键词去找。"
        }
    }

    Write-Host ''
    Write-Host '  ── 尾部 40 行（连续重复已折叠）' -ForegroundColor White
    Show-LogLines -Lines @($all | Select-Object -Last 40) -Collapse

    Write-Host ''
    Write-Hint '它是 dsh web 的 stdout 重定向：正常运行时通常只有开头两行启动信息，'
    Write-Hint '其余可能是第三方程序借道写入的噪声。真正有用的时候是【启动失败】，'
    Write-Hint '失败原因写在这里，stderr 的原因写在同名 .err.log 里。'
    Write-Hint '历史对话与工具调用不在这个文件里。'

    while ($true) {
        Write-Host ''
        Write-Host '    [1] 原始尾部 40 行   [2] 文件开头 20 行   [3] 搜索关键词   [0] 返回' -ForegroundColor White
        $c = Read-Host '  请选择'
        if ($c -eq '1') {
            Write-Host ''
            Show-LogLines -Lines @($all | Select-Object -Last 40) -FirstNumber ([Math]::Max(1, $all.Count - 39))
            [void](Pause-Any)
        } elseif ($c -eq '2') {
            Write-Host ''
            Show-LogLines -Lines @($all | Select-Object -First 20) -FirstNumber 1
            [void](Pause-Any)
        } elseif ($c -eq '3') {
            $kw = Read-Host '  关键词（按字面匹配，不区分大小写）'
            Write-Host ''
            if ([string]::IsNullOrWhiteSpace($kw)) {
                Write-Info '没有输入关键词。'
            } else {
                $hit = 0
                $idx = 0
                foreach ($line in $all) {
                    $idx++
                    if ($line.IndexOf($kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        Write-Host ("    {0,5}  {1}" -f $idx, (Get-MaskedUrl -Url $line)) -ForegroundColor Gray
                        $hit++
                        if ($hit -ge 30) { Write-Hint '…… 只显示前 30 条匹配。'; break }
                    }
                }
                if ($hit -eq 0) { Write-Info "没有匹配「$kw」的行。" } else { Write-Info "已显示 $hit 条匹配。" }
            }
            [void](Pause-Any)
        } elseif ($c -eq '0' -or [string]::IsNullOrWhiteSpace($c)) {
            return
        } else {
            Write-Warn2 "无效选项：$c"
            Start-Sleep -Milliseconds 600
        }
    }
}

function Clear-Logs {
    <#
      [5] → [6] 清理日志文件 —— 本菜单里唯一会删东西的项（另一个是 [4] 停进程）。

      删除范围 = .dsh-launcher\logs\ 下【所有扩展名为 .log 的文件】。界面上会先按
      命名分类统计，再列出实际文件名给用户核对，然后才问 y/N。四类文件：
        web-<stamp>.out.log                            每次启动 GUI 一份（dsh web 的 stdout）
        web-<stamp>.err.log                            与上一条配对（dsh web 的 stderr，正常 0 字节）
        gui-restart-<stamp>.log                        外部 GUI 重启助手的日志
        gui-restart-<stamp>.launcher-<n>.out/.err.log  重启助手重定向下来的启动器输出

      明确不删（原样保留）：
        state.json、.gitignore
        logs\*.preflight.txt        （只按 *.log 过滤，.txt 不匹配）
        logs\ 之外的任何文件         restart-gui.ps1、restart-stdin.txt、*.bak

      流程：列出将要删除的文件 → 说明不会删什么 → 点名运行中实例正占用的那两个
      → 提示可能含 token 与路径 → [y/N] 二次确认 → 逐个删除并分别计数。
      运行中的实例持有自己那份日志的句柄，那两个通常删不掉；此时只把它们单列出来
      提示、其余照删，不再像以前那样整批中断（与 docs/security.md 的「运行中的实例，它的日志
      洗不掉」是同一个原因）。删日志本身不会影响 GUI 运行。
    #>
    Write-Section '清理日志'

    $logs = @(Get-ChildItem $Script:LogDir -Filter '*.log' -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($logs.Count -eq 0) {
        Write-Info '没有日志文件需要清理。'
        Write-Hint "目录：$($Script:LogDir)"
        Pause-Any
        return
    }

    $totalKB = [Math]::Round((($logs | Measure-Object Length -Sum).Sum / 1KB), 1)
    Write-Info "目录：$($Script:LogDir)"
    Write-Info "共找到 $($logs.Count) 个 .log 文件，合计 $totalKB KB。"
    Write-Host ''
    Write-Host '  将要删除的文件（logs\ 下全部 .log）：' -ForegroundColor White

    # 分类统计：顺序即优先级，先匹配更具体的模式；每个文件只归入第一类
    $kinds = @(
        @{ Pat = 'gui-restart-*.launcher-*.out.log'; Name = 'gui-restart-*.launcher-*.out.log'; Desc = '重启助手重定向下来的启动器输出' }
        @{ Pat = 'gui-restart-*.launcher-*.err.log'; Name = 'gui-restart-*.launcher-*.err.log'; Desc = '同上（stderr）' }
        @{ Pat = 'gui-restart-*.log';                Name = 'gui-restart-<时间戳>.log';        Desc = '外部 GUI 重启助手的日志' }
        @{ Pat = 'web-*.out.log';                    Name = 'web-<时间戳>.out.log';            Desc = 'dsh web 的 stdout，每次启动 GUI 一份' }
        @{ Pat = 'web-*.err.log';                    Name = 'web-<时间戳>.err.log';            Desc = 'dsh web 的 stderr，与上一条配对（正常 0 字节）' }
        @{ Pat = '*';                                Name = '其他 *.log';                      Desc = '不属于以上命名模式' }
    )
    $claimed = @{}
    foreach ($k in $kinds) {
        $hit = @($logs | Where-Object { ($_.Name -like $k.Pat) -and (-not $claimed.ContainsKey($_.Name)) })
        if ($hit.Count -eq 0) { continue }
        foreach ($h in $hit) { $claimed[$h.Name] = $true }
        $kb = [Math]::Round((($hit | Measure-Object Length -Sum).Sum / 1KB), 1)
        Write-Host ("    {0} —— {1} 个 · {2} KB" -f $k.Name, $hit.Count, $kb) -ForegroundColor Gray
        Write-Host ("        {0}" -f $k.Desc) -ForegroundColor DarkGray
    }

    Write-Host ''
    $maxList = 20
    if ($logs.Count -le $maxList) {
        Write-Host "  实际文件（$($logs.Count) 个）：" -ForegroundColor White
    } else {
        Write-Host "  实际文件（共 $($logs.Count) 个，只列前 $maxList 个）：" -ForegroundColor White
    }
    foreach ($f in ($logs | Select-Object -First $maxList)) {
        $fkb = [Math]::Round(($f.Length / 1KB), 1)
        Write-Host ("    {0,-44} {1,7} KB" -f $f.Name, $fkb) -ForegroundColor DarkGray
    }
    if ($logs.Count -gt $maxList) {
        Write-Hint "…… 以及另外 $($logs.Count - $maxList) 个，同样会被删除。"
    }

    Write-Host ''
    Write-Hint '不会删除：state.json、.gitignore、*.preflight.txt，以及 logs\ 之外的任何文件。'

    # 运行中实例正持有的日志通常删不掉，提前点名，免得用户以为清理失败
    $live = Get-LiveGuiState
    $busy = @()
    if ($live) {
        foreach ($p in @($live.State.outLog, $live.State.errLog)) {
            if (-not $p) { continue }
            foreach ($f in $logs) { if ($f.FullName -eq $p) { $busy += $f.Name } }
        }
    }
    if ($busy.Count -gt 0) {
        Write-Host ''
        Write-Warn2 "运行中的实例（PID $($live.State.pid)）正在写这两个文件："
        foreach ($n in $busy) { Write-Hint $n }
        Write-Hint '它们被进程占用，通常删不掉；其余照删，不影响 GUI 运行。'
    }

    Write-Host ''
    Write-Hint '日志可能包含 token、项目路径等信息。'
    $ans = Read-Host '  全部删除？[y/N]'
    if ($ans -match '^[Yy]') {
        $ok = 0
        $failed = @()
        foreach ($f in $logs) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $ok++
            } catch {
                $failed += $f.Name
            }
        }
        if ($ok -gt 0) { Write-Ok "已删除 $ok 个日志文件。" }
        if ($failed.Count -gt 0) {
            Write-Warn2 "$($failed.Count) 个文件删不掉（正被运行中的进程占用）："
            foreach ($n in $failed) { Write-Hint $n }
            Write-Hint '停掉 GUI（[5] → [4]）之后再清理一次即可。'
        }
    } else {
        Write-Info '已取消。'
    }
    Pause-Any
}

function Show-ManageMenu {
    while ($true) {
        Clear-Screen
        Write-Banner
        Write-Section '环境自检与进程管理'

        $live = Get-LiveGuiState
        if ($live) {
            Write-Host ''
            Write-Host "  当前状态：运行中 · PID $($live.State.pid) · 端口 $($live.State.port)" -ForegroundColor Green
        } else {
            Write-Host ''
            Write-Host '  当前状态：无运行中的 GUI' -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host '    [1] 运行环境自检' -ForegroundColor White
        Write-Host '    [2] 修复 / 重新安装 dsh（npx 重新拉取）' -ForegroundColor White
        Write-Host '    [3] 查看运行中的 GUI' -ForegroundColor White
        Write-Host '    [4] 停止运行中的 GUI' -ForegroundColor White
        Write-Host '    [5] 查看 GUI 日志（摘要 + 关键行）' -ForegroundColor White
        Write-Host '    [6] 清理日志文件' -ForegroundColor White
        Write-Host '    [0] 返回主菜单' -ForegroundColor DarkGray
        Write-Host ''

        $c = Read-Host '  请选择'
        switch ($c) {
            '1' { [void](Invoke-SelfCheck) }
            '2' { [void](Repair-Dsh) }
            '3' { [void](Show-RunningGui) }
            '4' { [void](Stop-GuiInteractive) }
            '5' { [void](Show-GuiLog) }
            '6' { [void](Clear-Logs) }
            '0' { return }
            ''  { return }
            default { Write-Host ''; Write-Warn2 "无效选项：$c"; Start-Sleep -Milliseconds 700 }
        }
    }
}

# ─────────────────────────────── 主菜单 ───────────────────────────────

function Show-MainMenu {
    Clear-Screen
    Write-Banner

    $live = Get-LiveGuiState
    if ($live) {
        Write-Host ''
        Write-Host "  ● Web UI 运行中 · PID $($live.State.pid) · 端口 $($live.State.port)" -ForegroundColor Green
        # token 一律掩码：完整地址只在 [8] 里按需显示
        Write-Host "    http://127.0.0.1:$($live.State.port)/?token=••••••••   （完整地址见 [8]）" -ForegroundColor DarkGray
    } else {
        Write-Host ''
        Write-Host '  ○ 当前没有运行中的 Web UI' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '    [1] 启动 Web UI（默认，自动打开浏览器）' -ForegroundColor White
    Write-Host '    [2] 启动 Web UI（不自动打开浏览器）' -ForegroundColor White
    Write-Host '    [3] 查看当前安装版本' -ForegroundColor White
    Write-Host '    [4] 查看最新可用版本' -ForegroundColor White
    Write-Host '    [5] 环境自检与进程管理' -ForegroundColor White
    Write-Host '    [6] 打开工作目录' -ForegroundColor White
    Write-Host '    [7] 打开官方网址' -ForegroundColor White
    Write-Host '    [8] 查看访问地址与 Token' -ForegroundColor White
    Write-Host '    [0] 退出启动器' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host "  工作目录：$($Script:DefaultWorkspace)" -ForegroundColor DarkGray
}

function Open-WorkspaceFolder {
    $ws = $Script:DefaultWorkspace
    if (-not (Test-Path $ws)) {
        Write-Bad "目录不存在：$ws"
        Pause-Any
        return
    }
    try {
        Start-Process explorer.exe -ArgumentList "`"$ws`""
        Write-Info "已在资源管理器中打开：$ws"
    } catch {
        Write-Bad "打开失败：$($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 500
}

function Open-Docs {
    while ($true) {
        Clear-Screen
        Write-Banner
        Write-Section '官方文档'
        Write-Host ''
        for ($i = 0; $i -lt $Script:OfficialLinks.Count; $i++) {
            $link = $Script:OfficialLinks[$i]
            Write-Host ("    [{0}] {1}" -f ($i + 1), $link.Title) -ForegroundColor White
            Write-Host "        $($link.Url)" -ForegroundColor DarkGray
        }
        Write-Host '    [0] 返回' -ForegroundColor DarkGray
        Write-Host ''
        $c = Read-Host '  请选择要打开的链接'

        $idx = 0
        if ([int]::TryParse($c, [ref]$idx) -and $idx -ge 1 -and $idx -le $Script:OfficialLinks.Count) {
            $url = $Script:OfficialLinks[$idx - 1].Url
            try {
                Start-Process $url | Out-Null
                Write-Info "已交给默认浏览器：$url"
            } catch { Write-Bad "打开失败：$($_.Exception.Message)" }
            Start-Sleep -Milliseconds 500
        }
        else {
            return   # 0 / 空回车 / 非法输入：返回主菜单
        }
    }
}

function Invoke-Action {
    <#
      执行一个菜单项。所有子动作的输出都用 [void] 抑制，
      保证本函数只返回一个布尔值给主循环。
    #>
    param([string]$Key)

    if ([string]::IsNullOrWhiteSpace($Key)) { return $true }   # 空回车：静默重绘菜单

    switch ($Key) {
        '1' { [void](Invoke-LaunchWeb -NoOpen:$false) }
        '2' { [void](Invoke-LaunchWeb -NoOpen:$true) }
        '3' { [void](Show-CurrentVersion) }
        '4' { [void](Show-LatestVersion) }
        '5' { [void](Show-ManageMenu) }
        '6' { [void](Open-WorkspaceFolder) }
        '7' { [void](Open-Docs) }
        '8' { [void](Show-AccessInfo) }
        default { return $false }
    }
    return $true
}

# ─────────────────────────────── 入口 ───────────────────────────────

Initialize-DataDir

if ($SelfTest) {
    Write-Banner
    Invoke-SelfCheck -Quiet | Out-Null
    exit 0
}

if ($Action) {
    [void](Invoke-Action -Key $Action)
    exit 0
}

$emptyStreak = 0
while ($true) {
    Show-MainMenu
    $choice = Read-Host '  请选择'

    # stdin 已结束时 Read-Host 会立刻返回空值；不设上限会变成空转刷屏
    if ([string]::IsNullOrWhiteSpace($choice)) {
        if (++$emptyStreak -ge 3) {
            Write-Host ''
            Write-Info '连续收到空输入（stdin 可能已结束），启动器退出。'
            exit 0
        }
        continue
    }
    $emptyStreak = 0

    if ($choice -eq '0') {
        Write-Host ''
        $live = Get-LiveGuiState
        if ($live) {
            Write-Host "  Web UI 仍在后台运行（PID $($live.State.pid)）。" -ForegroundColor DarkGray
            Write-Host '  访问地址请重开启动器后用 [8] 查看，避免凭据留在屏幕上。' -ForegroundColor DarkGray
        }
        Write-Host '  再见。' -ForegroundColor Cyan
        Write-Host ''
        exit 0
    }

    $handled = Invoke-Action -Key $choice
    if (-not $handled) {
        Write-Host ''
        Write-Warn2 "无效选项：$choice"
        Start-Sleep -Milliseconds 800
    }
}
