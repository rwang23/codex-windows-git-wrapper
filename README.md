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

The wrapper target Git path is supplied by:

1. `CODEX_REAL_GIT` environment variable set by the launcher.
2. `real-git.txt` in the wrapper install directory.
3. Common Git for Windows install paths as a fallback.

## What This Does Not Do

- It does not replace your installed Git.
- It does not modify `C:\Program Files\Git`, `D:\Software\Git`, or any other Git install directory.
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

