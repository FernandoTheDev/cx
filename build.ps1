#requires -version 5.0
<#
.SYNOPSIS
    build.ps1 - build/install script for the Cx compiler on Windows

.DESCRIPTION
    Checks for ldc2 and dub, builds the project, copies the resulting
    binary to C:\Cx\bin, and syncs the std/ library folder to C:\Cx\std.
    Just run it, no flags needed.
#>

$ErrorActionPreference = "Stop"

# ---------- paths ----------
$ProjectDir = $PSScriptRoot
$BinName    = "cx.exe"
$CxRoot     = "C:\Cx"
$InstallDir = Join-Path $CxRoot "bin"
$CxStdDest  = Join-Path $CxRoot "std"
$CxStdSrc   = Join-Path $ProjectDir "std"

# ---------- helpers ----------
function Info($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Err($msg)  { Write-Host "[error] $msg" -ForegroundColor Red }

function Show-InstallInstructions {
    Write-Host ""
    Write-Host "Install ldc2 + dub on Windows:" -ForegroundColor White
    Write-Host ""
    Write-Host "Option 1 - winget (recommended, Windows 10/11):" -ForegroundColor Yellow
    Write-Host "  winget install --id DLang.LDC -e"
    Write-Host "  winget install --id DLang.DUB -e"
    Write-Host ""
    Write-Host "Option 2 - Chocolatey:" -ForegroundColor Yellow
    Write-Host "  choco install ldc dub -y"
    Write-Host ""
    Write-Host "Option 3 - Scoop:" -ForegroundColor Yellow
    Write-Host "  scoop bucket add main"
    Write-Host "  scoop install ldc dub"
    Write-Host ""
    Write-Host "Option 4 - manual installer (works everywhere):" -ForegroundColor Yellow
    Write-Host "  Download and run the installer from https://dlang.org/download.html"
    Write-Host "  (LDC releases: https://github.com/ldc-developers/ldc/releases)"
    Write-Host ""
    Write-Host "After installing, restart your terminal so PATH changes take effect."
    Write-Host ""
}

function Check-Deps {
    $missing = $false

    $ldc2 = Get-Command ldc2 -ErrorAction SilentlyContinue
    if ($ldc2) {
        $ver = (& ldc2 --version | Select-Object -First 1)
        Ok "ldc2 found: $ver"
    } else {
        Err "ldc2 not found in PATH"
        $missing = $true
    }

    $dub = Get-Command dub -ErrorAction SilentlyContinue
    if ($dub) {
        $ver = (& dub --version | Select-Object -First 1)
        Ok "dub found: $ver"
    } else {
        Err "dub not found in PATH"
        $missing = $true
    }

    if ($missing) {
        Write-Host ""
        Warn "Install the missing dependencies before continuing."
        Show-InstallInstructions
        return $false
    }

    Ok "All dependencies are installed."
    return $true
}

function Do-Build {
    Push-Location $ProjectDir
    try {
        Info "Building with dub (ldc2, release)..."
        dub build --compiler=ldc2 --build=release
        $binPath = Join-Path $ProjectDir $BinName
        if (Test-Path $binPath) {
            Ok "Build finished: $binPath"
        } else {
            Err "Build finished but binary '$BinName' was not found in $ProjectDir"
            throw "binary not found"
        }
    } finally {
        Pop-Location
    }
}

function Install-Bin {
    $binPath = Join-Path $ProjectDir $BinName
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    Copy-Item -Path $binPath -Destination (Join-Path $InstallDir $BinName) -Force
    Ok "Binary copied to $(Join-Path $InstallDir $BinName)"
}

function Update-Std {
    if (-not (Test-Path $CxStdSrc)) {
        Err "std/ directory not found in $ProjectDir"
        throw "std not found"
    }

    New-Item -ItemType Directory -Force -Path $CxRoot | Out-Null
    if (Test-Path $CxStdDest) {
        Remove-Item -Recurse -Force $CxStdDest
    }
    Copy-Item -Recurse -Path $CxStdSrc -Destination $CxStdDest
    Ok "std/ updated at $CxStdDest"
}

function Show-PathInstructions {
    Write-Host ""
    Write-Host "Add $InstallDir to PATH:" -ForegroundColor White
    Write-Host ""
    Write-Host "PowerShell (current user, persistent):" -ForegroundColor Yellow
    Write-Host "  [Environment]::SetEnvironmentVariable('Path', `"`$env:Path;$InstallDir`", 'User')"
    Write-Host ""
    Write-Host "Or via the GUI:" -ForegroundColor Yellow
    Write-Host "  Search 'Environment Variables' in the Start menu -> Edit environment"
    Write-Host "  variables for your account -> select 'Path' -> New -> paste:"
    Write-Host "  $InstallDir"
    Write-Host ""
    Write-Host "Then restart your terminal and verify with: Get-Command cx"
    Write-Host ""
}

# ---------- main ----------
if (-not (Check-Deps)) { exit 1 }
Do-Build
Install-Bin
Update-Std
Write-Host ""
Ok "All done! '$BinName' installed at $InstallDir and std/ at $CxStdDest"
Show-PathInstructions
