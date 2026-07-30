param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    if ($RequestedPath -and (Test-Path $RequestedPath)) {
        return (Resolve-Path $RequestedPath).Path
    }

    $commandCandidates = @(
        "godot",
        "godot4",
        "Godot_v4.6.3-stable_win64_console.exe",
        "Godot_v4.6.3-stable_win64.exe"
    )

    foreach ($candidate in $commandCandidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            return $command.Source
        }
    }

    $localCandidates = @(
        (Join-Path $ProjectRoot "Godot_v4.6.3-stable_win64_console.exe"),
        (Join-Path $ProjectRoot "Godot_v4.6.3-stable_win64.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.6.3-stable_win64_console.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.6.3-stable_win64.exe")
    )

    foreach ($candidate in $localCandidates) {
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw @"
Godot 실행 파일을 찾지 못했습니다.
다음처럼 경로를 직접 전달하세요.

    .\tools\run_all_tests.ps1 -GodotPath "C:\경로\Godot_v4.6.3-stable_win64_console.exe"
"@
}

function Invoke-GodotCheck {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    & $script:GodotExecutable @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Name 실패: 종료 코드 $LASTEXITCODE"
    }
}

$script:GodotExecutable = Resolve-GodotExecutable $GodotPath
Write-Host "Godot: $script:GodotExecutable" -ForegroundColor DarkGray
Write-Host "Project: $ProjectRoot" -ForegroundColor DarkGray

Invoke-GodotCheck "프로젝트 파싱" @(
    "--headless",
    "--editor",
    "--path", $ProjectRoot,
    "--quit"
)

$testScripts = @(
    "res://tests/presentation_refactor_test_runner.gd",
    "res://tests/readable_boundaries_test_runner.gd",
    "res://tests/world_test_runner.gd",
    "res://tests/governance_rebellion_test_runner.gd",
    "res://tests/main_runtime_test_runner.gd"
)

foreach ($testScript in $testScripts) {
    Invoke-GodotCheck $testScript @(
        "--headless",
        "--path", $ProjectRoot,
        "--script", $testScript
    )
}

Write-Host ""
Write-Host "모든 Project Epoch 검증을 통과했습니다." -ForegroundColor Green
