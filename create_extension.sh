#!/bin/bash

# Default parameter values
VERBOSITY=1  # 0=quiet, 1=normal, 2=verbose
COMPILE=1    # 1=compile, 0=skip
VERSION_MODE="prompt"  # prompt, auto, keep, manual
DRY_RUN=0
CLEAN=0
NEW_VERSION=""

# Function to print usage
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Creates an Aseprite extension package with optional compilation and versioning.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Verbose output (can be used multiple times)
    -q, --quiet             Quiet mode (minimal output)
    
    -c, --compile           Compile native libraries (default)
    -C, --no-compile        Skip compilation
    
    -p, --prompt            Prompt for version (default)
    -a, --auto-version      Auto-increment patch version
    -k, --keep-version      Keep current version
    -V, --version VERSION   Set specific version
    
    -n, --dry-run           Show what would be done without doing it
    --clean                 Clean build artifacts before building
    
EXAMPLES:
    $0                              # Interactive mode
    $0 -q -k -C                     # Quiet, keep version, no compile
    $0 -v -a                        # Verbose, auto-increment version
    $0 -V 1.2.3                     # Set version to 1.2.3
    $0 --dry-run --clean            # Preview clean build

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--verbose)
            VERBOSITY=$((VERBOSITY + 1))
            shift
            ;;
        -q|--quiet)
            VERBOSITY=0
            shift
            ;;
        -c|--compile)
            COMPILE=1
            shift
            ;;
        -C|--no-compile)
            COMPILE=0
            shift
            ;;
        -p|--prompt)
            VERSION_MODE="prompt"
            shift
            ;;
        -a|--auto-version)
            VERSION_MODE="auto"
            shift
            ;;
        -k|--keep-version)
            VERSION_MODE="keep"
            shift
            ;;
        -V|--version)
            VERSION_MODE="manual"
            NEW_VERSION="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    if [ $VERBOSITY -ge 1 ]; then
        echo "$@"
    fi
}

log_verbose() {
    if [ $VERBOSITY -ge 2 ]; then
        echo "[VERBOSE] $@"
    fi
}

log_error() {
    echo "[ERROR] $@" >&2
}

# Navigate to the script's directory
cd "$(dirname "$0")"
log_verbose "Working directory: $(pwd)"

# Clean build artifacts if requested
if [ $CLEAN -eq 1 ]; then
    log_info "Cleaning build artifacts..."
    if [ $DRY_RUN -eq 0 ]; then
        rm -f render/bin/asevoxel_native.so render/bin/asevoxel_native.dll
        rm -f libasevoxel_native.a
        log_verbose "Removed native library files"
    else
        log_info "[DRY-RUN] Would remove native library files"
    fi
fi

# Version management
if [ -f "package.json" ]; then
    CURRENT_VERSION=$(grep -o '"version"\s*:\s*"[^"]*"' package.json | grep -o '[0-9][^"]*')
    log_info "Current version: $CURRENT_VERSION"
    
    case $VERSION_MODE in
        prompt)
            read -p "Enter new version (leave empty to keep $CURRENT_VERSION): " NEW_VERSION
            if [ -z "$NEW_VERSION" ]; then
                NEW_VERSION=$CURRENT_VERSION
                log_info "Keeping version $NEW_VERSION"
            else
                log_info "Updating to version $NEW_VERSION"
                if [ $DRY_RUN -eq 0 ]; then
                    sed -i "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" package.json
                else
                    log_info "[DRY-RUN] Would update version to $NEW_VERSION"
                fi
            fi
            ;;
        auto)
            # Auto-increment patch version
            IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
            MAJOR="${VERSION_PARTS[0]}"
            MINOR="${VERSION_PARTS[1]}"
            PATCH="${VERSION_PARTS[2]}"
            PATCH=$((PATCH + 1))
            NEW_VERSION="$MAJOR.$MINOR.$PATCH"
            log_info "Auto-incrementing version to $NEW_VERSION"
            if [ $DRY_RUN -eq 0 ]; then
                sed -i "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" package.json
            else
                log_info "[DRY-RUN] Would update version to $NEW_VERSION"
            fi
            ;;
        keep)
            NEW_VERSION=$CURRENT_VERSION
            log_info "Keeping version $NEW_VERSION"
            ;;
        manual)
            log_info "Setting version to $NEW_VERSION"
            if [ $DRY_RUN -eq 0 ]; then
                sed -i "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" package.json
            else
                log_info "[DRY-RUN] Would update version to $NEW_VERSION"
            fi
            ;;
    esac
else
    log_error "package.json not found, version information unavailable"
    NEW_VERSION="unknown"
fi

# Define the extension name
EXTENSION_NAME="AseVoxel-Viewer"

# Delete previous extension if it exists
if [ -f "$EXTENSION_NAME.aseprite-extension" ]; then
    log_info "Deleting existing $EXTENSION_NAME.aseprite-extension..."
    if [ $DRY_RUN -eq 0 ]; then
        rm "$EXTENSION_NAME.aseprite-extension"
    else
        log_info "[DRY-RUN] Would delete $EXTENSION_NAME.aseprite-extension"
    fi
fi

# Compile native libraries
if [ $COMPILE -eq 1 ]; then
    log_info "Compiling native libraries..."
    
    # Create bin directory if it doesn't exist
    mkdir -p render/bin
    log_verbose "Created render/bin directory"
    
    # Compile Linux library
    log_verbose "Compiling Linux native library (asevoxel_native.so)..."
    if [ $DRY_RUN -eq 0 ]; then
        # Check if source file exists
        if [ ! -f "asevoxel_native.cpp" ]; then
            log_error "Source file asevoxel_native.cpp not found"
            exit 1
        fi
        
        # Check if pkg-config is available
        if ! command -v pkg-config &> /dev/null; then
            log_error "pkg-config not found. Please install pkg-config."
            exit 1
        fi
        
        # Check if Lua development files are available
        if ! pkg-config --exists lua5.4; then
            log_error "Lua 5.4 development files not found. Try: sudo apt-get install liblua5.4-dev"
            exit 1
        fi
        
        log_verbose "Compiler flags: $(pkg-config --cflags lua5.4)"
        log_verbose "Linker flags: $(pkg-config --libs lua5.4)"
        
        if g++ -shared -fPIC $(pkg-config --cflags lua5.4) -o render/bin/asevoxel_native.so asevoxel_native.cpp $(pkg-config --libs lua5.4) 2>&1 | tee /dev/stderr; then
            log_info "✓ Built asevoxel_native.so"
            if [ $VERBOSITY -ge 2 ]; then
                ls -lh render/bin/asevoxel_native.so
            fi
        else
            log_error "Failed to build asevoxel_native.so"
            exit 1
        fi
    else
        log_info "[DRY-RUN] Would compile asevoxel_native.so"
    fi
    
    # Compile Windows library (cross-compilation)
    log_verbose "Compiling Windows native library (asevoxel_native.dll)..."
    if [ $DRY_RUN -eq 0 ]; then
        # Check if MinGW cross-compiler is available
        if ! command -v x86_64-w64-mingw32-g++ &> /dev/null; then
            log_error "MinGW cross-compiler not found. Try: sudo apt-get install mingw-w64"
            exit 1
        fi
        
        # Check if Windows Lua libraries exist
        if [ ! -d "thirdparty/lua-win/include" ] || [ ! -d "thirdparty/lua-win/lib" ]; then
            log_error "Windows Lua libraries not found in thirdparty/lua-win/"
            log_error "Please ensure thirdparty/lua-win/include and thirdparty/lua-win/lib exist"
            exit 1
        fi
        
        log_verbose "Using Lua headers from: thirdparty/lua-win/include"
        log_verbose "Using Lua library from: thirdparty/lua-win/lib"
        
        if x86_64-w64-mingw32-g++ -O2 -std=c++17 -D_WIN32_WINNT=0x0601 -shared asevoxel_native.cpp \
           -Ithirdparty/lua-win/include -Lthirdparty/lua-win/lib -llua54 \
           -static -static-libgcc -static-libstdc++ \
           -Wl,--out-implib,libasevoxel_native.a -o render/bin/asevoxel_native.dll 2>&1 | tee /dev/stderr; then
            log_info "✓ Built asevoxel_native.dll"
            if [ $VERBOSITY -ge 2 ]; then
                ls -lh render/bin/asevoxel_native.dll
            fi
        else
            log_error "Failed to build asevoxel_native.dll"
            exit 1
        fi
    else
        log_info "[DRY-RUN] Would compile asevoxel_native.dll"
    fi
else
    log_info "Skipping compilation (--no-compile flag set)"
fi

# Create a new zip archive with lua, json files and binary libraries
log_info "Creating $EXTENSION_NAME.zip..."
log_verbose "Including: *.lua, *.json, io/, math/, render/, utils/, dialog/, core/"

if [ $DRY_RUN -eq 0 ]; then
    # Verify that render/bin directory exists and has libraries
    if [ $COMPILE -eq 1 ]; then
        if [ ! -f "render/bin/asevoxel_native.so" ] && [ ! -f "render/bin/asevoxel_native.dll" ]; then
            log_error "No compiled libraries found in render/bin/"
            exit 1
        fi
        log_verbose "Found compiled libraries:"
        [ -f "render/bin/asevoxel_native.so" ] && log_verbose "  - asevoxel_native.so"
        [ -f "render/bin/asevoxel_native.dll" ] && log_verbose "  - asevoxel_native.dll"
    fi
    
    # Create zip with appropriate verbosity
    if [ $VERBOSITY -ge 2 ]; then
        zip -r "$EXTENSION_NAME.zip" *.lua *.json io math render utils dialog core
    else
        zip -q -r "$EXTENSION_NAME.zip" *.lua *.json io math render utils dialog core
    fi
    
    # Rename the .zip file to .aseprite-extension
    log_info "Renaming $EXTENSION_NAME.zip to $EXTENSION_NAME.aseprite-extension..."
    mv "$EXTENSION_NAME.zip" "$EXTENSION_NAME.aseprite-extension"
    
    # Make the file executable
    chmod +x "$EXTENSION_NAME.aseprite-extension"
    
    log_info "$EXTENSION_NAME.aseprite-extension created successfully!"
    if [ $VERBOSITY -ge 2 ]; then
        log_verbose "Extension details:"
        ls -lh "$EXTENSION_NAME.aseprite-extension"
    fi
else
    log_info "[DRY-RUN] Would create $EXTENSION_NAME.zip"
    log_info "[DRY-RUN] Would rename to $EXTENSION_NAME.aseprite-extension"
    log_info "[DRY-RUN] Would make file executable"
fi

log_info "Done! Version: $NEW_VERSION"
