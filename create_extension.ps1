# Navigate to the directory and store the script location
$scriptDir = (Split-Path -Parent $MyInvocation.MyCommand.Definition)
Set-Location -Path $scriptDir

# Read the current version from package.json
if (Test-Path "package.json") {
    $packageContent = Get-Content "package.json" -Raw | ConvertFrom-Json
    $currentVersion = $packageContent.version
    Write-Host "Current version: $currentVersion"
    
    # Prompt for new version
    $newVersion = Read-Host "Enter new version (leave empty to keep $currentVersion)"
    
    # Default to current version if empty
    if ([string]::IsNullOrWhiteSpace($newVersion)) {
        $newVersion = $currentVersion
        Write-Host "Keeping version $newVersion"
    }
    else {
        Write-Host "Updating to version $newVersion"
        # Update version in package.json
        $packageContent.version = $newVersion
        $packageContent | ConvertTo-Json -Depth 10 | Set-Content "package.json"
    }
}
else {
    Write-Host "Warning: package.json not found, version information unavailable"
}

# Define extension name 
$extensionName = "AseVoxel-Viewer"

# Define file names with full paths to ensure correct location
$tempZipFile = Join-Path -Path $scriptDir -ChildPath "$extensionName.zip"
$outputFile = Join-Path -Path $scriptDir -ChildPath "$extensionName.aseprite-extension"

# Delete any existing files
if (Test-Path $tempZipFile) {
    Write-Host "Removing existing $tempZipFile"
    Remove-Item $tempZipFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1  # Give time for file handle to release
}

if (Test-Path $outputFile) {
    Write-Host "Removing existing $outputFile"
    Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1  # Give time for file handle to release
}

# Create a new zip archive using PowerShell's Compress-Archive
Write-Host "Creating $tempZipFile..."
try {
    # Collect top-level lua/json files
    $paths = @()
    $paths += Get-ChildItem -Path $scriptDir -Filter *.lua -File -Recurse:$false | ForEach-Object { $_.FullName }
    $paths += Get-ChildItem -Path $scriptDir -Filter *.json -File -Recurse:$false | ForEach-Object { $_.FullName }

    # Include bin and lib directories if present (all files inside)
    $binDir = Join-Path $scriptDir "bin"
    if (Test-Path $binDir) {
        $paths += Get-ChildItem -Path $binDir -Recurse -File | ForEach-Object { $_.FullName }
    }
    $libDir = Join-Path $scriptDir "lib"
    if (Test-Path $libDir) {
        $paths += Get-ChildItem -Path $libDir -Recurse -File | ForEach-Object { $_.FullName }
    }

    # Include any native libraries (.so, .dll) anywhere under the script dir
    $paths += Get-ChildItem -Path $scriptDir -Recurse -Include *.so,*.dll -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }

    # Deduplicate list
    $paths = $paths | Select-Object -Unique

    if ($paths.Count -eq 0) {
        Write-Host "No files found to add to archive; creating empty archive" -ForegroundColor Yellow
        # create an empty zip
        [System.IO.Compression.ZipFile]::Open($tempZipFile,'Create').Dispose()
    } else {
        # Create the zip file from the collected files
        Compress-Archive -LiteralPath $paths -DestinationPath $tempZipFile -Force
    }

    if (Test-Path $tempZipFile) {
        # Rename the .zip file to .aseprite-extension
        Write-Host "Renaming $tempZipFile to $outputFile..."
        if (Test-Path $outputFile) {
            Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 200
        }
        Rename-Item -Path $tempZipFile -NewName $outputFile -Force

        if (Test-Path $outputFile) {
            Write-Host "$outputFile created successfully!" -ForegroundColor Green
        } else {
            Write-Host "Error: Failed to rename zip file" -ForegroundColor Red
        }
    } else {
        Write-Host "Error: Failed to create zip file" -ForegroundColor Red
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
}