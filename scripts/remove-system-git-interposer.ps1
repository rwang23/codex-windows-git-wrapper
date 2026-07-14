[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin"),
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

    throw "Could not restore $Destination after $Attempts attempts because it remained in use: $($lastError.Exception.Message)"
}

$statePath = Join-Path $InstallDir "system-git-interposer-state.json"
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "No direct Git interposer state was found at $statePath. Nothing was changed."
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$targetPath = [string]$state.TargetPath
$targetDirectory = Split-Path -Parent $targetPath
$targetConfigPath = Join-Path $targetDirectory "real-git.txt"
$backupDir = Join-Path $InstallDir "system-git-interposer-backup"
$backupGitPath = Join-Path $backupDir "git.exe.original"
$backupConfigPath = Join-Path $backupDir "real-git.txt.original"

if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
    throw "The interposed Git dispatcher is missing: $targetPath. The original backup remains at $backupGitPath"
}
if (-not (Test-Path -LiteralPath $backupGitPath -PathType Leaf)) {
    throw "The original Git backup is missing: $backupGitPath. Refusing to change $targetPath."
}

$currentHash = Get-Sha256 -Path $targetPath
if ($currentHash -ne $state.WrapperSha256 -and -not $Force) {
    throw "The Git dispatcher no longer matches the installed wrapper. Refusing to overwrite it. Use -Force only after confirming that restoring the saved original Git is intended."
}
if ((Get-Sha256 -Path $backupGitPath) -ne $state.OriginalSha256) {
    throw "The original Git backup hash does not match the recorded state. Refusing to restore it."
}

Copy-FileWithRetry -Source $backupGitPath -Destination $targetPath
if ((Get-Sha256 -Path $targetPath) -ne $state.OriginalSha256) {
    throw "The restored Git dispatcher hash does not match the original backup. The backup remains at $backupGitPath"
}

if ($state.OriginalConfigExists) {
    if (-not (Test-Path -LiteralPath $backupConfigPath -PathType Leaf)) {
        throw "The original real-git.txt backup is missing: $backupConfigPath"
    }
    Copy-Item -LiteralPath $backupConfigPath -Destination $targetConfigPath -Force
} elseif (Test-Path -LiteralPath $targetConfigPath -PathType Leaf) {
    Remove-Item -LiteralPath $targetConfigPath -Force
}

Remove-Item -LiteralPath $statePath -Force
Write-Output "Restored the original Git dispatcher: $targetPath"
Write-Output "The rollback backup was retained at: $backupGitPath"
