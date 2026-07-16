$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configureScript = Join-Path $repoRoot "scripts\configure-codex-temp.ps1"
$guardTestRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin\guard-tests"
$testRoot = Join-Path $guardTestRoot "codex-temp-test-$PID"
$installDir = Join-Path $testRoot "wrapper-bin"
$originalTemp = Join-Path $testRoot "original-temp"
$newTemp = Join-Path $testRoot "new-temp"
$configPath = Join-Path $installDir "codex-temp-dir.txt"
$backupPath = Join-Path $installDir "codex-temp-dir.backup.txt"

if (-not (Test-Path -LiteralPath $configureScript -PathType Leaf)) {
    throw "Codex temporary-directory configuration script is missing: $configureScript"
}

try {
    New-Item -ItemType Directory -Force -Path $installDir, $originalTemp | Out-Null
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($configPath, ($originalTemp + [Environment]::NewLine), $encoding)

    & $configureScript -Mode Enable -TempDir $newTemp -InstallDir $installDir
    if (-not (Test-Path -LiteralPath $newTemp -PathType Container)) {
        throw "The requested Codex temporary directory was not created."
    }
    if (([IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8).Trim()) -ne $newTemp) {
        throw "The Codex temporary-directory configuration was not written."
    }
    if (([IO.File]::ReadAllText($backupPath, [Text.Encoding]::UTF8).Trim()) -ne $originalTemp) {
        throw "The previous Codex temporary-directory configuration was not backed up."
    }

    & $configureScript -Mode Enable -TempDir $newTemp -InstallDir $installDir
    & $configureScript -Mode Disable -InstallDir $installDir
    if (([IO.File]::ReadAllText($configPath, [Text.Encoding]::UTF8).Trim()) -ne $originalTemp) {
        throw "The previous Codex temporary-directory configuration was not restored."
    }
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        throw "The temporary-directory backup remained after restore."
    }

    Remove-Item -LiteralPath $configPath -Force
    & $configureScript -Mode Enable -TempDir $newTemp -InstallDir $installDir
    & $configureScript -Mode Disable -InstallDir $installDir
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        throw "The Codex temporary-directory configuration was not removed when no previous configuration existed."
    }
    if (-not (Test-Path -LiteralPath $newTemp -PathType Container)) {
        throw "Disabling the configuration unexpectedly removed the temporary directory."
    }

    Write-Output "Codex temporary-directory regression checks: PASS"
}
finally {
    if ($testRoot -notlike "$(Join-Path $guardTestRoot 'codex-temp-test-*')") {
        throw "Refusing to remove an unexpected test path: $testRoot"
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
