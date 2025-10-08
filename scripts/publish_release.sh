#!/usr/bin/env bash
set -euo pipefail

# Usage: GITHUB_TOKEN=... ./publish_release.sh owner repo tag

if [ -z "${GITHUB_TOKEN-}" ]; then
  echo "GITHUB_TOKEN environment variable is required to authenticate with the GitHub API"
  exit 1
fi

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 owner repo tag"
  exit 1
fi

OWNER="$1"
REPO="$2"
TAG="$3"

EXT_FILE="AseVoxel-Viewer.aseprite-extension"
SRC_FILE="Source.zip"
NOTES_FILE="release_notes/v1.0.md"

if [ ! -f "$EXT_FILE" ] || [ ! -f "$SRC_FILE" ]; then
  echo "Expected files not found: $EXT_FILE and $SRC_FILE must exist in the repo root"
  exit 1
fi

BODY=$(cat "$NOTES_FILE" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')

echo "Creating release $TAG for $OWNER/$REPO..."
CREATE_RESP=$(curl -s -X POST "https://api.github.com/repos/${OWNER}/${REPO}/releases" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "tag_name": "${TAG}",
  "name": "${TAG}",
  "body": $(cat "$NOTES_FILE" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))'),
  "draft": false,
  "prerelease": false
}
EOF
)

RELEASE_ID=$(echo "$CREATE_RESP" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('id',''))")
UPLOAD_URL_BASE="$(echo "$CREATE_RESP" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('upload_url','').split('{')[0])")"

if [ -z "$RELEASE_ID" ] || [ -z "$UPLOAD_URL_BASE" ]; then
  echo "Failed to create release. Response:"
  echo "$CREATE_RESP"
  exit 1
fi

echo "Release created (id=$RELEASE_ID). Uploading assets..."

for file in "$EXT_FILE" "$SRC_FILE"; do
  NAME=$(basename "$file")
  echo "Uploading $NAME..."
  curl -s --data-binary "@$file" -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/octet-stream" "${UPLOAD_URL_BASE}?name=${NAME}"
done

echo "Done. Release: https://github.com/${OWNER}/${REPO}/releases/tag/${TAG}"
