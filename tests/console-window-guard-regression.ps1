$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installScript = Join-Path $repoRoot "scripts\install.ps1"
$fixtureSource = Join-Path $PSScriptRoot "FakeChatGptGitHost.cs"
$fakeGitSource = Join-Path $PSScriptRoot "FakeGit.cs"
$guardTestRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin\guard-tests"
$testRoot = Join-Path $guardTestRoot "codex-console-window-guard-test-$PID"
$installDir = Join-Path $testRoot "wrapper-bin"
$fakeChatGpt = Join-Path $testRoot "ChatGPT.exe"
$fakeCodex = Join-Path $testRoot "Codex.exe"
$fakeGit = Join-Path $testRoot "Git\cmd\git.exe"
$activeGuard = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin\codex-console-window-guard.exe"
$existingGuards = @(Get-Process -Name "codex-console-window-guard" -ErrorAction SilentlyContinue)
$restartExistingGuard = $existingGuards.Count -gt 0
if ($restartExistingGuard) {
    $existingGuards | Stop-Process -Force
}

function Find-Csc {
    foreach ($candidate in @(
        (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "csc.exe was not available for the console window guard regression test."
}

function Invoke-GuardFixture {
    param(
        [string]$GuardPath,
        [string]$HostPath,
        [string]$HostName,
        [string]$GitPath
    )

    $guardProcess = Start-Process -FilePath $GuardPath -ArgumentList "--once" -PassThru
    try {
        Start-Sleep -Milliseconds 300
        $hostProcess = Start-Process -FilePath $HostPath -ArgumentList @($GitPath) -PassThru
        if (-not $guardProcess.WaitForExit(6000)) {
            throw "The console window guard did not detect the simulated $HostName-to-Git console window."
        }
        if ($guardProcess.ExitCode -ne 0) {
            throw "The console window guard exited with code $($guardProcess.ExitCode)."
        }
        $hostProcess.WaitForExit()
    }
    finally {
        if (-not $guardProcess.HasExited) {
            $guardProcess.Kill()
            $guardProcess.WaitForExit()
        }
        $guardProcess.Dispose()
    }
}

try {
    if (-not (Test-Path -LiteralPath $fixtureSource) -or -not (Test-Path -LiteralPath $fakeGitSource)) {
        throw "Guard test fixture is missing."
    }

    & $installScript -InstallDir $installDir
    $guard = Join-Path $installDir "codex-console-window-guard.exe"
    if (-not (Test-Path -LiteralPath $guard)) {
        Write-Warning "Console window guard regression skipped because no native compiler was available."
        exit 0
    }

    $selfTestProcess = Start-Process -FilePath $guard -ArgumentList "--self-test-process-graph" -PassThru
    try {
        if (-not $selfTestProcess.WaitForExit(6000)) {
            throw "The console window guard process-graph self-test timed out."
        }
        if ($selfTestProcess.ExitCode -ne 0) {
            throw "The console window guard process-graph self-test failed with exit code $($selfTestProcess.ExitCode)."
        }
    }
    finally {
        if (-not $selfTestProcess.HasExited) {
            $selfTestProcess.Kill()
            $selfTestProcess.WaitForExit()
        }
        $selfTestProcess.Dispose()
    }

    $csc = Find-Csc
    & $csc /nologo /target:winexe /optimize+ /out:$fakeChatGpt $fixtureSource
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fakeChatGpt)) {
        throw "Could not compile the ChatGPT/Git guard fixture."
    }
    Copy-Item -LiteralPath $fakeChatGpt -Destination $fakeCodex
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fakeGit) | Out-Null
    & $csc /nologo /target:winexe /optimize+ /out:$fakeGit $fakeGitSource
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $fakeGit)) {
        throw "Could not compile the Git console fixture."
    }

    Invoke-GuardFixture -GuardPath $guard -HostPath $fakeChatGpt -HostName "ChatGPT" -GitPath $fakeGit
    Invoke-GuardFixture -GuardPath $guard -HostPath $fakeCodex -HostName "Codex" -GitPath $fakeGit

    Write-Output "Console window guard regression checks: PASS"
}
finally {
    if ($testRoot -notlike "$(Join-Path $guardTestRoot 'codex-console-window-guard-test-*')") {
        throw "Refusing to remove an unexpected test path: $testRoot"
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    if ($restartExistingGuard -and (Test-Path -LiteralPath $activeGuard)) {
        Start-Process -FilePath $activeGuard -ErrorAction SilentlyContinue
    }
}
