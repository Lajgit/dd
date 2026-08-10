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
        # Flutter 3.44 can generate kotlin.compilerOptions while its compatibility migrator
        # disables AGP 9 built-in Kotlin; legacy mode still needs the Kotlin Android plugin.
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

function Get-Sha256Lower {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Prepare-BundledLocalAiModel {
    $modelFileName = "qwen3-0.6b-q4_k_m-b0638f08.gguf"
    $expectedSha256 = "b0638f08417a2d3c8652760462eb5407c6e30173cf9608ad0820757a281eea0e"
    $modelUrl = "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/1208e45d782fe18602c5eaf10e5758d5b0f24c03/Qwen3-0.6B-Q4_K_M.gguf?download=true"

    $dartModelConfigPath = Join-Path (Get-Location) "lib\features\memories\data\bundled_local_ai_model.dart"
    $dartModelConfig = Get-Content -Path $dartModelConfigPath -Raw
    if ($dartModelConfig -notmatch [regex]::Escape($modelFileName) -or
        $dartModelConfig -notmatch [regex]::Escape($expectedSha256)) {
        throw "Bundled AI model constants are out of sync between Dart and bootstrap script."
    }

    $cacheDirectory = Join-Path (Get-Location) ".local_models"
    $cachePath = Join-Path $cacheDirectory $modelFileName
    New-Item -ItemType Directory -Force -Path $cacheDirectory | Out-Null

    $needsDownload = $true
    if (Test-Path $cachePath) {
        $cachedSha256 = Get-Sha256Lower -Path $cachePath
        if ($cachedSha256 -eq $expectedSha256) {
            $needsDownload = $false
            Write-Host "Using verified bundled AI model cache: $cachePath"
        } else {
            Write-Host "Cached bundled AI model hash mismatch; downloading a fresh copy."
            Remove-Item -Force $cachePath
        }
    }

    if ($needsDownload) {
        $tempPath = "$cachePath.part"
        if (Test-Path $tempPath) {
            Remove-Item -Force $tempPath
        }

        Write-Host "Downloading bundled Qwen3 0.6B Q4_K_M model (about 397 MB)..."
        $previousProgressPreference = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $modelUrl -OutFile $tempPath -UseBasicParsing
        } finally {
            $ProgressPreference = $previousProgressPreference
        }

        $downloadedSha256 = Get-Sha256Lower -Path $tempPath
        if ($downloadedSha256 -ne $expectedSha256) {
            Remove-Item -Force $tempPath
            throw "Bundled AI model SHA-256 mismatch. Expected $expectedSha256 but got $downloadedSha256"
        }
        Move-Item -Force $tempPath $cachePath
        Write-Host "Bundled AI model downloaded and SHA-256 verified."
    }

    $assetModelDirectory = Join-Path (Get-Location) "android\app\src\main\assets\models"
    New-Item -ItemType Directory -Force -Path $assetModelDirectory | Out-Null
    $assetModelPath = Join-Path $assetModelDirectory $modelFileName
    if (Test-Path $assetModelPath) {
        Remove-Item -Force $assetModelPath
    }

    # Prefer a hard link so the developer machine does not keep another 397 MB copy before packaging.
    try {
        New-Item -ItemType HardLink -Path $assetModelPath -Target $cachePath -ErrorAction Stop | Out-Null
        Write-Host "Linked verified bundled AI model into Android assets."
    } catch {
        Copy-Item -Force $cachePath $assetModelPath
        Write-Host "Copied verified bundled AI model into Android assets."
    }

    $assetLicenseDirectory = Join-Path (Get-Location) "android\app\src\main\assets\licenses"
    New-Item -ItemType Directory -Force -Path $assetLicenseDirectory | Out-Null
    Copy-Item -Force ".\legal\Apache-2.0.txt" (Join-Path $assetLicenseDirectory "Apache-2.0.txt")
    Copy-Item -Force ".\legal\Qwen3-NOTICE.txt" (Join-Path $assetLicenseDirectory "Qwen3-NOTICE.txt")
}

function Configure-BundledModelBridge {
    $kotlinRoot = Join-Path (Get-Location) "android\app\src\main\kotlin"
    $mainActivity = Get-ChildItem -Path $kotlinRoot -Filter "MainActivity.kt" -Recurse | Select-Object -First 1
    if ($null -eq $mainActivity) {
        throw "Generated MainActivity.kt was not found under: $kotlinRoot"
    }

    $existing = Get-Content -Path $mainActivity.FullName -Raw
    $packageMatch = [regex]::Match($existing, '(?m)^\s*package\s+([A-Za-z0-9_.]+)\s*$')
    if (-not $packageMatch.Success) {
        throw "Could not determine Android package name from: $($mainActivity.FullName)"
    }

    $templatePath = Join-Path (Get-Location) "tool\android\MainActivity.kt.template"
    if (-not (Test-Path $templatePath)) {
        throw "Bundled model Android bridge template was not found: $templatePath"
    }
    $packageName = $packageMatch.Groups[1].Value
    $template = Get-Content -Path $templatePath -Raw
    $content = $template.Replace("__PACKAGE__", $packageName)
    Set-Content -Path $mainActivity.FullName -Value $content -Encoding UTF8
    Write-Host "Configured Android bridge for bundled local AI model extraction."
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
Prepare-BundledLocalAiModel
Configure-BundledModelBridge
Invoke-Flutter @("build", "apk", "--debug")

$apkPath = Join-Path (Get-Location) "build\app\outputs\flutter-apk\app-debug.apk"
if (Test-Path $apkPath) {
    Write-Host ""
    Write-Host "Build succeeded. APK: $apkPath"
} else {
    throw "Build finished but APK was not found at: $apkPath"
}
