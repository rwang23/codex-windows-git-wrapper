param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".codex\codex-git-wrapper")
)

$ErrorActionPreference = "Stop"

$wrapper = Join-Path $InstallDir "git.exe"
$config = Join-Path $InstallDir "real-git.txt"
$package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1

Write-Output "Codex package:"
if ($package) {
    Write-Output "  Version: $($package.Version)"
    Write-Output "  Location: $($package.InstallLocation)"
} else {
    Write-Output "  Not found"
}

Write-Output ""
Write-Output "Git wrapper:"
if (Test-Path -LiteralPath $wrapper) {
    $item = Get-Item -LiteralPath $wrapper
    Write-Output "  Present: yes"
    Write-Output "  Path: $($item.FullName)"
    Write-Output "  LastWriteTime: $($item.LastWriteTime)"
} else {
    Write-Output "  Present: no"
}

Write-Output ""
Write-Output "Configured real Git:"
if (Test-Path -LiteralPath $config) {
    $realGit = (Get-Content -LiteralPath $config -Raw).Trim()
    Write-Output "  Path: $realGit"
    if ($realGit -and (Test-Path -LiteralPath $realGit)) {
        Write-Output "  Version: $(& $realGit --version)"
    } else {
        Write-Output "  Missing or invalid"
    }
} else {
    Write-Output "  Not configured"
}

Write-Output ""
Write-Output "Current process git resolution:"
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    Write-Output "  $($git.Source)"
} else {
    Write-Output "  git not found"
}

Write-Output ""
Write-Output "Persistent PATH checks:"
$userPathHasWrapper = ([Environment]::GetEnvironmentVariable("Path", "User") -split ";") |
    Where-Object { $_ -like "*codex-git-wrapper*" }
$machinePathHasWrapper = ([Environment]::GetEnvironmentVariable("Path", "Machine") -split ";") |
    Where-Object { $_ -like "*codex-git-wrapper*" }
Write-Output "  User PATH contains wrapper: $([bool]$userPathHasWrapper)"
Write-Output "  Machine PATH contains wrapper: $([bool]$machinePathHasWrapper)"

Write-Output ""
Write-Output "Running Codex processes:"
$runningCodex = Get-Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessName -in @("Codex", "codex") -and
        $_.Path -like "*OpenAI*Codex*"
    } |
    Select-Object Id, ProcessName, Path

if ($runningCodex) {
    $runningCodex | Format-Table -AutoSize | Out-String | Write-Output
} else {
    Write-Output "  None"
}

