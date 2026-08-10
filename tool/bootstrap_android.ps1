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
    $packageName = $packageMatch.Groups[1].Value

    $bridgeBody = @'
import android.content.res.AssetManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val bundledModelLock = Any()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.lajgit.diandi_memory/local_ai_assets",
        ).setMethodCallHandler { call, result ->
            if (call.method != "ensureBundledModel") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            ensureBundledModel(call, result)
        }
    }

    private fun ensureBundledModel(call: MethodCall, result: MethodChannel.Result) {
        val assetPath = call.argument<String>("assetPath")
        val targetFileName = call.argument<String>("targetFileName")
        val expectedSha256 = call.argument<String>("expectedSha256")?.lowercase()
        if (assetPath.isNullOrBlank() || targetFileName.isNullOrBlank() || expectedSha256.isNullOrBlank()) {
            result.error("bundled_model_arguments", "Bundled model arguments are incomplete", null)
            return
        }
        if (targetFileName.contains('/') || targetFileName.contains('\\')) {
            result.error("bundled_model_arguments", "Bundled model filename is invalid", null)
            return
        }

        // 397 MB GGUF 解压和校验放到后台线程，不能阻塞 Android/Flutter 主线程。
        Thread({
            try {
                val payload = synchronized(bundledModelLock) {
                    materializeBundledModel(assetPath, targetFileName, expectedSha256)
                }
                runOnUiThread { result.success(payload) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "bundled_model_failed",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }, "bundled-model-copy").start()
    }

    private fun materializeBundledModel(
        assetPath: String,
        targetFileName: String,
        expectedSha256: String,
    ): Map<String, Any> {
        val modelDirectory = File(filesDir, "models").apply { mkdirs() }
        val target = File(modelDirectory, targetFileName)
        val marker = File(modelDirectory, "$targetFileName.sha256")

        if (target.exists() && marker.exists() && marker.readText().trim() == expectedSha256) {
            return modelPayload(target, expectedSha256)
        }

        if (target.exists() && sha256(target) == expectedSha256) {
            marker.writeText(expectedSha256)
            return modelPayload(target, expectedSha256)
        }

        val temp = File(modelDirectory, "$targetFileName.part")
        if (temp.exists()) temp.delete()
        val digest = MessageDigest.getInstance("SHA-256")
        assets.open(assetPath, AssetManager.ACCESS_STREAMING).use { input ->
            FileOutputStream(temp).use { output ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count <= 0) break
                    digest.update(buffer, 0, count)
                    output.write(buffer, 0, count)
                }
                output.flush()
                output.fd.sync()
            }
        }

        val actualSha256 = digest.digest().joinToString("") { "%02x".format(it) }
        if (actualSha256 != expectedSha256) {
            temp.delete()
            throw IllegalStateException(
                "Bundled model SHA-256 mismatch: expected $expectedSha256, got $actualSha256",
            )
        }

        if (target.exists() && !target.delete()) {
            temp.delete()
            throw IllegalStateException("Could not replace previous bundled model")
        }
        if (!temp.renameTo(target)) {
            temp.copyTo(target, overwrite = true)
            temp.delete()
        }
        marker.writeText(expectedSha256)
        return modelPayload(target, expectedSha256)
    }

    private fun modelPayload(target: File, sha256: String): Map<String, Any> = hashMapOf(
        "path" to target.absolutePath,
        "byteSize" to target.length(),
        "sha256" to sha256,
    )

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count <= 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
'@

    $content = "package $packageName`r`n`r`n$bridgeBody"
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
