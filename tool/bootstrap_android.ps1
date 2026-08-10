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

function Disable-KotlinIncrementalCompilation {
    $gradlePropertiesPath = Join-Path (Get-Location) "android\gradle.properties"
    if (-not (Test-Path $gradlePropertiesPath)) {
        throw "Android gradle.properties was not generated: $gradlePropertiesPath"
    }

    $content = Get-Content -Path $gradlePropertiesPath -Raw
    if ($content -match "(?m)^kotlin\.incremental=false\s*$") {
        return
    }

    # Windows Kotlin incremental caches can fail when Pub Cache and the project are on different drive roots.
    # Disable incremental compilation for this generated Android project to keep local builds deterministic.
    Add-Content -Path $gradlePropertiesPath -Value "`nkotlin.incremental=false" -Encoding ASCII
    Write-Host "Disabled Kotlin incremental compilation for Windows cross-drive build compatibility."
}

function Configure-AndroidForLocalAi {
    $appGradlePath = Join-Path (Get-Location) "android\app\build.gradle.kts"
    $gradlePropertiesPath = Join-Path (Get-Location) "android\gradle.properties"
    if (-not (Test-Path $appGradlePath)) {
        throw "Android app build.gradle.kts was not generated: $appGradlePath"
    }
    if (-not (Test-Path $gradlePropertiesPath)) {
        throw "Android gradle.properties was not generated: $gradlePropertiesPath"
    }

    $content = Get-Content -Path $appGradlePath -Raw
    $gradleProperties = Get-Content -Path $gradlePropertiesPath -Raw
    $changed = $false

    if ($content -match "minSdk\s*=\s*flutter\.minSdkVersion") {
        # llama.cpp Android runtime requires API 26+, while the test device is already API 33.
        $content = $content -replace "minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26"
        $changed = $true
        Write-Host "Configured Android minSdk 26 for local llama.cpp inference."
    }

    $usesLegacyKotlin = $gradleProperties -match "(?m)^android\.builtInKotlin=false\s*$"
    $hasKotlinCompilerDsl = $content -match "(?m)^kotlin\s*\{"
    $hasKotlinPlugin = $content -match 'id\("org\.jetbrains\.kotlin\.android"\)'
    if ($usesLegacyKotlin -and $hasKotlinCompilerDsl -and -not $hasKotlinPlugin) {
        # Flutter 3.44 can generate the top-level kotlin.compilerOptions block while the
        # compatibility migrator disables AGP 9 built-in Kotlin. In that legacy mode the
        # Kotlin Android plugin must be applied so the top-level kotlin extension exists.
        $applicationPluginPattern = '(?m)^(\s*)id\("com\.android\.application"\)\s*$'
        if ($content -notmatch $applicationPluginPattern) {
            throw "Android application plugin declaration was not found in: $appGradlePath"
        }
        $replacement = '$0' + [Environment]::NewLine + '$1id("org.jetbrains.kotlin.android")'
        $content = $content -replace $applicationPluginPattern, $replacement
        $changed = $true
        Write-Host "Applied Kotlin Android plugin for Flutter 3.44 legacy Kotlin compatibility."
    }

    if ($changed) {
        Set-Content -Path $appGradlePath -Value $content -Encoding UTF8
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
Disable-KotlinIncrementalCompilation
Configure-AndroidForLocalAi
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
