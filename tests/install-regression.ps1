$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installScript = Join-Path $repoRoot "scripts\install.ps1"
$testInstall = Join-Path $env:TEMP "codex-wrapper-install-test-$PID"
$realGit = (Get-Command git.exe -All -CommandType Application | Where-Object Source -NotLike "*codex-git-wrapper*" | Select-Object -First 1).Source
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
    & $installScript -InstallDir $testInstall -RealGit $realGit -RealPowerShell $realPowerShell

    $gitWrapper = Join-Path $testInstall "git.exe"
    $powerShellWrapper = Join-Path $testInstall "powershell.exe"
    if (-not (Test-Path -LiteralPath $gitWrapper)) {
        throw "Git wrapper was not installed."
    }
    if (-not (Test-Path -LiteralPath $powerShellWrapper)) {
        throw "PowerShell wrapper was not installed."
    }

    $gitResult = Invoke-Wrapper -FilePath $gitWrapper -ArgumentList @("--version")
    if ($gitResult.ExitCode -ne 0 -or $gitResult.Stdout -notmatch '^git version ') {
        throw "Git wrapper did not forward correctly: $($gitResult.Stdout) $($gitResult.Stderr)"
    }

    $powerShellResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", "Write-Output 'wrapper-powershell-ok'")
    if ($powerShellResult.ExitCode -ne 0 -or $powerShellResult.Stdout -ne "wrapper-powershell-ok") {
        throw "PowerShell wrapper did not forward correctly: $($powerShellResult.Stdout) $($powerShellResult.Stderr)"
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
    Remove-Item -LiteralPath $testInstall -Recurse -Force -ErrorAction SilentlyContinue
}
