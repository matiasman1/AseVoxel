#!/usr/bin/env pwsh
# Rewritten to imitate create_extension.sh behavior and CLI

param(
    [switch]$h,
    [switch]$help,
    [switch]$Verbose,
    [switch]$Quiet,
    [switch]$COMPILE_FLAG,
    [switch]$NoCompile,
    [switch]$Prompt,
    [switch]$Auto,
    [switch]$Keep,
    [string]$Version,
    [switch]$DryRun,
    [switch]$Clean
)

# Defaults
$VERBOSITY = 1   # 0=quiet,1=normal,2=verbose
$COMPILE_FLAG = $true
$VERSION_MODE = "prompt"  # prompt, auto, keep, manual
$DRY_RUN_FLAG = $false
$CLEAN_FLAG = $false
$NEW_VERSION = ""

function Show-Help {
    @"
Usage: create_extension.ps1 [OPTIONS]

Creates an Aseprite extension package with optional compilation and versioning.

OPTIONS:
    -h, -help               Show this help message
    -Verbose                Verbose output
    -Quiet                  Quiet mode
    -Compile                Compile native libraries (default)
    -NoCompile              Skip compilation
    -Prompt                 Prompt for version (default)
    -Auto                   Auto-increment patch version
    -Keep                   Keep current version
    -Version <version>      Set specific version
    -DryRun                 Dry-run mode
    -Clean                  Clean build artifacts
"@ | Write-Host
    exit 0
}

function Log-Info { param($m) if ($VERBOSITY -ge 1) { Write-Host $m } }
function Log-Verbose { param($m) if ($VERBOSITY -ge 2) { Write-Host "[VERBOSE] $m" -ForegroundColor Cyan } }
function Log-Error { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }
function Log-Dry { param($m) Write-Host "[DRY-RUN] $m" -ForegroundColor Yellow }

# Parse params
if ($h -or $help) { Show-Help }
if ($Verbose) { $VERBOSITY = 2 }
if ($Quiet) { $VERBOSITY = 0 }
if ($COMPILE_FLAG) { $COMPILE_FLAG = $true }
if ($NoCompile) { $COMPILE_FLAG = $false }
if ($Prompt) { $VERSION_MODE = "prompt" }
if ($Auto) { $VERSION_MODE = "auto" }
if ($Keep) { $VERSION_MODE = "keep" }
if ($Version) { $VERSION_MODE = "manual"; $NEW_VERSION = $Version }
if ($DryRun) { $DRY_RUN_FLAG = $true }
if ($Clean) { $CLEAN_FLAG = $true }

# Navigate to script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location -Path $scriptDir
Log-Verbose "Working directory: $scriptDir"

# Clean build artifacts
if ($CLEAN_FLAG) {
    Log-Info "Cleaning build artifacts..."
    if (-not $DRY_RUN_FLAG) {
        $artifacts = @("render/bin/asevoxel_native.so","render/bin/asevoxel_native.dll","libasevoxel_native.a")
        foreach ($a in $artifacts) {
            $p = Join-Path $scriptDir $a
            if (Test-Path $p) {
                Remove-Item $p -Force -ErrorAction SilentlyContinue
                Log-Verbose "Removed $a"
            }
        }
    } else {
        Log-Dry "Would remove native library files"
    }
}

# Version management
if (Test-Path "package.json") {
    try {
        $pkg = Get-Content "package.json" -Raw | ConvertFrom-Json
        $current = $pkg.version
    } catch {
        Log-Error "Failed reading package.json: $_"
        $current = ""
    }
    Log-Info "Current version: $current"

    switch ($VERSION_MODE) {
        "prompt" {
            $input = Read-Host "Enter new version (leave empty to keep $current)"
            if ([string]::IsNullOrWhiteSpace($input)) {
                $NEW_VERSION = $current
                Log-Info "Keeping version $NEW_VERSION"
            } else {
                $NEW_VERSION = $input
                Log-Info "Updating to version $NEW_VERSION"
                if (-not $DRY_RUN_FLAG) {
                    try {
                        $pkgObj = Get-Content package.json -Raw | ConvertFrom-Json
                        $pkgObj.version = $NEW_VERSION
                        $pkgObj | ConvertTo-Json -Depth 10 | Set-Content package.json
                    } catch {
                        Log-Error "Failed updating package.json: $_"
                    }
                } else {
                    Log-Dry "Would update version to $NEW_VERSION"
                }
            }
        }
        "auto" {
            if ($current -match '^(\d+)\.(\d+)\.(\d+)$') {
                $major = [int]$matches[1]; $minor = [int]$matches[2]; $patch = [int]$matches[3] + 1
                $NEW_VERSION = "$major.$minor.$patch"
                Log-Info "Auto-incrementing version to $NEW_VERSION"
                if (-not $DRY_RUN_FLAG) {
                    try {
                        $pkgObj = Get-Content package.json -Raw | ConvertFrom-Json
                        $pkgObj.version = $NEW_VERSION
                        $pkgObj | ConvertTo-Json -Depth 10 | Set-Content package.json
                    } catch {
                        Log-Error "Failed updating package.json: $_"
                    }
                } else {
                    Log-Dry "Would update version to $NEW_VERSION"
                }
            } else {
                Log-Error "Current version not in MAJOR.MINOR.PATCH format: $current"
                $NEW_VERSION = $current
            }
        }
        "keep" {
            $NEW_VERSION = $current
            Log-Info "Keeping version $NEW_VERSION"
        }
        "manual" {
            if (-not [string]::IsNullOrWhiteSpace($NEW_VERSION)) {
                Log-Info "Setting version to $NEW_VERSION"
                if (-not $DRY_RUN_FLAG) {
                    try {
                        $pkgObj = Get-Content package.json -Raw | ConvertFrom-Json
                        $pkgObj.version = $NEW_VERSION
                        $pkgObj | ConvertTo-Json -Depth 10 | Set-Content package.json
                    } catch {
                        Log-Error "Failed updating package.json: $_"
                    }
                } else {
                    Log-Dry "Would update version to $NEW_VERSION"
                }
            } else {
                Log-Error "No version provided for manual mode"
            }
        }
    }
} else {
    Log-Error "package.json not found, version information unavailable"
    $NEW_VERSION = "unknown"
}

# Prepare names
$EXT = "AseVoxel-Viewer"
$tempZip = Join-Path $scriptDir "$EXT.zip"
$outFile = Join-Path $scriptDir "$EXT.aseprite-extension"

# Remove previous outputs
if (Test-Path $tempZip) {
    Log-Verbose "Removing existing $tempZip"
    if (-not $DRY_RUN_FLAG) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue } else { Log-Dry "Would remove $tempZip" }
}
if (Test-Path $outFile) {
    Log-Info "Removing existing $outFile"
    if (-not $DRY_RUN_FLAG) { Remove-Item $outFile -Force -ErrorAction SilentlyContinue } else { Log-Dry "Would remove $outFile" }
}

# Compilation (Linux .so and Windows cross .dll) - mimic shell script behavior
if ($COMPILE_FLAG) {
    Log-Info "Compiling native libraries..."

    $binDir = Join-Path $scriptDir "render/bin"
    if (-not (Test-Path $binDir)) {
        if (-not $DRY_RUN_FLAG) {
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null
            Log-Verbose "Created render/bin"
        } else {
            Log-Dry "Would create render/bin"
        }
    }

    # Check source
    if (-not (Test-Path "asevoxel_native.cpp")) {
        Log-Error "Source file asevoxel_native.cpp not found"
        exit 1
    }

    # Linux build (g++)
    $gpp = Get-Command g++ -ErrorAction SilentlyContinue
    $pkg = Get-Command pkg-config -ErrorAction SilentlyContinue
    if ($gpp -and $pkg) {
        Log-Verbose "Found g++ and pkg-config"
        if (-not $DRY_RUN_FLAG) {
            # verify lua5.4 exists
            & pkg-config --exists lua5.4
            if ($LASTEXITCODE -ne 0) { Log-Error "Lua 5.4 dev files not found"; exit 1 }
            $cflags = (& pkg-config --cflags lua5.4).Trim()
            $libs   = (& pkg-config --libs lua5.4).Trim()
            Log-Verbose "Compiler flags: $cflags"
            Log-Verbose "Linker flags: $libs"

            $soOut = Join-Path $binDir "asevoxel_native.so"
            $args = @('-shared','-fPIC') + ($cflags -split '\s+') + @('-o', $soOut, 'asevoxel_native.cpp') + ($libs -split '\s+')
            Log-Verbose "Running: g++ $($args -join ' ')"
            $output = & g++ @args 2>&1
            if ($LASTEXITCODE -eq 0) {
                Log-Info "✓ Built asevoxel_native.so"
                if ($VERBOSITY -ge 2) { Get-ChildItem $soOut | ForEach-Object { Write-Host $_ } }
            } else {
                Log-Error "Failed to build asevoxel_native.so"
                Log-Error $output
                exit 1
            }
        } else { Log-Dry "Would compile asevoxel_native.so" }
    } else {
        Log-Verbose "g++ or pkg-config not found for Linux build; skipping .so build"
    }

    # Windows cross compile (mingw)
    $mingw = Get-Command x86_64-w64-mingw32-g++ -ErrorAction SilentlyContinue
    if ($mingw) {
        Log-Verbose "Found MinGW cross-compiler"
        if (-not $DRY_RUN_FLAG) {
            if (-not (Test-Path "thirdparty/lua-win/include") -or -not (Test-Path "thirdparty/lua-win/lib")) {
                Log-Error "Windows Lua libraries not found in thirdparty/lua-win"
                exit 1
            }
            $dllOut = Join-Path $binDir "asevoxel_native.dll"
            $args = @(
                '-O2','-std=c++17','-D_WIN32_WINNT=0x0601','-shared',
                'asevoxel_native.cpp',
                '-Ithirdparty/lua-win/include','-Lthirdparty/lua-win/lib','-llua54',
                '-static','-static-libgcc','-static-libstdc++',
                '-Wl,--out-implib,libasevoxel_native.a',
                '-o', $dllOut
            )
            Log-Verbose "Running: x86_64-w64-mingw32-g++ $($args -join ' ')"
            $output = & x86_64-w64-mingw32-g++ @args 2>&1
            if ($LASTEXITCODE -eq 0) {
                Log-Info "✓ Built asevoxel_native.dll"
                if ($VERBOSITY -ge 2) { Get-ChildItem $dllOut | ForEach-Object { Write-Host $_ } }
            } else {
                Log-Error "Failed to build asevoxel_native.dll"
                Log-Error $output
                exit 1
            }
        } else { Log-Dry "Would compile asevoxel_native.dll" }
    } else {
        Log-Verbose "MinGW cross-compiler not found; skipping .dll build"
    }
} else {
    Log-Info "Skipping compilation (--no-compile)"
}

# Packaging: collect files and create zip, then rename
Log-Info "Creating $EXT.zip..."
Log-Verbose "Including: *.lua, *.json, io/, math/, render/, utils/, dialog/, core/"

# Build list of files with relative paths to preserve structure
$files = @()
$files += Get-ChildItem -Path $scriptDir -Filter *.lua -File -Depth 0 -ErrorAction SilentlyContinue
$files += Get-ChildItem -Path $scriptDir -Filter *.json -File -Depth 0 -ErrorAction SilentlyContinue
$dirs = @("io","math","render","utils","dialog","core")
foreach ($d in $dirs) {
    $p = Join-Path $scriptDir $d
    if (Test-Path $p) { 
        $files += Get-ChildItem -Path $p -Recurse -File | Where-Object { -not $_.Name.EndsWith('.backup') }
        Log-Verbose "Added files from $d" 
    }
}
Log-Verbose "Total files to include: $($files.Count)"

if ($files.Count -eq 0) {
    Log-Info "No files found to add to archive"
    if (-not $DRY_RUN_FLAG) { [System.IO.Compression.ZipFile]::Open($tempZip,'Create').Dispose() } else { Log-Dry "Would create empty archive" }
} else {
    if (-not $DRY_RUN_FLAG) {
        # Use System.IO.Compression to preserve folder structure
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
        
        $zip = [System.IO.Compression.ZipFile]::Open($tempZip, 'Create')
        try {
            foreach ($file in $files) {
                # Calculate relative path from script directory
                $relativePath = $file.FullName.Substring($scriptDir.Length + 1).Replace('\', '/')
                Log-Verbose "Adding: $relativePath"
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relativePath) | Out-Null
            }
            Log-Verbose "Archive created with $($files.Count) files"
        } finally {
            $zip.Dispose()
        }
    } else {
        Log-Dry "Would compress $($files.Count) files into $tempZip preserving folder structure"
    }
}

# Rename .zip to .aseprite-extension
if ((Test-Path $tempZip) -or $DRY_RUN_FLAG) {
    Log-Info "Renaming $tempZip to $outFile..."
    if (-not $DRY_RUN_FLAG) {
        if (Test-Path $outFile) { Remove-Item $outFile -Force -ErrorAction SilentlyContinue }
        Rename-Item -Path $tempZip -NewName $outFile -Force
        Log-Info "$outFile created successfully!"
        # Try to set executable bit if chmod exists (on *nix)
        $chmod = Get-Command chmod -ErrorAction SilentlyContinue
        if ($chmod) { & chmod +x $outFile }
    } else {
        Log-Dry "Would rename to $outFile"
        Log-Dry "Would make $outFile executable (if applicable)"
    }
} else {
    Log-Error "Failed to create zip file"
}

Log-Info "Done! Version: $NEW_VERSION"
