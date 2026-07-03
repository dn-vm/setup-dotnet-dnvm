#Requires -Version 5.1
# Installs a .NET SDK using dnvm and wires up the environment for subsequent
# GitHub Actions steps (PATH, DOTNET_ROOT) and step outputs. Windows-native
# implementation (no bash dependency); the Unix equivalent is setup.sh.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$dotnetVersion  = $env:INPUT_DOTNET_VERSION
$globalJsonFile = $env:INPUT_GLOBAL_JSON_FILE
$dnvmVersion    = if ($env:INPUT_DNVM_VERSION) { $env:INPUT_DNVM_VERSION } else { '1.1.2' }

if (-not $dotnetVersion -and -not $globalJsonFile) {
    Write-Error "One of 'dotnet-version' or 'global-json-file' is required."
}
if ($dotnetVersion -and $globalJsonFile) {
    Write-Error "'dotnet-version' and 'global-json-file' are mutually exclusive."
}

# --- Resolve the dnvm runtime identifier (RID) for this runner ---------------
$arch = if ($env:RUNNER_ARCH) { $env:RUNNER_ARCH } else { $env:PROCESSOR_ARCHITECTURE }
switch -Regex ($arch) {
    '^(X64|AMD64)$' { $ridArch = 'x64' }
    default {
        Write-Error "dnvm only publishes a win-x64 build; 'win-$arch' is unsupported."
    }
}
$rid = "win-$ridArch"
$url = "https://github.com/dn-vm/dnvm/releases/download/v$dnvmVersion/dnvm-$dnvmVersion-$rid.zip"

# --- Download and extract the dnvm binary -----------------------------------
$baseTmp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$toolDir = Join-Path $baseTmp 'dnvm-bin'
New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
$archive = Join-Path $toolDir 'dnvm.zip'

Write-Host "Downloading dnvm $dnvmVersion for $rid"
Invoke-WebRequest -Uri $url -OutFile $archive
Expand-Archive -LiteralPath $archive -DestinationPath $toolDir -Force
$dnvmBin = Join-Path $toolDir 'dnvm.exe'

# --- Resolve DNVM_HOME ------------------------------------------------------
$dnvmHome = if ($env:INPUT_INSTALL_DIR) { $env:INPUT_INSTALL_DIR } else { Join-Path $HOME '.dnvm' }
New-Item -ItemType Directory -Force -Path $dnvmHome | Out-Null
$dotnetRoot = Join-Path $dnvmHome 'dn'
$dotnetExe  = Join-Path $dotnetRoot 'dotnet.exe'

# --- Install the requested SDK (idempotent: dnvm skips if already present) ---
$env:DNVM_HOME = $dnvmHome
if ($globalJsonFile) {
    if (-not (Test-Path -LiteralPath $globalJsonFile -PathType Leaf)) {
        Write-Error "global-json-file not found: $globalJsonFile"
    }
    # dnvm restore reads a file named 'global.json' from the current directory
    # upward. Point the cwd at the file's directory; if the file has a different
    # name, stage a copy named global.json in a temp dir.
    if ((Split-Path $globalJsonFile -Leaf) -eq 'global.json') {
        $gjDir = Split-Path -Path (Resolve-Path -LiteralPath $globalJsonFile) -Parent
    } else {
        $gjDir = Join-Path $baseTmp 'dnvm-globaljson'
        New-Item -ItemType Directory -Force -Path $gjDir | Out-Null
        Copy-Item -LiteralPath $globalJsonFile -Destination (Join-Path $gjDir 'global.json') -Force
    }

    Write-Host "Restoring SDK from $globalJsonFile into $dnvmHome"
    Push-Location $gjDir
    try {
        & $dnvmBin restore
        if ($LASTEXITCODE -ne 0) { Write-Error "dnvm restore failed with exit code $LASTEXITCODE" }
        # The resolved SDK (after roll-forward) is what the muxer selects for
        # that global.json, so query it from the restore directory.
        $env:DOTNET_ROOT = $dotnetRoot
        $resolvedVersion = (& $dotnetExe --version).Trim()
    } finally {
        Pop-Location
    }
} else {
    Write-Host "Installing .NET SDK $dotnetVersion into $dnvmHome"
    & $dnvmBin install $dotnetVersion
    if ($LASTEXITCODE -ne 0) { Write-Error "dnvm install failed with exit code $LASTEXITCODE" }
    $resolvedVersion = $dotnetVersion
}

# --- Wire up the environment for subsequent steps ---------------------------
if ($env:GITHUB_PATH)   { Add-Content -Path $env:GITHUB_PATH -Value $dotnetRoot }
if ($env:GITHUB_ENV)    { Add-Content -Path $env:GITHUB_ENV -Value "DOTNET_ROOT=$dotnetRoot" }
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "dotnet-version=$resolvedVersion"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "dotnet-root=$dotnetRoot"
}

Write-Host "Installed .NET SDK $resolvedVersion"
& $dotnetExe --version
