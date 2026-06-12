# Codex Windows Git Wrapper

Temporary workaround for Windows Codex App users who see transient `git.exe` console windows flashing while Codex runs tasks.

This project is intentionally small and conservative. It does not patch Codex, replace Git, or change persistent system configuration. It only provides a launcher that starts Codex with a process-local `PATH` entry pointing to a small `git.exe` wrapper.

## Problem

On some Windows machines, the Codex desktop app repeatedly launches Git commands during task execution. Because Git for Windows `git.exe` is a console executable, a `git.exe` / console window may flash briefly if Codex starts it from a GUI process without hiding the console window.

Known related reports:

- <https://github.com/openai/codex/issues/24910>
- <https://github.com/openai/codex/issues/17229>
- <https://github.com/openai/codex/issues/20933>
- <https://github.com/openai/codex/issues/22085>

The upstream fix should come from Codex launching Git with the appropriate Windows no-console/no-window flags. This repository is only a local workaround.

## What This Does

The wrapper is a tiny Windows GUI executable named `git.exe`. When Codex invokes `git`, the wrapper starts your real Git executable with `CREATE_NO_WINDOW`, then waits for Git to exit and returns the same exit code.

When a native C++ compiler is available, the installer builds a native wrapper first. If no native compiler is available, it falls back to the managed C# wrapper.

The wrapper target Git path is supplied by:

1. `CODEX_REAL_GIT` environment variable set by the launcher.
2. `real-git.txt` in the wrapper install directory.
3. Common Git for Windows install paths as a fallback.

## What This Does Not Do

- It does not replace your installed Git.
- It does not modify your Git install directory.
- It does not modify system or user `PATH`.
- It does not modify the registry.
- It does not reduce Codex's Git polling frequency.

## Install

Clone the repository:

```powershell
git clone https://github.com/rwang23/codex-windows-git-wrapper.git
cd codex-windows-git-wrapper
```

Install the wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

The installer detects your real Git path with `Get-Command git -All`, excluding the wrapper install directory.

If your Git is installed somewhere custom, pass the path explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -RealGit "C:\Program Files\Git\cmd\git.exe"
```

Your path may be different. Check with:

```powershell
Get-Command git -All
```

## One Command Setup And Launch

If you already cloned this repository locally, run this from an external PowerShell window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -Force
```

Important: do not run the `-Force` command from inside an active Codex task. It closes existing Codex processes so the newly launched Codex process can inherit the wrapper environment.

If you want a clone-or-update command that works from any directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$repo = Join-Path $env:USERPROFILE 'codex-windows-git-wrapper'; if (!(Test-Path -LiteralPath $repo)) { git clone https://github.com/rwang23/codex-windows-git-wrapper.git $repo } else { git -C $repo pull --ff-only }; & (Join-Path $repo 'scripts\setup-and-start.ps1') -Force"
```

If Git is installed in a custom location, pass `-RealGit`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -RealGit "C:\Program Files\Git\cmd\git.exe" -Force
```

## For Codex / AI Agents

If you are using Codex or another AI coding agent, give it this prompt:

```text
I am on Windows and the Codex desktop app is flashing git.exe console windows during tasks.

Please install this temporary workaround:
https://github.com/rwang23/codex-windows-git-wrapper

Requirements:
- Do not replace or rename my real Git executable.
- Do not copy the wrapper into my Git installation directory.
- Do not modify system PATH or user PATH.
- Clone the repo locally.
- Run scripts\setup-and-start.ps1 only if I explicitly ask you to restart Codex.
- Otherwise run scripts\install.ps1.
- If Git auto-detection fails, run Get-Command git -All and pass the real Git path with -RealGit.
- Run scripts\status.ps1 and confirm persistent user/machine PATH do not contain codex-git-wrapper.
- Do not run scripts\setup-and-start.ps1 -Force or scripts\start-codex-with-git-wrapper.ps1 -Force from inside an active Codex task.
- Tell me the exact external PowerShell command I should run to start Codex with the wrapper.
- Tell me the exact remove command for rollback.
```

The agent should install and verify the workaround, then give you the external PowerShell command to start Codex. It should not run the `-Force` launcher from inside Codex, because that closes Codex and may interrupt the session.

## Start Codex With The Wrapper

Close Codex completely, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-codex-with-git-wrapper.ps1
```

If Codex is already running, the launcher refuses to continue because existing Codex processes keep their old environment and the wrapper will not apply.

To force-close existing Codex processes first:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-codex-with-git-wrapper.ps1 -Force
```

Do not run the `-Force` command from inside an active Codex task, because it will close Codex.

The combined install/check/start script is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -Force
```

## Check Status

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\status.ps1
```

This reports:

- Codex App version and install location.
- Wrapper install path.
- Configured real Git path.
- Current process Git resolution.
- Whether persistent user or machine `PATH` contains the wrapper.
- Running Codex processes.

## Troubleshooting fondue.exe / Windows Features

If a `Windows Features` window or `fondue.exe` appears after installing the wrapper, do not treat that as the normal fix path.

`fondue.exe` is a Windows component used for feature-on-demand prompts. In this workaround, it can appear if the managed wrapper crashes while Windows is loading the .NET runtime. One known trigger is a broken or unavailable current working directory inherited from a Codex process. Current wrapper source avoids reading `Environment.CurrentDirectory` before launching Git.

Recommended recovery:

```powershell
git pull --ff-only
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\status.ps1
```

Then close Codex completely and start it again with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-codex-with-git-wrapper.ps1
```

## Remove

Close Codex, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\remove.ps1
```

You can also restore normal behavior by closing Codex and launching it normally from the Start menu. The wrapper only applies to Codex processes started by `start-codex-with-git-wrapper.ps1`.

## Emergency Recovery

If something goes wrong, stop Codex and Git processes:

```powershell
taskkill /F /IM git.exe
taskkill /F /IM codex.exe
taskkill /F /IM Codex.exe
```

Then remove the wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\remove.ps1
```

No Git installation files need to be restored because this workaround never changes them.

## Notes

- Do not copy the wrapper into your Git installation directory.
- Do not rename or replace your real `git.exe`.
- Do not add the wrapper directory to persistent user or machine `PATH`.
- Remove this workaround after Codex fixes the Windows Git process launch behavior upstream.
