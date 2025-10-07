#!/bin/bash

# Navigate to the script's directory
cd "$(dirname "$0")"

# Read the current version from package.json
if [ -f "package.json" ]; then
    CURRENT_VERSION=$(grep -o '"version"\s*:\s*"[^"]*"' package.json | grep -o '[0-9][^"]*')
    echo "Current version: $CURRENT_VERSION"
    
    # Prompt for new version
    read -p "Enter new version (leave empty to keep $CURRENT_VERSION): " NEW_VERSION
    
    # Default to current version if empty
    if [ -z "$NEW_VERSION" ]; then
        NEW_VERSION=$CURRENT_VERSION
        echo "Keeping version $NEW_VERSION"
    else
        echo "Updating to version $NEW_VERSION"
        # Update version in package.json
        sed -i "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$NEW_VERSION\"/" package.json
    fi
else
    echo "Warning: package.json not found, version information unavailable"
fi

# Define the extension name
EXTENSION_NAME="AseVoxel-Viewer"

# Delete previous extension if it exists
if [ -f "$EXTENSION_NAME.aseprite-extension" ]; then
    echo "Deleting existing $EXTENSION_NAME.aseprite-extension..."
    rm "$EXTENSION_NAME.aseprite-extension"
fi

# Create a new zip archive with lua, json files and binary libraries
echo "Creating $EXTENSION_NAME.zip..."
zip -r "$EXTENSION_NAME.zip" *.lua *.json bin *.so *.dll lib

# Rename the .zip file to .aseprite-extension
echo "Renaming $EXTENSION_NAME.zip to $EXTENSION_NAME.aseprite-extension..."
mv "$EXTENSION_NAME.zip" "$EXTENSION_NAME.aseprite-extension"

# Make the file executable
chmod +x "$EXTENSION_NAME.aseprite-extension"

echo "$EXTENSION_NAME.aseprite-extension created successfully!"
