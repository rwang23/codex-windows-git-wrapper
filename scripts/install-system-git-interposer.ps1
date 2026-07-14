[CmdletBinding()]
param(
    [string]$GitCmdPath,
    [string]$RealGit,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin"),
    [string]$BackupDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin\system-git-interposer-backup"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-Sha256 {
    param([string]$Path)

    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Copy-FileWithRetry {
    param(
        [string]$Source,
        [string]$Destination,
        [int]$Attempts = 80,
        [int]$DelayMilliseconds = 250
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            Copy-Item -LiteralPath $Source -Destination $Destination -Force
            return
        }
        catch [System.IO.IOException] {
            $lastError = $_
            if ($attempt -lt $Attempts) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }
        }
    }

    throw "Could not replace $Destination after $Attempts attempts because it remained in use: $($lastError.Exception.Message)"
}

function Assert-ForwardedGitVersion {
    param([string]$Path)

    $stdout = Join-Path $env:TEMP "codex-git-interposer-$([System.IO.Path]::GetRandomFileName()).out"
    $stderr = Join-Path $env:TEMP "codex-git-interposer-$([System.IO.Path]::GetRandomFileName()).err"
    try {
        $process = Start-Process -FilePath $Path -ArgumentList "--version" -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $stdoutText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
        $stderrText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
        if ($process.ExitCode -ne 0 -or $stdoutText -notmatch '^git version ') {
            $details = @($stdoutText, $stderrText) | Where-Object { $_ } | ForEach-Object { $_.Trim() }
            throw "The interposed Git dispatcher could not run the real Git executable. Exit code: $($process.ExitCode). Output: $($details -join ' | ')"
        }
    }
    finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-GitCmdDispatcher {
    param(
        [string]$RequestedPath,
        [string]$WrapperInstallDir
    )

    if ($RequestedPath) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            throw "The provided -GitCmdPath does not exist: $RequestedPath"
        }
        $resolved = (Resolve-Path -LiteralPath $RequestedPath).Path
        if ($resolved -notmatch '[\\/]cmd[\\/]git\.exe$') {
            throw "-GitCmdPath must point to Git for Windows cmd\git.exe: $resolved"
        }
        return $resolved
    }

    $codexRuntimeRoot = Join-Path $env:USERPROFILE ".cache\codex-runtimes"
    $codexAppRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex"
    $candidates = Get-Command git.exe -All -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Source -and
            $_.Source -match '[\\/]Git[\\/]cmd[\\/]git\.exe$' -and
            $_.Source -notlike "$WrapperInstallDir*" -and
            $_.Source -notlike "$codexRuntimeRoot*" -and
            $_.Source -notlike "$codexAppRoot*"
        }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate.Source -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate.Source).Path
        }
    }

    foreach ($candidate in @(
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files (x86)\Git\cmd\git.exe"
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Could not find Git for Windows cmd\git.exe. Pass -GitCmdPath with its full path."
}

function Resolve-DirectGit {
    param(
        [string]$RequestedRealGit,
        [string]$DispatcherPath
    )

    if ($RequestedRealGit) {
        if (-not (Test-Path -LiteralPath $RequestedRealGit -PathType Leaf)) {
            throw "The provided -RealGit path does not exist: $RequestedRealGit"
        }
        return (Resolve-Path -LiteralPath $RequestedRealGit).Path
    }

    $gitRoot = Split-Path -Parent (Split-Path -Parent $DispatcherPath)
    $directGit = Join-Path $gitRoot "mingw64\bin\git.exe"
    if (-not (Test-Path -LiteralPath $directGit -PathType Leaf)) {
        throw "Could not derive Git for Windows mingw64\bin\git.exe from $DispatcherPath. Pass -RealGit explicitly."
    }

    return (Resolve-Path -LiteralPath $directGit).Path
}

function Write-InterposerState {
    param(
        [string]$Path,
        [pscustomobject]$State
    )

    $State | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$wrapperPath = Join-Path $InstallDir "git.exe"
if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) {
    throw "The Git wrapper is missing: $wrapperPath. Run scripts\install.ps1 first."
}

$targetPath = Resolve-GitCmdDispatcher -RequestedPath $GitCmdPath -WrapperInstallDir $InstallDir
$realGitPath = Resolve-DirectGit -RequestedRealGit $RealGit -DispatcherPath $targetPath
if ($targetPath -eq $realGitPath) {
    throw "The dispatcher and direct Git paths must be different: $targetPath"
}

$targetDirectory = Split-Path -Parent $targetPath
$targetConfigPath = Join-Path $targetDirectory "real-git.txt"
$statePath = Join-Path $InstallDir "system-git-interposer-state.json"
$backupGitPath = Join-Path $BackupDir "git.exe.original"
$backupConfigPath = Join-Path $BackupDir "real-git.txt.original"
$wrapperHash = Get-Sha256 -Path $wrapperPath

if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.TargetPath -ne $targetPath) {
        throw "An interposer state file already targets a different Git dispatcher: $($state.TargetPath). Roll it back before installing another one."
    }

    $currentHash = Get-Sha256 -Path $targetPath
    if ($currentHash -ne $state.WrapperSha256) {
        if (-not $Force) {
            throw "The Git dispatcher changed after the interposer was installed. Refusing to overwrite it. Review the Git update, then rerun with -Force only if you want to create a fresh backup from the current dispatcher."
        }

        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
        Copy-Item -LiteralPath $targetPath -Destination (Join-Path $BackupDir "git.exe.pre-reapply-$timestamp") -Force
        if (Test-Path -LiteralPath $targetConfigPath -PathType Leaf) {
            Copy-Item -LiteralPath $targetConfigPath -Destination (Join-Path $BackupDir "real-git.txt.pre-reapply-$timestamp") -Force
        }
        $state.OriginalSha256 = $currentHash
        $state.OriginalConfigExists = [bool](Test-Path -LiteralPath $targetConfigPath -PathType Leaf)
        Copy-Item -LiteralPath $targetPath -Destination $backupGitPath -Force
        if ($state.OriginalConfigExists) {
            Copy-Item -LiteralPath $targetConfigPath -Destination $backupConfigPath -Force
        } elseif (Test-Path -LiteralPath $backupConfigPath) {
            Remove-Item -LiteralPath $backupConfigPath -Force
        }
    }
} else {
    $state = $null
    $currentHash = Get-Sha256 -Path $targetPath
    if ($currentHash -eq $wrapperHash) {
        throw "The target Git dispatcher already matches the wrapper, but no rollback state exists. Refusing to treat the wrapper as the original Git executable."
    }
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    Copy-Item -LiteralPath $targetPath -Destination $backupGitPath -Force
    if ((Get-Sha256 -Path $backupGitPath) -ne $currentHash) {
        throw "The backup copy did not match the original Git dispatcher. No replacement was attempted."
    }
    $originalConfigExists = Test-Path -LiteralPath $targetConfigPath -PathType Leaf
    if ($originalConfigExists) {
        Copy-Item -LiteralPath $targetConfigPath -Destination $backupConfigPath -Force
    }
    $state = [pscustomobject]@{
        SchemaVersion = 1
        TargetPath = $targetPath
        RealGitPath = $realGitPath
        WrapperPath = $wrapperPath
        WrapperSha256 = $wrapperHash
        OriginalSha256 = $currentHash
        OriginalConfigExists = [bool]$originalConfigExists
        InstalledAtUtc = [DateTime]::UtcNow.ToString("o")
    }
}

try {
    # Write the target before replacing cmd\git.exe so a concurrently started
    # Codex Git command can never see the wrapper without a real Git target.
    Set-Content -LiteralPath $targetConfigPath -Value $realGitPath -Encoding ASCII
    Copy-FileWithRetry -Source $wrapperPath -Destination $targetPath
    if ((Get-Sha256 -Path $targetPath) -ne $wrapperHash) {
        throw "The replacement Git dispatcher hash does not match the wrapper."
    }

    Assert-ForwardedGitVersion -Path $targetPath

    $state.RealGitPath = $realGitPath
    $state.WrapperPath = $wrapperPath
    $state.WrapperSha256 = $wrapperHash
    $state.InstalledAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-InterposerState -Path $statePath -State $state
}
catch {
    $installError = $_
    try {
        if (Test-Path -LiteralPath $backupGitPath -PathType Leaf) {
            Copy-FileWithRetry -Source $backupGitPath -Destination $targetPath
        }
        if ($state.OriginalConfigExists -and (Test-Path -LiteralPath $backupConfigPath -PathType Leaf)) {
            Copy-Item -LiteralPath $backupConfigPath -Destination $targetConfigPath -Force
        } elseif (Test-Path -LiteralPath $targetConfigPath -PathType Leaf) {
            Remove-Item -LiteralPath $targetConfigPath -Force
        }
    }
    catch {
        throw "Interposer installation failed: $($installError.Exception.Message). Automatic rollback also failed: $($_.Exception.Message). The original backup is at $backupGitPath"
    }
    throw "Interposer installation failed and the original Git dispatcher was restored: $($installError.Exception.Message)"
}

Write-Output "Installed the direct Git interposer."
Write-Output "Dispatcher: $targetPath"
Write-Output "Real Git:   $realGitPath"
Write-Output "Backup:     $backupGitPath"
Write-Output "Rollback:   powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\remove-system-git-interposer.ps1`""
