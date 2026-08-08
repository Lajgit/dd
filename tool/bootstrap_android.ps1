$ErrorActionPreference = "Stop"

function Resolve-FlutterCommand {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $localFlutter = Join-Path $env:LOCALAPPDATA "Programs\flutter\bin\flutter.bat"
    if (Test-Path $localFlutter) {
        return $localFlutter
    }

    throw @"
Flutter was not found.

Run this first from the repository root:
  powershell -ExecutionPolicy Bypass -File .\tool\install_flutter_windows.ps1

Then close and reopen PowerShell, return to the repository, and run:
  powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_android.ps1
"@
}

function Invoke-Flutter {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $script:FlutterCommand @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter command failed: flutter $($Arguments -join ' ')"
    }
}

$script:FlutterCommand = Resolve-FlutterCommand
Write-Host "Using Flutter: $script:FlutterCommand"

Invoke-Flutter @("--version")

# Clear generated plugin/build state before regenerating the Android project.
# This avoids stale plugin registrants after dependency changes.
Invoke-Flutter @("clean")

Invoke-Flutter @(
    "create",
    ".",
    "--platforms=android",
    "--project-name=diandi_memory",
    "--org=com.lajgit"
)
Invoke-Flutter @("pub", "get")
Invoke-Flutter @("analyze")
Invoke-Flutter @("test")
Invoke-Flutter @("build", "apk", "--debug")

$apkPath = Join-Path (Get-Location) "build\app\outputs\flutter-apk\app-debug.apk"
if (Test-Path $apkPath) {
    Write-Host ""
    Write-Host "Build succeeded. APK: $apkPath"
} else {
    throw "Build finished but APK was not found at: $apkPath"
}
