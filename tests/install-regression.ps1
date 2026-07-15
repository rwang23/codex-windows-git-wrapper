$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installScript = Join-Path $repoRoot "scripts\install.ps1"
$guardTestRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin\guard-tests"
$testInstall = Join-Path $guardTestRoot "codex-wrapper-install-test-$PID"
$realGit = (Get-Command git.exe -All -CommandType Application | Where-Object {
    $_.Source -notlike "*codex-git-wrapper*" -and
    $_.Source -notlike "*$([IO.Path]::DirectorySeparatorChar).cache$([IO.Path]::DirectorySeparatorChar)codex-runtimes*" -and
    $_.Source -notlike "*$([IO.Path]::DirectorySeparatorChar)AppData$([IO.Path]::DirectorySeparatorChar)Local$([IO.Path]::DirectorySeparatorChar)OpenAI$([IO.Path]::DirectorySeparatorChar)Codex*"
} | Select-Object -First 1).Source
if (-not $realGit) {
    throw "No non-Codex Git installation was available for the install regression test."
}
$realPowerShell = (Get-Command powershell.exe -All -CommandType Application | Where-Object Source -NotLike "*codex-git-wrapper*" | Select-Object -First 1).Source

function Invoke-Wrapper {
    param([string]$FilePath, [string[]]$ArgumentList)

    $stdout = Join-Path $testInstall "$([System.IO.Path]::GetRandomFileName()).out"
    $stderr = Join-Path $testInstall "$([System.IO.Path]::GetRandomFileName()).err"
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $stdoutText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
    $stderrText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = if ($null -eq $stdoutText) { "" } else { $stdoutText.Trim() }
        Stderr = if ($null -eq $stderrText) { "" } else { $stderrText.Trim() }
    }
}

try {
    & $installScript -InstallDir $testInstall -RealPowerShell $realPowerShell

    $gitWrapper = Join-Path $testInstall "git.exe"
    $powerShellWrapper = Join-Path $testInstall "powershell.exe"
    $cmdWrapper = Join-Path $testInstall "cmd.exe"
    $consoleWindowGuard = Join-Path $testInstall "codex-console-window-guard.exe"
    if (-not (Test-Path -LiteralPath $gitWrapper)) {
        throw "Git wrapper was not installed."
    }
    if (-not (Test-Path -LiteralPath $powerShellWrapper)) {
        throw "PowerShell wrapper was not installed."
    }
    if (-not (Test-Path -LiteralPath $cmdWrapper)) {
        throw "Command Prompt wrapper was not installed."
    }
    $buildKind = (Get-Content -LiteralPath (Join-Path $testInstall 'wrapper-kind.txt') -Raw).Trim()
    if ($buildKind -like 'native-*' -and -not (Test-Path -LiteralPath $consoleWindowGuard)) {
        throw "Console window guard was not installed with the native wrapper build."
    }

    $configuredGit = (Get-Content -LiteralPath (Join-Path $testInstall 'real-git.txt') -Raw).Trim()
    $expectedGit = $realGit
    if ($realGit -match '[\\/]cmd[\\/]git\.exe$') {
        $directGit = Join-Path (Split-Path -Parent (Split-Path -Parent $realGit)) 'mingw64\bin\git.exe'
        if (Test-Path -LiteralPath $directGit) {
            $expectedGit = (Resolve-Path -LiteralPath $directGit).Path
        }
    }
    if ($configuredGit -ne $expectedGit) {
        throw "Installer did not select the direct Git executable. Expected: $expectedGit; Actual: $configuredGit"
    }
    if ($configuredGit -like "*$([IO.Path]::DirectorySeparatorChar).cache$([IO.Path]::DirectorySeparatorChar)codex-runtimes*") {
        throw "Installer selected Codex's private runtime Git instead of the user's Git installation: $configuredGit"
    }

    $gitResult = Invoke-Wrapper -FilePath $gitWrapper -ArgumentList @("--version")
    if ($gitResult.ExitCode -ne 0 -or $gitResult.Stdout -notmatch '^git version ') {
        throw "Git wrapper did not forward correctly: $($gitResult.Stdout) $($gitResult.Stderr)"
    }

    $powerShellResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", "Write-Output 'wrapper-powershell-ok'")
    if ($powerShellResult.ExitCode -ne 0 -or $powerShellResult.Stdout -ne "wrapper-powershell-ok") {
        throw "PowerShell wrapper did not forward correctly: $($powerShellResult.Stdout) $($powerShellResult.Stderr)"
    }

    $cmdResult = Invoke-Wrapper -FilePath $cmdWrapper -ArgumentList @("/d", "/s", "/c", "echo wrapper-cmd-ok")
    if ($cmdResult.ExitCode -ne 0 -or $cmdResult.Stdout -ne "wrapper-cmd-ok") {
        throw "Command Prompt wrapper did not forward correctly: $($cmdResult.Stdout) $($cmdResult.Stderr)"
    }

    $sampleCommand = "`$ErrorActionPreference = 'Stop'; Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId | ConvertTo-Json -Depth 2"
    $quotedSample = '"' + $sampleCommand.Replace('"', '\"') + '"'
    $env:CODEX_WRAPPER_SUPPRESS_PROCESS_SAMPLING = "1"
    try {
        $samplingResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", $quotedSample)
    } finally {
        Remove-Item Env:CODEX_WRAPPER_SUPPRESS_PROCESS_SAMPLING -ErrorAction SilentlyContinue
    }
    if ($samplingResult.ExitCode -ne 0 -or $samplingResult.Stdout -ne "[]") {
        throw "Process sampling was not suppressed: $($samplingResult.Stdout) $($samplingResult.Stderr)"
    }

    Write-Output "Install regression checks: PASS"
}
finally {
    if ($testInstall -notlike "$(Join-Path $guardTestRoot 'codex-wrapper-install-test-*')") {
        throw "Refusing to remove an unexpected test path: $testInstall"
    }
    Remove-Item -LiteralPath $testInstall -Recurse -Force -ErrorAction SilentlyContinue
}
