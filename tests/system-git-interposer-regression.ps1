$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$wrapperInstallScript = Join-Path $repoRoot "scripts\install.ps1"
$interposerInstallScript = Join-Path $repoRoot "scripts\install-system-git-interposer.ps1"
$interposerRemoveScript = Join-Path $repoRoot "scripts\remove-system-git-interposer.ps1"
$standardRemoveScript = Join-Path $repoRoot "scripts\remove.ps1"
$testRoot = Join-Path $env:TEMP "codex-system-git-interposer-test-$PID"
$testInstall = Join-Path $testRoot "wrapper-bin"
$testDispatcher = Join-Path $testRoot "Git\cmd\git.exe"
$testConfig = Join-Path (Split-Path -Parent $testDispatcher) "real-git.txt"
$testBackup = Join-Path $testInstall "system-git-interposer-backup"

function Invoke-Executable {
    param([string]$FilePath, [string[]]$ArgumentList)

    $stdout = Join-Path $env:TEMP "codex-system-git-interposer-$([System.IO.Path]::GetRandomFileName()).out"
    $stderr = Join-Path $env:TEMP "codex-system-git-interposer-$([System.IO.Path]::GetRandomFileName()).err"
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
            Stderr = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
        }
    }
    finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

$gitCommands = Get-Command git.exe -All -CommandType Application -ErrorAction Stop |
    Where-Object {
        $_.Source -notlike "*codex-git-wrapper*" -and
        $_.Source -notlike "*$([IO.Path]::DirectorySeparatorChar).cache$([IO.Path]::DirectorySeparatorChar)codex-runtimes*" -and
        $_.Source -notlike "*$([IO.Path]::DirectorySeparatorChar)AppData$([IO.Path]::DirectorySeparatorChar)Local$([IO.Path]::DirectorySeparatorChar)OpenAI$([IO.Path]::DirectorySeparatorChar)Codex*"
    }
$realGit = ($gitCommands | Where-Object Source -Match '[\\/]mingw64[\\/]bin[\\/]git\.exe$' | Select-Object -First 1).Source
if (-not $realGit) {
    $gitDispatcher = ($gitCommands | Where-Object Source -Match '[\\/]Git[\\/]cmd[\\/]git\.exe$' | Select-Object -First 1).Source
    if ($gitDispatcher) {
        $realGit = Join-Path (Split-Path -Parent (Split-Path -Parent $gitDispatcher)) "mingw64\bin\git.exe"
    }
}
if (-not $realGit) {
    throw "No direct Git for Windows mingw64\bin\git.exe was available for the interposer regression test."
}
$realGit = (Resolve-Path -LiteralPath $realGit).Path

$realPowerShell = (Get-Command powershell.exe -All -CommandType Application -ErrorAction Stop |
    Where-Object Source -NotLike "*codex-git-wrapper*" |
    Select-Object -First 1).Source
if (-not $realPowerShell) {
    throw "No non-wrapper powershell.exe was available for the interposer regression test."
}

try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $testDispatcher) | Out-Null
    Copy-Item -LiteralPath $realGit -Destination $testDispatcher -Force
    $originalDispatcherHash = (Get-FileHash -LiteralPath $testDispatcher -Algorithm SHA256).Hash
    $originalConfig = "C:\before-test\git.exe"
    Set-Content -LiteralPath $testConfig -Value $originalConfig -Encoding ASCII

    & $wrapperInstallScript -InstallDir $testInstall -RealGit $realGit -RealPowerShell $realPowerShell

    & $interposerInstallScript -GitCmdPath $testDispatcher -RealGit $realGit -InstallDir $testInstall -BackupDir $testBackup

    $wrapperPath = Join-Path $testInstall "git.exe"
    $interposedHash = (Get-FileHash -LiteralPath $testDispatcher -Algorithm SHA256).Hash
    $wrapperHash = (Get-FileHash -LiteralPath $wrapperPath -Algorithm SHA256).Hash
    if ($interposedHash -ne $wrapperHash) {
        throw "The test Git dispatcher was not replaced by the wrapper."
    }

    $configuredRealGit = (Get-Content -LiteralPath $testConfig -Raw).Trim()
    if ($configuredRealGit -ne $realGit) {
        throw "The interposer did not configure the direct real Git target. Expected: $realGit; Actual: $configuredRealGit"
    }

    $version = Invoke-Executable -FilePath $testDispatcher -ArgumentList @("--version")
    if ($version.ExitCode -ne 0 -or $version.Stdout -notmatch '^git version ') {
        throw "The interposed dispatcher did not forward --version: $($version.Stdout) $($version.Stderr)"
    }

    $standardRemoveBlocked = $false
    try {
        & $standardRemoveScript -InstallDir $testInstall
    }
    catch {
        $standardRemoveBlocked = $true
    }
    if (-not $standardRemoveBlocked) {
        throw "The standard wrapper removal did not refuse while the direct interposer was active."
    }

    & $interposerRemoveScript -InstallDir $testInstall

    $restoredHash = (Get-FileHash -LiteralPath $testDispatcher -Algorithm SHA256).Hash
    if ($restoredHash -ne $originalDispatcherHash) {
        throw "The original test Git dispatcher hash was not restored."
    }
    $restoredConfig = (Get-Content -LiteralPath $testConfig -Raw).Trim()
    if ($restoredConfig -ne $originalConfig) {
        throw "The original real-git.txt content was not restored."
    }
    if (Test-Path -LiteralPath (Join-Path $testInstall "system-git-interposer-state.json")) {
        throw "The interposer state file remained after rollback."
    }

    $noConfigDispatcher = Join-Path $testRoot "GitNoConfig\cmd\git.exe"
    $noConfigPath = Join-Path (Split-Path -Parent $noConfigDispatcher) "real-git.txt"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $noConfigDispatcher) | Out-Null
    Copy-Item -LiteralPath $realGit -Destination $noConfigDispatcher -Force
    $noConfigOriginalHash = (Get-FileHash -LiteralPath $noConfigDispatcher -Algorithm SHA256).Hash

    & $interposerInstallScript -GitCmdPath $noConfigDispatcher -RealGit $realGit -InstallDir $testInstall -BackupDir $testBackup
    if (-not (Test-Path -LiteralPath $noConfigPath)) {
        throw "The interposer did not create real-git.txt for a dispatcher without an original configuration."
    }
    & $interposerRemoveScript -InstallDir $testInstall
    if (Test-Path -LiteralPath $noConfigPath) {
        throw "Rollback did not remove a real-git.txt that was absent before installation."
    }
    if ((Get-FileHash -LiteralPath $noConfigDispatcher -Algorithm SHA256).Hash -ne $noConfigOriginalHash) {
        throw "Rollback did not restore the dispatcher that had no original configuration."
    }

    Write-Output "System Git interposer regression checks: PASS"
}
finally {
    if ($testRoot -notlike "$(Join-Path $env:TEMP 'codex-system-git-interposer-test-*')") {
        throw "Refusing to remove an unexpected test path: $testRoot"
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
