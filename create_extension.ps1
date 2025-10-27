[CmdletBinding()]
param(
    [Parameter(HelpMessage="Display help information")]
    [Alias("h")]
    [switch]$Help,
    
    [Parameter(HelpMessage="Verbose output (more detailed logging)")]
    [Alias("v")]
    [switch]$Verbose,
    
    [Parameter(HelpMessage="Quiet mode (minimal output)")]
    [Alias("q")]
    [switch]$Quiet,
    
    [Parameter(HelpMessage="Compile native libraries")]
    [Alias("c")]
    [switch]$Compile,
    
    [Parameter(HelpMessage="Skip compilation of native libraries")]
    [Alias("C")]
    [switch]$NoCompile,
    
    [Parameter(HelpMessage="Prompt for version (default)")]
    [Alias("p")]
    [switch]$PromptVersion,
    
    [Parameter(HelpMessage="Auto-increment patch version")]
    [Alias("a")]
    [switch]$AutoVersion,
    
    [Parameter(HelpMessage="Keep current version")]
    [Alias("k")]
    [switch]$KeepVersion,
    
    [Parameter(HelpMessage="Set specific version")]
    [Alias("V")]
    [string]$Version,
    
    [Parameter(HelpMessage="Show what would be done without doing it")]
    [Alias("n")]
    [switch]$DryRun,
    
    [Parameter(HelpMessage="Clean build artifacts before building")]
    [switch]$Clean
)

# Function to show help
function Show-Help {
    Write-Host @"
Usage: .\create_extension.ps1 [OPTIONS]

Creates an Aseprite extension package with optional compilation and versioning.

OPTIONS:
    -Help, -h               Show this help message
    -Verbose, -v            Verbose output (detailed logging)
    -Quiet, -q              Quiet mode (minimal output)
    
    -Compile, -c            Compile native libraries (default)
    -NoCompile, -C          Skip compilation
    
    -PromptVersion, -p      Prompt for version (default)
    -AutoVersion, -a        Auto-increment patch version
    -KeepVersion, -k        Keep current version
    -Version VERSION, -V    Set specific version
    
    -DryRun, -n             Show what would be done without doing it
    -Clean                  Clean build artifacts before building
    
EXAMPLES:
    .\create_extension.ps1                      # Interactive mode
    .\create_extension.ps1 -Quiet -KeepVersion -NoCompile
    .\create_extension.ps1 -Verbose -AutoVersion
    .\create_extension.ps1 -Version 1.2.3
    .\create_extension.ps1 -DryRun -Clean

"@
    exit 0
}

# Show help if requested
if ($Help) {
    Show-Help
}

# Set verbosity level
$VerbosityLevel = 1  # 0=quiet, 1=normal, 2=verbose
if ($Quiet) { $VerbosityLevel = 0 }
if ($Verbose) { $VerbosityLevel = 2 }

# Determine compilation mode
$ShouldCompile = $true
if ($NoCompile) { $ShouldCompile = $false }
if ($Compile) { $ShouldCompile = $true }

# Determine version mode
$VersionMode = "prompt"
if ($KeepVersion) { $VersionMode = "keep" }
if ($AutoVersion) { $VersionMode = "auto" }
if ($Version) { $VersionMode = "manual" }

# Logging functions
function Log-Info {
    param([string]$Message)
    if ($VerbosityLevel -ge 1) {
        Write-Host $Message
    }
}

function Log-Verbose {
    param([string]$Message)
    if ($VerbosityLevel -ge 2) {
        Write-Host "[VERBOSE] $Message" -ForegroundColor Cyan
    }
}

function Log-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Log-DryRun {
    param([string]$Message)
    Write-Host "[DRY-RUN] $Message" -ForegroundColor Yellow
}

# Navigate to the directory and store the script location
$scriptDir = (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location -Path $scriptDir
Log-Verbose "Working directory: $scriptDir"

# Clean build artifacts if requested
if ($Clean) {
    Log-Info "Cleaning build artifacts..."
    if (-not $DryRun) {
        $artifactsToRemove = @(
            "render\bin\asevoxel_native.so",
            "render\bin\asevoxel_native.dll",
            "libasevoxel_native.a"
        )
        foreach ($artifact in $artifactsToRemove) {
            $fullPath = Join-Path $scriptDir $artifact
            if (Test-Path $fullPath) {
                Remove-Item $fullPath -Force -ErrorAction SilentlyContinue
                Log-Verbose "Removed $artifact"
            }
        }
    } else {
        Log-DryRun "Would remove native library files"
    }
}

# Read the current version from package.json
$currentVersion = $null
$newVersion = $null

if (Test-Path "package.json") {
    $packageContent = Get-Content "package.json" -Raw | ConvertFrom-Json
    $currentVersion = $packageContent.version
    Log-Info "Current version: $currentVersion"
    
    switch ($VersionMode) {
        "prompt" {
            $newVersion = Read-Host "Enter new version (leave empty to keep $currentVersion)"
            if ([string]::IsNullOrWhiteSpace($newVersion)) {
                $newVersion = $currentVersion
                Log-Info "Keeping version $newVersion"
            } else {
                Log-Info "Updating to version $newVersion"
                if (-not $DryRun) {
                    $packageContent.version = $newVersion
                    $packageContent | ConvertTo-Json -Depth 10 | Set-Content "package.json"
                } else {
                    Log-DryRun "Would update version to $newVersion"
                }
            }
        }
        "auto" {
            # Auto-increment patch version
            $versionParts = $currentVersion -split '\.'
            $major = [int]$versionParts[0]
            $minor = [int]$versionParts[1]
            $patch = [int]$versionParts[2]
            $patch++
            $newVersion = "$major.$minor.$patch"
            Log-Info "Auto-incrementing version to $newVersion"
            if (-not $DryRun) {
                $packageContent.version = $newVersion
                $packageContent | ConvertTo-Json -Depth 10 | Set-Content "package.json"
            } else {
                Log-DryRun "Would update version to $newVersion"
            }
        }
        "keep" {
            $newVersion = $currentVersion
            Log-Info "Keeping version $newVersion"
        }
        "manual" {
            $newVersion = $Version
            Log-Info "Setting version to $newVersion"
            if (-not $DryRun) {
                $packageContent.version = $newVersion
                $packageContent | ConvertTo-Json -Depth 10 | Set-Content "package.json"
            } else {
                Log-DryRun "Would update version to $newVersion"
            }
        }
    }
} else {
    Log-Error "package.json not found, version information unavailable"
    $newVersion = "unknown"
}

# Define extension name 
$extensionName = "AseVoxel-Viewer"

# Define file names with full paths to ensure correct location
$tempZipFile = Join-Path -Path $scriptDir -ChildPath "$extensionName.zip"
$outputFile = Join-Path -Path $scriptDir -ChildPath "$extensionName.aseprite-extension"

# Delete any existing files
if (Test-Path $tempZipFile) {
    Log-Verbose "Removing existing $tempZipFile"
    if (-not $DryRun) {
        Remove-Item $tempZipFile -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    } else {
        Log-DryRun "Would remove $tempZipFile"
    }
}

if (Test-Path $outputFile) {
    Log-Info "Removing existing $outputFile"
    if (-not $DryRun) {
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    } else {
        Log-DryRun "Would remove $outputFile"
    }
}

# Compile native libraries
if ($ShouldCompile) {
    Log-Info "Compiling native libraries..."
    
    # Create bin directory if needed
    $binDir = Join-Path $scriptDir "render\bin"
    if (-not (Test-Path $binDir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $binDir -Force | Out-Null
            Log-Verbose "Created render\bin directory"
        } else {
            Log-DryRun "Would create render\bin directory"
        }
    }
    
    # Check for source file
    $sourceFile = Join-Path $scriptDir "asevoxel_native.cpp"
    if (-not (Test-Path $sourceFile)) {
        Log-Error "Source file asevoxel_native.cpp not found"
        exit 1
    }
    
    # Windows compilation requires MinGW-w64 or MSVC
    # Check for g++ (MinGW) first
    $gppPath = Get-Command g++ -ErrorAction SilentlyContinue
    $clPath = Get-Command cl -ErrorAction SilentlyContinue
    
    if ($gppPath) {
        Log-Info "Found g++ compiler (MinGW): $($gppPath.Source)"
        
        # Check for Lua development files
        $luaInclude = Join-Path $scriptDir "thirdparty\lua-win\include"
        $luaLib = Join-Path $scriptDir "thirdparty\lua-win\lib"
        
        if (-not (Test-Path $luaInclude) -or -not (Test-Path $luaLib)) {
            Log-Error "Windows Lua libraries not found in thirdparty\lua-win\"
            Log-Error "Please ensure thirdparty\lua-win\include and thirdparty\lua-win\lib exist"
            exit 1
        }
        
        Log-Verbose "Using Lua headers from: $luaInclude"
        Log-Verbose "Using Lua library from: $luaLib"
        
        if (-not $DryRun) {
            $outputDll = Join-Path $binDir "asevoxel_native.dll"
            $compileCmd = "g++ -O2 -std=c++17 -D_WIN32_WINNT=0x0601 -shared `"$sourceFile`" " +
                          "-I`"$luaInclude`" -L`"$luaLib`" -llua54 " +
                          "-static -static-libgcc -static-libstdc++ " +
                          "-o `"$outputDll`""
            
            Log-Verbose "Compile command: $compileCmd"
            
            try {
                $output = Invoke-Expression $compileCmd 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Log-Info "✓ Built asevoxel_native.dll"
                    if ($VerbosityLevel -ge 2) {
                        $fileInfo = Get-Item $outputDll
                        Log-Verbose "  Size: $($fileInfo.Length) bytes"
                    }
                } else {
                    Log-Error "Failed to build asevoxel_native.dll"
                    Log-Error $output
                    exit 1
                }
            } catch {
                Log-Error "Compilation failed: $_"
                exit 1
            }
        } else {
            Log-DryRun "Would compile asevoxel_native.dll with g++"
        }
        
    } elseif ($clPath) {
        Log-Info "Found MSVC compiler: $($clPath.Source)"
        Log-Info "Note: MSVC compilation support is experimental"
        
        # MSVC compilation would require different flags
        # For now, just warn
        Log-Info "Please use MinGW-w64 g++ for reliable compilation on Windows"
        Log-Info "Or compile on Linux and copy the DLL to render\bin\"
        
    } else {
        Log-Info "No C++ compiler found on Windows"
        Log-Info "Native library compilation requires one of:"
        Log-Info "  1. MinGW-w64 (recommended): choco install mingw"
        Log-Info "  2. MSVC (Visual Studio Build Tools)"
        Log-Info "  3. Compile on Linux and copy DLLs to render\bin\"
        
        # Check if pre-compiled binaries exist
        $dllPath = Join-Path $binDir "asevoxel_native.dll"
        if (Test-Path $dllPath) {
            Log-Info "Found pre-compiled asevoxel_native.dll, will use existing binary"
        } else {
            Log-Error "No compiler found and no pre-compiled DLL available"
            exit 1
        }
    }
} else {
    Log-Info "Skipping compilation (-NoCompile flag set)"
}

# Create a new zip archive using PowerShell's Compress-Archive
Log-Info "Creating $tempZipFile..."
Log-Verbose "Including: *.lua, *.json, render/bin/, io/, math/, utils/, dialog/, core/"

try {
    # Collect top-level lua/json files
    $paths = @()
    $paths += Get-ChildItem -Path $scriptDir -Filter *.lua -File -Recurse:$false | ForEach-Object { $_.FullName }
    $paths += Get-ChildItem -Path $scriptDir -Filter *.json -File -Recurse:$false | ForEach-Object { $_.FullName }

    # Include specific directories
    $dirsToInclude = @("io", "math", "render", "utils", "dialog", "core")
    foreach ($dir in $dirsToInclude) {
        $dirPath = Join-Path $scriptDir $dir
        if (Test-Path $dirPath) {
            $paths += Get-ChildItem -Path $dirPath -Recurse -File | ForEach-Object { $_.FullName }
            Log-Verbose "Added files from $dir directory"
        }
    }

    # Verify native libraries exist if compilation was enabled
    if ($ShouldCompile -and -not $DryRun) {
        $dllPath = Join-Path $scriptDir "render\bin\asevoxel_native.dll"
        if (-not (Test-Path $dllPath)) {
            Log-Error "Expected compiled library not found: $dllPath"
            exit 1
        }
        Log-Verbose "Verified native library exists: asevoxel_native.dll"
    }

    # Deduplicate list
    $paths = $paths | Select-Object -Unique
    Log-Verbose "Total files to include: $($paths.Count)"

    if ($paths.Count -eq 0) {
        Log-Info "No files found to add to archive" -ForegroundColor Yellow
        if (-not $DryRun) {
            [System.IO.Compression.ZipFile]::Open($tempZipFile,'Create').Dispose()
        } else {
            Log-DryRun "Would create empty archive"
        }
    } else {
        if (-not $DryRun) {
            # Create the zip file from the collected files
            Compress-Archive -LiteralPath $paths -DestinationPath $tempZipFile -Force
            Log-Verbose "Archive created successfully"
        } else {
            Log-DryRun "Would compress $($paths.Count) files into archive"
        }
    }

    if ((Test-Path $tempZipFile) -or $DryRun) {
        # Rename the .zip file to .aseprite-extension
        Log-Info "Renaming $tempZipFile to $outputFile..."
        if (-not $DryRun) {
            if (Test-Path $outputFile) {
                Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 200
            }
            Rename-Item -Path $tempZipFile -NewName $outputFile -Force

            if (Test-Path $outputFile) {
                Log-Info "$outputFile created successfully!" -ForegroundColor Green
                if ($VerbosityLevel -ge 2) {
                    $fileInfo = Get-Item $outputFile
                    Log-Verbose "Extension details:"
                    Log-Verbose "  Size: $($fileInfo.Length) bytes"
                    Log-Verbose "  Path: $($fileInfo.FullName)"
                }
            } else {
                Log-Error "Failed to rename zip file"
            }
        } else {
            Log-DryRun "Would rename to $outputFile"
        }
    } else {
        Log-Error "Failed to create zip file"
    }
} catch {
    Log-Error "Exception occurred: $_"
}

Log-Info "Done! Version: $newVersion"