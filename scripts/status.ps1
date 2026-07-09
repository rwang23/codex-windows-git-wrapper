param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".codex\codex-git-wrapper")
)

$ErrorActionPreference = "Stop"

$wrapper = Join-Path $InstallDir "git.exe"
$config = Join-Path $InstallDir "real-git.txt"
$kindConfig = Join-Path $InstallDir "wrapper-kind.txt"
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
    if (Test-Path -LiteralPath $kindConfig) {
        Write-Output "  Build: $((Get-Content -LiteralPath $kindConfig -Raw).Trim())"
    } else {
        Write-Output "  Build: unknown"
    }
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
$git = Get-Command git -All -ErrorAction SilentlyContinue
if ($git) {
    $git | ForEach-Object { Write-Output "  $($_.Source)" }
} else {
    Write-Output "  git not found"
}

Write-Output ""
Write-Output "Codex CLI:"
$codex = Get-Command codex -All -ErrorAction SilentlyContinue
if ($codex) {
    $codex | ForEach-Object { Write-Output "  $($_.Source)" }
    try {
        Write-Output "  Version: $((& $codex[0].Source --version 2>$null).Trim())"
    } catch {
        Write-Output "  Version: unavailable"
    }
} else {
    Write-Output "  codex not found"
}

Write-Output ""
Write-Output "Codex shell_snapshot:"
$configPath = Join-Path $env:USERPROFILE ".codex\config.toml"
$featureLine = if (Test-Path -LiteralPath $configPath) {
    Select-String -LiteralPath $configPath -Pattern '^\s*shell_snapshot\s*=' -ErrorAction SilentlyContinue |
        Select-Object -Last 1
}
if ($featureLine) {
    Write-Output "  $($featureLine.Line.Trim())"
} else {
    Write-Output "  Not explicitly configured (Codex default may be enabled)"
}

Write-Output ""
Write-Output "Standalone CLI sandbox helpers:"
$helperNames = @("codex-command-runner.exe", "codex-windows-sandbox-setup.exe")
$npmHelperRoot = $null
if ($codex) {
    $npmHelperRoot = Join-Path (Split-Path $codex[0].Source -Parent) "node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc"
}
$helperRoots = @(
    (Join-Path $env:USERPROFILE ".codex\packages\standalone\current"),
    (Join-Path $env:LOCALAPPDATA "OpenAI\Codex"),
    $npmHelperRoot
)
$foundHelperRoot = $false
foreach ($helperRoot in ($helperRoots | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $helperRoot) {
        $foundHelperRoot = $true
        Write-Output "  Root: $helperRoot"
        foreach ($name in $helperNames) {
            $matches = Get-ChildItem -LiteralPath $helperRoot -Recurse -File -Filter $name -ErrorAction SilentlyContinue
            if ($matches) {
                $matches | ForEach-Object { Write-Output "    $($_.FullName)" }
            } else {
                Write-Output "    ${name}: missing"
            }
        }
    }
}
if (-not $foundHelperRoot) {
    Write-Output "  No standalone/npm helper root found"
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
