param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\flutter"
)

$ErrorActionPreference = "Stop"

function Ensure-UserPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathEntry
    )

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @()
    if (-not [string]::IsNullOrWhiteSpace($userPath)) {
        $entries = $userPath.Split(';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $alreadyPresent = $entries | Where-Object {
        $_.TrimEnd('\\') -ieq $PathEntry.TrimEnd('\\')
    }

    if (-not $alreadyPresent) {
        $newUserPath = (($entries + $PathEntry) -join ';')
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
        Write-Host "Added Flutter to the user PATH."
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git was not found. Install Git for Windows first, then rerun this script."
}

$flutterBat = Join-Path $InstallDir "bin\flutter.bat"
if (-not (Test-Path $flutterBat)) {
    $parent = Split-Path -Parent $InstallDir
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    Write-Host "Installing Flutter stable into: $InstallDir"
    git clone --branch stable --depth 1 https://github.com/flutter/flutter.git $InstallDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone Flutter stable."
    }
}

$flutterBin = Join-Path $InstallDir "bin"
$env:Path = "$flutterBin;$env:Path"
Ensure-UserPathEntry -PathEntry $flutterBin

Write-Host "Using Flutter: $flutterBat"
& $flutterBat --version
if ($LASTEXITCODE -ne 0) {
    throw "Flutter installation exists but flutter --version failed."
}

Write-Host ""
Write-Host "Running flutter doctor..."
& $flutterBat doctor

Write-Host ""
Write-Host "Flutter setup finished."
Write-Host "Close and reopen PowerShell so the PATH update is visible everywhere."
Write-Host "Then run from the repository root:"
Write-Host "  powershell -ExecutionPolicy Bypass -File .\tool\bootstrap_android.ps1"
