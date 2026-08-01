<#
.SYNOPSIS
Provides one small command entry point for Codex Windows Guard.

.DESCRIPTION
The default check is read-only. Repair only considers detached service roots
reported by the existing read-only health snapshot and requires -Apply before
it can stop an exact process. Stop targets only the detected Codex Desktop and
Codex Windows Guard processes. Launch forwards the supported setup options and
never adds -Force unless the caller explicitly requests it.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("Check", "Repair", "Stop", "Launch", "Help")]
    [string]$Command = "Check",
    [switch]$Apply,
    [switch]$Force,
    [int[]]$ProcessId,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin"),
    [string]$TempDir,
    [string]$RealGit,
    [string]$RealPowerShell
)

$ErrorActionPreference = "Stop"
$scriptsDir = Split-Path -Parent $PSCommandPath
$statusScript = Join-Path $scriptsDir "status.ps1"
$healthSnapshotScript = Join-Path $scriptsDir "health-snapshot.ps1"
$setupScript = Join-Path $scriptsDir "setup-and-start.ps1"
$packageScript = Join-Path $scriptsDir "codex-package.ps1"

function Resolve-HostPowerShell {
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pwsh) {
        return $pwsh.Source
    }

    $windowsPowerShell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) {
        return $windowsPowerShell
    }

    throw "No PowerShell host was found for Codex Guard child scripts."
}

$hostPowerShell = Resolve-HostPowerShell

function Assert-RequiredScript {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required Codex Guard script was not found: $Path"
    }
}

function Invoke-ChildScript {
    param(
        [string]$Path,
        [string[]]$ArgumentList = @()
    )

    Assert-RequiredScript -Path $Path
    & $hostPowerShell -NoProfile -ExecutionPolicy Bypass -File $Path @ArgumentList
    $childSucceeded = $?
    $childExitCode = $LASTEXITCODE
    if (-not $childSucceeded -or ($null -ne $childExitCode -and $childExitCode -ne 0)) {
        throw "Codex Guard child command failed with exit code ${childExitCode}: $Path"
    }
}

function Get-HealthSnapshotObject {
    Assert-RequiredScript -Path $healthSnapshotScript
    $json = & $hostPowerShell -NoProfile -ExecutionPolicy Bypass -File $healthSnapshotScript -AsJson
    $childSucceeded = $?
    $childExitCode = $LASTEXITCODE
    if (-not $childSucceeded -or ($null -ne $childExitCode -and $childExitCode -ne 0)) {
        throw "Health snapshot failed with exit code ${childExitCode}."
    }

    $jsonText = ($json -join [Environment]::NewLine)
    if (-not $jsonText.Trim()) {
        throw "Health snapshot returned no JSON."
    }
    return ($jsonText | ConvertFrom-Json)
}

function Invoke-Check {
    Write-Output "Codex Guard check"
    Write-Output "================="
    Write-Output ""
    Write-Output "[installation and launcher status]"
    Invoke-ChildScript -Path $statusScript -ArgumentList @("-InstallDir", $InstallDir)
    Write-Output ""
    Write-Output "[read-only process health]"
    Invoke-ChildScript -Path $healthSnapshotScript
}

function Get-RepairCandidates {
    $snapshot = Get-HealthSnapshotObject
    return @($snapshot.DetachedCandidates | Where-Object {
        $_.Disposition -eq "review-candidate" -and
        ($null -eq $ProcessId -or $ProcessId -contains [int]$_.ProcessId)
    })
}

function Confirm-Action {
    param([string]$Message)

    if ($Force) {
        return $true
    }
    $answer = Read-Host "$Message [y/N]"
    return $answer -match "^(?i:y|yes)$"
}

function Invoke-Repair {
    $candidates = @(Get-RepairCandidates)
    Write-Output "Codex Guard repair candidates"
    Write-Output "============================="

    if ($candidates.Count -eq 0) {
        Write-Output "No detached Codex service candidates matched the requested scope."
        return
    }

    $candidates |
        Select-Object ProcessId, Kind, ParentProcessId, StartedAtUtc, PrivateMB, WorkingSetMB, Disposition |
        Format-Table -AutoSize |
        Out-String |
        Write-Output

    if (-not $Apply) {
        Write-Warning "Preview only. No process was changed. Rerun with -Apply to review exact candidates for stopping."
        return
    }

    foreach ($candidate in $candidates) {
        $candidatePid = [int]$candidate.ProcessId
        $current = Get-CimInstance Win32_Process -Filter "ProcessId = $candidatePid" -ErrorAction SilentlyContinue
        if (-not $current) {
            Write-Output "Skipping PID $candidatePid; it already exited."
            continue
        }

        $parentAlive = $false
        if ([int]$current.ParentProcessId -gt 0) {
            $parentAlive = $null -ne (Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$current.ParentProcessId)" -ErrorAction SilentlyContinue)
        }
        if ($parentAlive) {
            Write-Warning "Skipping PID $candidatePid; its parent is no longer detached. Re-run check before deciding."
            continue
        }

        if (-not (Confirm-Action -Message "Stop detached $($candidate.Kind) PID $candidatePid?")) {
            Write-Output "Kept PID $candidatePid."
            continue
        }

        Stop-Process -Id $candidatePid -Force -ErrorAction Stop
        Write-Output "Stopped detached $($candidate.Kind) PID $candidatePid."
    }
}

function Get-ManagedGuardProcesses {
    $guardPath = Join-Path $InstallDir "codex-console-window-guard.exe"
    return @(Get-Process -Name "codex-console-window-guard" -ErrorAction SilentlyContinue |
        Where-Object {
            try { $_.Path -eq $guardPath } catch { $false }
        })
}

function Invoke-Stop {
    Assert-RequiredScript -Path $packageScript
    . $packageScript

    $packageInfo = Resolve-CodexDesktopPackage
    $targets = [System.Collections.ArrayList]::new()

    foreach ($process in @(Get-RunningCodexDesktopProcesses -PackageInfo $packageInfo)) {
        [void]$targets.Add([pscustomobject]@{
            Id = [int]$process.Id
            Kind = "Codex Desktop"
            Path = [string]$process.Path
        })
    }
    foreach ($process in @(Get-ManagedGuardProcesses)) {
        [void]$targets.Add([pscustomobject]@{
            Id = [int]$process.Id
            Kind = "Codex Windows Guard"
            Path = [string]$process.Path
        })
    }

    Write-Output "Codex Guard stop targets"
    Write-Output "========================"
    if ($targets.Count -eq 0) {
        Write-Output "No managed Codex Desktop or Guard process was found."
        return
    }

    $targets | Format-Table -AutoSize | Out-String | Write-Output
    Write-Warning "This command does not stop unowned MCP, Node, browser, Docker, or project development processes."
    if (-not $Apply) {
        Write-Warning "Preview only. Rerun with -Apply to stop these exact targets."
        return
    }
    if (-not (Confirm-Action -Message "Stop the exact targets listed above?")) {
        Write-Output "No process was stopped."
        return
    }

    foreach ($target in $targets) {
        Stop-Process -Id $target.Id -Force -ErrorAction Stop
        Write-Output "Stopped $($target.Kind) PID $($target.Id)."
    }
}

function Invoke-Launch {
    if ($Apply) {
        throw "-Apply is not used with launch. Use -Force explicitly if Codex must be restarted."
    }

    $arguments = @(
        "-DisableShellSnapshot",
        "-SuppressProcessSampling",
        "-UseWindowsConsoleHost"
    )
    if ($TempDir) {
        $arguments += @("-TempDir", $TempDir)
    }
    if ($RealGit) {
        $arguments += @("-RealGit", $RealGit)
    }
    if ($RealPowerShell) {
        $arguments += @("-RealPowerShell", $RealPowerShell)
    }
    if ($Force) {
        $arguments += "-Force"
    }

    Write-Output "Launching Codex through Codex Windows Guard."
    Write-Output "Default switches: -DisableShellSnapshot -SuppressProcessSampling -UseWindowsConsoleHost"
    if ($Force) {
        Write-Warning "-Force will stop and restart Codex. Run this command from an external PowerShell window."
    }
    Invoke-ChildScript -Path $setupScript -ArgumentList @($arguments + @("-InstallDir", $InstallDir))
}

function Write-Help {
    @"
Codex Windows Guard command entry point

Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-guard.ps1 check
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-guard.ps1 repair
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-guard.ps1 repair -Apply
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-guard.ps1 stop
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-guard.ps1 stop -Apply
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-guard.ps1 launch
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex-guard.ps1 launch -Force

check  Read installation, Codex, MCP, Node REPL, and detached-service health.
repair Preview detached-service candidates; -Apply enables exact-process review.
stop   Preview exact Codex Desktop/Guard targets; -Apply stops those targets.
launch Start setup-and-start with the default Codex Guard switches.

Repair and stop never target arbitrary processes by name. The health snapshot
remains read-only; launch -Force must be run outside an active Codex task.
"@ | Write-Output
}

switch ($Command.ToLowerInvariant()) {
    "check" { Invoke-Check }
    "repair" { Invoke-Repair }
    "stop" { Invoke-Stop }
    "launch" { Invoke-Launch }
    "help" { Write-Help }
    default { Write-Help }
}
