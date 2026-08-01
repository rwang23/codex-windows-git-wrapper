# ChatGPT Codex Windows Guard

[English](README.md) | [简体中文](README.zh-CN.md)

这是一个仅适用于 **Windows** 的、可逆的本地兼容工具，用于缓解 ChatGPT Codex Desktop 工作时闪现的 `git.exe`、`powershell.exe`、`cmd.exe`、`conhost.exe`，以及空白的 Windows Terminal 窗口。

安装器还会在 process-local wrapper 目录旁创建一个简短的 `codexguard` 命令 shim。Codex 通过 Guard 启动后，日常统一使用 `codexguard check`、`codexguard repair`、`codexguard stop` 和 `codexguard launch`；脚本路径只作为首次引导或恢复时的备用入口。

它支持当前 Microsoft Store / MSIX 包中的 `ChatGPT.exe`，也兼容旧版 `Codex.exe`。它不是 macOS/Linux 工具，也不会替换真实 Git。若已安装 PowerShell 7，wrapper 只会在 Codex 启动的 `powershell.exe` 命令中优先转发到 `pwsh.exe`；系统 Windows PowerShell 5.1 保持不变。需要兼容旧脚本时，可通过 `-RealPowerShell` 显式固定到 5.1。

## 搜索关键词

`ChatGPT Codex Windows`、`Codex Windows 弹窗`、`Codex Git 弹窗`、`git.exe 闪现`、`PowerShell 弹窗`、`CMD 闪现`、`conhost.exe 闪现`、`Windows Terminal 空白窗口`、`Terminal 抢焦点`、`CASCADIA_HOSTING_WINDOW_CLASS` 和 `Codex 控制台窗口`。

如果遇到的是 Codex 高 CPU、反复 shell/进程活动、MCP 进程增长或桌面端闪退，应将其视为需要上游诊断的问题，而不代表本 guard 能修复 CPU 或闪退缺陷。

## 给 Codex / 编程 Agent 的最快安全路径

在让 Agent 处理问题前，可直接交给它以下说明：

```text
我在 Windows 上使用 ChatGPT Codex Desktop，出现 Git、PowerShell、CMD、conhost 或空白 Terminal 窗口闪现的问题。

请使用 https://github.com/rwang23/codex-windows-guard 作为可逆的、本地 Windows 兼容方案。

执行顺序：
1. 克隆到用户自行选择的本地目录；不要假定已有绝对路径。
2. 运行 scripts\install.ps1，再运行 scripts\status.ps1；报告检测到的桌面包、wrapper 状态、默认终端模式，以及最近的 guard 日志规则。
3. 如果是空白或抢焦点的 `Terminal` / `CASCADIA_HOSTING_WINDOW_CLASS` 窗口，且状态显示为 Automatic 或 Windows Terminal，先解释 Console Host 缓解方案；只有得到用户明确同意后才能应用。
4. 如果 guard 日志没有匹配规则，先捕获窗口归属/进程症状，再扩大方案；绝不能一概隐藏所有终端或所有控制台窗口。

安全边界：
- 不得替换、改名、修补或手工复制真实 Git 可执行文件。
- 不得修改系统 PATH、用户 PATH、用户 TEMP/TMP 或机器级 TEMP/TMP。
- 只有用户明确同意时，才能改动当前用户的两个默认终端委派注册表值；必须保留备份并给出恢复命令。
- 专用 TEMP 必须只作用于 wrapper 子进程、可以撤销，停用时不能删除其中已有文件。
- 只有用户明确同意重启 Codex 时，才能运行 scripts\setup-and-start.ps1。
- 绝不能在正在运行的 Codex 任务内执行带 `-Force` 的启动命令。
- 完成前必须给出外部 PowerShell 启动命令和 scripts\remove.ps1 回滚命令。
```

Agent 可以安装和验证文件；最终带 `-Force` 的重启命令应由用户在 **外部 PowerShell** 中运行，避免中断当前 Codex 任务。

## 已验证的 Windows Terminal 缓解路径

这个项目最初主要处理 Git 和 shell wrapper 的可见窗口。后来确认还有另一类症状：当 Windows 的默认终端是 **Automatic** 时，原本没有绑定终端的控制台 UI 可能被委派给 `WindowsTerminal.exe` / `OpenConsole.exe`。其顶层 `CASCADIA_HOSTING_WINDOW_CLASS` 窗口可能由 Windows 服务托管，而不是 Codex 的子进程。

因此，普通的进程祖先链 guard 无法安全地隐藏它们，否则可能误伤用户主动打开的 Windows Terminal。

在用于验证本项目的 Windows 环境中，明确选择 **Windows Console Host** 后，已观察到这类 brokered `Terminal` 闪窗停止出现。它是针对这一症状的、可逆的缓解手段，**不代表**它能修复全部 Codex 子进程、CPU、MCP 或闪退问题。

先查看当前模式：

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"
& (Join-Path $guardRepo "scripts\configure-default-terminal.ps1") -Mode Status
```

若显示 `Automatic` 或 `Windows Terminal`，且窗口标题为 `Terminal`、窗口类为 `CASCADIA_HOSTING_WINDOW_CLASS`，可在外部 PowerShell 中启用 Console Host：

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"
& (Join-Path $guardRepo "scripts\configure-default-terminal.ps1") -Mode ConsoleHost
```

它只改动当前用户 `HKCU\Console\%%Startup` 下的两个终端委派值；不会卸载或禁用 Windows Terminal，仍可手动打开。恢复原始值：

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"
& (Join-Path $guardRepo "scripts\configure-default-terminal.ps1") -Mode Restore
```

## 这个工具解决什么

Codex Desktop 有时会从 GUI / MSIX 进程启动 Git 或 PowerShell。Git for Windows 是控制台程序，因此可能闪出窗口。部分 Microsoft Store / MSIX 启动路径还可能绕过启动器的进程级 `PATH`。

本项目提供三层定向缓解：

1. 在用户本地 wrapper 目录中构建 `git.exe`、`powershell.exe`、`cmd.exe` 的 GUI wrapper；它们将参数、标准流和退出码转发给真实程序，同时不创建控制台窗口。
2. 在能编译原生 C++ 守卫时，监控并只隐藏明确归属于 Codex 的 Git/CMD/PowerShell/conhost、后端 helper 或 Chrome native-host bridge 窗口。
3. 对上述 brokered Windows Terminal 症状，选择可回滚的 Windows Console Host，而不是粗暴隐藏全部 `WindowsTerminal.exe`。

这个项目不会：

- 修改真实 Git、系统 PATH、用户 PATH，或 MSIX 包文件；
- 默认修改注册表；
- 修改用户/机器级 `TEMP` 或 `TMP`；
- 隐藏任意无关窗口；
- 降低 Codex 上游 Git 轮询频率、去重 MCP 进程池，或保证修复全部 CPU / 闪退问题。

## 安装

请在任意希望存放仓库的位置克隆。首次使用时只设置一次 `$guardRepo`，把它指向实际仓库目录；不要修改脚本内部的路径。

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"
# 如果仓库放在其他位置，只改上一行，例如：
# $guardRepo = "C:\your\actual\codex-windows-guard"
git clone https://github.com/rwang23/codex-windows-guard.git $guardRepo
& (Join-Path $guardRepo "scripts\install.ps1")
```

如果仓库已经克隆，跳过 `git clone`，把 `$guardRepo` 设置为现有仓库的绝对路径后运行安装器。以后如果移动仓库，也要重新运行安装器，让本地 `codexguard.cmd` shim 记录新的位置。

如果 Git 位于非标准路径，先查找：

```powershell
Get-Command git -All
```

再显式传入真实 Git：

```powershell
& (Join-Path $guardRepo "scripts\install.ps1") -RealGit "C:\Path\To\Git\mingw64\bin\git.exe"
```

安装器只在 `%LOCALAPPDATA%\OpenAI\Codex\wrapper-bin` 中记录真实 Git、PowerShell 和 CMD 路径，不会改动持久环境变量。

## 日常启动：一行命令，无需 `cd` 或 `git pull`

下面这条较长的脚本路径命令只用于首次引导或恢复。首次安装后，请从 **外部 PowerShell** 运行：

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"; & (Join-Path $guardRepo "scripts\codex-guard.ps1") launch -Force
```

如果仓库不在默认的用户目录，只需要把 `$guardRepo` 这一段替换为实际绝对路径。

`-Force` 会关闭当前正在运行的 ChatGPT/Codex Desktop 并重启。请先保存工作；不要在一个活跃 Codex 任务内运行它。

如果 Codex 已关闭，去掉 `-Force`：

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"; & (Join-Path $guardRepo "scripts\codex-guard.ps1") launch
```

## 统一 CodexGuard 指令

Codex 通过 Guard 启动后，日常操作直接使用短命令：

```powershell
codexguard check
codexguard repair
codexguard repair -Apply
codexguard stop
codexguard stop -Apply
codexguard launch
codexguard launch -Force
```

`check` 会合并安装状态和只读进程健康检查。`repair` 默认只预览；传入 `-Apply` 后，才会逐项处理健康检查已经识别出的 detached service root，默认还会逐项询问确认，非交互场景可同时使用 `-Force`。`stop` 默认只显示精确目标；传入 `-Apply` 后，只停止检测到的 Codex Desktop 和 Codex Windows Guard 进程，不会停止没有明确归属的 MCP、Node、浏览器、Docker 或项目开发服务器。`launch` 会自动转发 `-DisableShellSnapshot`、`-SuppressProcessSampling` 和 `-UseWindowsConsoleHost`。

shim 只通过 Guard 的进程级 PATH 提供，不修改用户或系统 PATH。`launch -Force` 会关闭并重启 Codex。请先保存工作，从外部 PowerShell 窗口运行 `launch`；不要在活跃 Codex 任务内运行。

## 可选开关

| 开关 | 适用症状 | 边界 / 代价 |
| --- | --- | --- |
| `-DisableShellSnapshot` | Codex 反复启动 PowerShell/conhost 用于 shell/process snapshot | 在 Codex 用户配置中关闭 `shell_snapshot`。 |
| `-SuppressProcessSampling` | 桌面进程采样造成高 CPU 或重复 PowerShell/CIM | 桌面端的进程 CPU/元数据视图可能不完整。 |
| `-UseWindowsConsoleHost` | 空白、抢焦点的 `Terminal` 窗口 | 只改当前用户默认控制台 host；Windows Terminal 仍可手动使用，原值会备份。 |
| `-TempDir "C:\CodexTemp"` | 公共 TEMP 拥挤，wrapper 启动的命令变慢 | 只影响 Codex wrapper 子进程；不全局迁移 Windows TEMP/TMP。 |

## 专用 Codex TEMP

若公共 `%TEMP%` 累积了大量临时文件，Git、PowerShell、CMD 等 wrapper 子进程可能在创建、扫描或清理文件时变慢。建议使用 SSD/NVMe 上的目录：

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"
& (Join-Path $guardRepo "scripts\configure-codex-temp.ps1") -Mode Enable -TempDir "C:\CodexTemp"
```

它只对 Codex wrapper 启动的 `git.exe`、`powershell.exe`、`cmd.exe` 及其子进程设置 `TEMP`/`TMP`；不改变用户或系统环境变量。停用但保留其中文件：

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"
& (Join-Path $guardRepo "scripts\configure-codex-temp.ps1") -Mode Disable
```

## 状态、更新与回滚

如果问题是多个长期任务下的 CPU、内存或 stdio/MCP 进程增长，请先阅读 [Codex Desktop Windows 性能诊断与优化运行手册](docs/codex-desktop-performance-runbook.zh-CN.md)。其中记录了本次 CodeGraph、Node REPL、MCP、pre-compact hook、BB Browser 与 Docker/WSL 调整的原理、升级后检查和回滚方式。

查看状态和只读健康信息：

```powershell
codexguard check
```

需要更新或修复安装时，再运行：

```powershell
codexguard launch -Force
```

完整回滚：关闭 Codex 后，在外部 PowerShell 运行：

```powershell
$guardRepo = Join-Path $env:USERPROFILE "codex-windows-guard"
& (Join-Path $guardRepo "scripts\configure-default-terminal.ps1") -Mode Restore
& (Join-Path $guardRepo "scripts\configure-codex-temp.ps1") -Mode Disable
& (Join-Path $guardRepo "scripts\remove.ps1")
```

## 验证与反馈

仓库包含针对 Windows 的回归测试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\install-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\launcher-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\console-window-guard-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\default-terminal-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\codex-temp-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\health-snapshot-regression.ps1
```

如需反馈问题，请附上桌面包版本、可见窗口/进程的具体症状，以及已脱敏的 `status.ps1` 输出；不要上传个人路径、账户信息或 token。

## 上游边界

该项目是 Windows 本地缓解方案。真正的上游修复仍应由 Codex 处理无窗口子进程启动、Git 轮询、MCP 进程生命周期、CPU 和闪退等问题。本工具会继续跟踪相关行为，但不宣称替代上游修复。
