# Tools/build_android.ps1
# Compiles the Android Release APK via ProjectBootstrap.StereoBuilder.BuildAndroid.
param(
    [string]$UnityPath,
    [string]$ProjectPath = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$OutputPath,
    [string]$LogFile,
    [switch]$Development,
    [string]$BundleId = "com.brenpoly.cardboardxr",
    [string]$Version,
    [string]$KeystorePath,
    [string]$KeystorePass,
    [string]$KeyAlias
)

$ErrorActionPreference = "Stop"

if (-not $OutputPath) {
    $OutputPath = Join-Path $ProjectPath "Builds\Android\CardboardXR.apk"
}
if (-not $LogFile) {
    $LogFile = Join-Path $ProjectPath "Builds\build.log"
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

# Locate OpenJDK 17
$unityDir = Split-Path -Parent (Split-Path -Parent $UnityPath)
$embeddedJdk = Join-Path $unityDir "Data\PlaybackEngines\AndroidPlayer\OpenJDK"
$hostJdk17 = "E:\Software\OpenJDK17U-jdk_x64_windows_hotspot_17.0.17_10\jdk-17.0.17+10"

if (Test-Path $embeddedJdk) {
    $env:JAVA_HOME = $embeddedJdk
} elseif (Test-Path $hostJdk17) {
    $env:JAVA_HOME = $hostJdk17
}

# Locate Android SDK and NDK
$embeddedSdk = Join-Path $unityDir "Data\PlaybackEngines\AndroidPlayer\SDK"
$embeddedNdk = Join-Path $unityDir "Data\PlaybackEngines\AndroidPlayer\NDK"

if (Test-Path $embeddedSdk) {
    $env:ANDROID_SDK_ROOT = $embeddedSdk
    $env:ANDROID_HOME = $embeddedSdk
} elseif (Test-Path "C:\Android") {
    $env:ANDROID_SDK_ROOT = "C:\Android"
    $env:ANDROID_HOME = "C:\Android"
}

if (Test-Path $embeddedNdk) {
    $env:ANDROID_NDK_ROOT = $embeddedNdk
    $env:NDK_ROOT = $embeddedNdk
} elseif (Test-Path "C:\Android\ndk") {
    $ndkDirs = Get-ChildItem -Path "C:\Android\ndk" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    if ($ndkDirs -and $ndkDirs.Count -gt 0) {
        $env:ANDROID_NDK_ROOT = $ndkDirs[0].FullName
        $env:NDK_ROOT = $ndkDirs[0].FullName
    }
}

Write-Host "== Project Path:  $ProjectPath"
Write-Host "== Unity Path:    $UnityPath"
Write-Host "== Output Target: $OutputPath"
Write-Host "== Build Log:     $LogFile"
Write-Host "== JAVA_HOME:     $env:JAVA_HOME"
Write-Host "== ANDROID_SDK:   $env:ANDROID_SDK_ROOT"
Write-Host "== ANDROID_NDK:   $env:ANDROID_NDK_ROOT"

# Ensure output directories exist
$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$logDir = Split-Path -Parent $LogFile
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Clean stale project lockfile
$lockFile = Join-Path $ProjectPath "Temp\UnityLockfile"
if (Test-Path $lockFile) {
    Write-Warning "Removing stale lockfile at $lockFile"
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

# Set build environment variables for StereoBuilder
$env:CARDBOARDXR_BUNDLE_ID = $BundleId
$env:CARDBOARDXR_DEVELOPMENT = if ($Development) { "1" } else { "0" }

if ($Version) {
    $env:CARDBOARDXR_VERSION = $Version
}
if ($KeystorePath) {
    $env:CARDBOARDXR_KEYSTORE = $KeystorePath
    $env:CARDBOARDXR_KEYSTORE_PASS = $KeystorePass
    if ($KeyAlias) { $env:CARDBOARDXR_KEY_ALIAS = $KeyAlias }
}

# Remove stale build log
if (Test-Path $LogFile) {
    Remove-Item $LogFile -Force -ErrorAction SilentlyContinue
}

Write-Host "== Compiling Android Release APK via ProjectBootstrap.StereoBuilder.BuildAndroid..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$proc = Start-Process -FilePath $UnityPath -ArgumentList @(
    "-batchmode",
    "-quit",
    "-projectPath", "`"$ProjectPath`"",
    "-buildTarget", "Android",
    "-executeMethod", "ProjectBootstrap.StereoBuilder.BuildAndroid",
    "-logFile", "`"$LogFile`""
) -Wait -PassThru -NoNewWindow

$sw.Stop()
Write-Host "== Build process exited with code $($proc.ExitCode) in $([math]::Round($sw.Elapsed.TotalSeconds, 1))s"

# Locate produced APK (StereoBuilder outputs to Builds/CardboardXR.apk by default)
$defaultApk = Join-Path $ProjectPath "Builds\CardboardXR.apk"

if (Test-Path $defaultApk) {
    # Ensure target output path has the APK
    if ($defaultApk -ne $OutputPath) {
        Copy-Item -Path $defaultApk -Destination $OutputPath -Force
    }
}

if (-not (Test-Path $OutputPath)) {
    Write-Error "Build failed to generate APK at $OutputPath. Exit code: $($proc.ExitCode)"
    if (Test-Path $LogFile) {
        Write-Host "== Filtered errors from $LogFile =="
        Select-String -Path $LogFile -Pattern "\[Build\]|error CS|Exception|Build Succeeded|Build Failed" | Select-Object -First 30
    }
    exit 1
}

$apkItem = Get-Item $OutputPath
$apkSizeMB = [math]::Round($apkItem.Length / 1MB, 2)
Write-Host "========================================" -ForegroundColor Green
Write-Host "  BUILD SUCCEEDED: $OutputPath ($apkSizeMB MB)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
exit 0
