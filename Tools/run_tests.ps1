# Tools/run_tests.ps1
# Executes Unity UTF EditMode tests in headless batchmode.
param(
    [string]$UnityPath,
    [string]$ProjectPath = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$ResultsPath,
    [string]$LogFile
)

$ErrorActionPreference = "Stop"

if (-not $ResultsPath) {
    $ResultsPath = Join-Path $ProjectPath "Builds\tests.xml"
}
if (-not $LogFile) {
    $LogFile = Join-Path $ProjectPath "Builds\tests.log"
}

# Locate Unity executable if not explicitly provided
if (-not $UnityPath) {
    $candidates = @(
        "C:\Unity\6000.6.0f1\Editor\Unity.exe",
        "C:\Unity\Hub\Editor\6000.6.0f1\Editor\Unity.exe",
        "C:\Program Files\Unity\Hub\Editor\6000.6.0f1\Editor\Unity.exe",
        "$env:LOCALAPPDATA\Programs\Unity\6000.6.0f1\Editor\Unity.exe",
        "$env:USERPROFILE\Unity\Hub\Editor\6000.6.0f1\Editor\Unity.exe"
    )
    if ($env:UNITY -and (Test-Path $env:UNITY)) {
        $UnityPath = $env:UNITY
    } else {
        foreach ($cand in $candidates) {
            if (Test-Path $cand) {
                $UnityPath = $cand
                break
            }
        }
    }
}

if (-not $UnityPath -or -not (Test-Path $UnityPath)) {
    Write-Error "Unity executable not found. Provide -UnityPath pointing to Unity 6000.6.0f1 Editor\Unity.exe."
    exit 1
}

Write-Host "== Project Path: $ProjectPath"
Write-Host "== Unity Path:   $UnityPath"
Write-Host "== Results File: $ResultsPath"
Write-Host "== Log File:     $LogFile"

# Ensure output directory exists
$buildsDir = Split-Path -Parent $ResultsPath
if (-not (Test-Path $buildsDir)) {
    New-Item -ItemType Directory -Path $buildsDir -Force | Out-Null
}

# Clean stale project lockfile
$lockFile = Join-Path $ProjectPath "Temp\UnityLockfile"
if (Test-Path $lockFile) {
    Write-Warning "Removing stale lockfile at $lockFile"
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

# Remove existing results file to prevent stale reports
if (Test-Path $ResultsPath) {
    Remove-Item $ResultsPath -Force -ErrorAction SilentlyContinue
}

Write-Host "== Executing UTF EditMode tests..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Notice: UTF handles its own shutdown. Do NOT pass -quit with -runTests.
$proc = Start-Process -FilePath $UnityPath -ArgumentList @(
    "-batchmode",
    "-projectPath", "`"$ProjectPath`"",
    "-runTests",
    "-testPlatform", "EditMode",
    "-testResults", "`"$ResultsPath`"",
    "-logFile", "`"$LogFile`""
) -Wait -PassThru -NoNewWindow

$sw.Stop()
Write-Host "== Test process exited with code $($proc.ExitCode) in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"

if (-not (Test-Path $ResultsPath)) {
    Write-Error "Tests did not produce results XML file at $ResultsPath. Inspect $LogFile for details."
    if (Test-Path $LogFile) {
        Write-Host "== Tail of $LogFile =="
        Get-Content $LogFile -Tail 30
    }
    exit 1
}

# Parse NUnit 3 Test Results
[xml]$xml = Get-Content $ResultsPath
$total = [int]$xml.'test-run'.total
$passed = [int]$xml.'test-run'.passed
$failed = [int]$xml.'test-run'.failed
$skipped = [int]$xml.'test-run'.skipped

Write-Host "========================================"
Write-Host "  TEST RESULTS: Total=$total Passed=$passed Failed=$failed Skipped=$skipped"
Write-Host "========================================"

if ($failed -gt 0) {
    Write-Host "== FAILED TEST CASES ==" -ForegroundColor Red
    $failedCases = $xml.SelectNodes("//test-case[@result='Failed']")
    foreach ($case in $failedCases) {
        $name = $case.GetAttribute("fullname")
        $failNode = $case.SelectSingleNode("failure/message")
        $msg = if ($failNode) { $failNode.InnerText } else { $null }
        Write-Host "## $name" -ForegroundColor Red
        if ($msg) {
            Write-Host "   $($msg.Trim())" -ForegroundColor DarkRed
        }
    }
    exit 1
}

Write-Host "All EditMode tests passed successfully!" -ForegroundColor Green
exit 0
