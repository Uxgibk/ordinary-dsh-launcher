@echo off
goto :launcher
rem ============================================================================
rem  ordinary dsh launcher - 双击入口
rem
rem  【本文件只是入口】所有逻辑和界面文字都在同目录的 ordinary-dsh-launcher.ps1。
rem  名字 / 版本 / 副标题也只在那个 .ps1 最上方定义，本文件不重复写。
rem
rem  ---------------------------------------------------------------------------
rem  .dsh-launcher\ 是什么（第一次双击本文件后就会出现）
rem  ---------------------------------------------------------------------------
rem  那是【启动器自己的运行时数据目录】，不是 dsh 的，也不是你项目的。
rem  它随着使用不断变多属于正常现象，不是出错。整个文件夹随时可以删除，
rem  下次运行会自动重建（只会丢掉历史日志和「运行中 GUI」的识别）。
rem
rem  一定会出现的文件：
rem    .gitignore                    自动生成，让整个目录不被 git 追踪
rem    state.json                    当前 GUI 的 pid / 端口 / 访问地址（[8] 的数据来源）
rem    logs\web-[时间戳].out.log     每次启动 GUI 一份，dsh web 的 stdout
rem    logs\web-[时间戳].err.log     与上面配对，dsh web 的 stderr（正常是 0 字节）
rem
rem  可能会出现的文件（不是启动器生成的，来自外部重启助手或人工留档，删掉无影响）：
rem    logs\gui-restart-[时间戳].log
rem    logs\gui-restart-[时间戳].launcher-[序号].out.log / .err.log
rem    logs\gui-restart-[时间戳].preflight.txt
rem    restart-gui.ps1、restart-stdin.txt、*.bak
rem
rem  为什么会越攒越多：每点一次 [1] / [2] 启动 GUI，就会新开一对带时间戳的
rem  日志；旧的一律保留，不覆盖、不轮转、也不自动清理。
rem
rem  菜单 [5] 子菜单里和文件有关的两项：
rem    [5] 查看 GUI 日志   只读，不改任何文件。先报文件大小 / 行数 / 时间，并统计
rem                        「值得看的行」与第三方噪声各占多少，再单独列出值得看的
rem                        行（带行号），最后显示折叠掉连续重复的尾部；还有
rem                        [1] 原始尾部 / [2] 文件开头 / [3] 搜索关键词 三个入口。
rem                        全程 token 打码。
rem                        小提示：正常运行时这份日志基本只有开头两行启动信息，
rem                        它真正有用的时候是【启动失败】。
rem    [6] 清理日志文件    删除 logs\ 下的【所有 .log】。界面上会先按类型统计，
rem                        再列出每个实际文件名让你核对，最后才问 y/N。它会删：
rem                          web-[时间戳].out.log / web-[时间戳].err.log
rem                          gui-restart-[时间戳].log
rem                          gui-restart-[时间戳].launcher-[序号].out.log / .err.log
rem                        不会删 state.json、.gitignore、*.preflight.txt，
rem                        也不会动 logs\ 之外的任何文件。
rem  [5] / [6] 的逐文件说明，另见 .ps1 里 Show-GuiLog 与 Clear-Logs 的注释。
rem
rem  安全提醒：.dsh-launcher\ 里存着访问凭据（token）。分享给别人之前先删掉它，
rem  详见 docs/security.md 的「安全说明（重要）」。
rem
rem  ---------------------------------------------------------------------------
rem  Portability / encoding notes (see docs/data-and-files.md):
rem   - Everything is resolved relative to THIS file (%~dp0), so the launcher
rem     folder can be moved anywhere.
rem   - The script is looked up by this file's base name first, then as the only
rem     .ps1 next to it, so either file may be renamed.
rem   - This .cmd must stay UTF-8 WITHOUT BOM, with CRLF line endings, and the
rem     notes above must stay behind the "goto :launcher" jump below.
rem     Reason: cmd.exe loses sync while parsing multi-byte text in batch
rem     comments and starts "running" fragments of them (verified: 8-18 bogus
rem     "is not recognized" lines per run). Skipped lines are never parsed, so
rem     the notes are safe there. Do not add a BOM (it breaks "@echo off"),
rem     do not re-save as GBK, and do not convert this file to LF-only.
rem   - "chcp 65001" runs after the jump, so the GUI text the .ps1 prints still
rem     renders as UTF-8.
rem ============================================================================
:launcher
rem The "goto :launcher" above is deliberate -- see the encoding note it skipped.
setlocal enableextensions
chcp 65001 >nul 2>&1
rem Provisional title until the .ps1 sets "name vversion" from its identity block
title %~n0

rem Preferred: same base name as this .cmd (ordinary-dsh-launcher.ps1)
set "SCRIPT=%~dp0%~n0.ps1"

rem Fallback: the single .ps1 sitting next to this .cmd (allows renaming)
if not exist "%SCRIPT%" (
    set "SCRIPT="
    for %%F in ("%~dp0*.ps1") do (
        if not defined SCRIPT set "SCRIPT=%%~fF"
    )
)

if not defined SCRIPT (
    echo [ERROR] No .ps1 script found next to this launcher.
    echo         Expected: "%~dp0%~n0.ps1"
    echo         Put the launcher .ps1 next to this .cmd and retry.
    echo.
    pause
    exit /b 1
)

rem Prefer PowerShell 7 (pwsh), fall back to Windows PowerShell 5.1
set "PSEXE=pwsh.exe"
where pwsh.exe >nul 2>&1 || set "PSEXE=powershell.exe"

where %PSEXE% >nul 2>&1
if errorlevel 1 (
    echo [ERROR] No PowerShell interpreter found on PATH.
    echo         Install PowerShell 7, or enable Windows PowerShell.
    echo.
    pause
    exit /b 1
)

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo [Launcher exited with code %RC%]
    pause
)

endlocal & exit /b %RC%
