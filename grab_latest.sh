#!/usr/bin/env bash
set -euo pipefail

MANIFEST_FILE="net.imput.helium.yml"
METADATA_FILE="net.imput.helium.metainfo.xml"
REPO_URL="https://github.com/imputnet/helium-linux/releases/download"

if [ -f "fetch.config.yml" ]; then
    ALLOW_PRERELEASE=$(grep -m1 'allow-prerelease:' fetch.config.yml | awk '{print $2}')
else
    ALLOW_PRERELEASE="false"
fi

echo "   Fetching releases from GitHub..."
RELEASES_JSON=$(curl -s https://api.github.com/repos/imputnet/helium-linux/releases)

read -r LATEST_VERSION IS_PRERELEASE <<< $(echo "$RELEASES_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    allow_pre = '${ALLOW_PRERELEASE}' == 'true'
    if not isinstance(data, list):
        print('null false')
        sys.exit(0)
    candidates = [r for r in data if r.get('tag_name') and (allow_pre or not r.get('prerelease', False))]
    if candidates:
        latest = sorted(candidates, key=lambda x: x.get('created_at', ''))[-1]
        print(f\"{latest['tag_name']} {str(latest['prerelease']).lower()}\")
    else:
        print('null false')
except Exception:
    print('null false')
")

if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
  echo "   Error: Failed to fetch valid version tag from GitHub."
  exit 1
fi

CURRENT_VERSION=$(grep -Po 'helium-[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' "$MANIFEST_FILE" | head -n1 | grep -Po '[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?')
CURRENT_DATE=$(date '+%Y-%m-%d')

echo "version: $CURRENT_VERSION" > version.txt
echo "prerelease: $IS_PRERELEASE" >> version.txt

if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
  echo "   Manifest is already up to date ($CURRENT_VERSION)."
  # We exit successfully; the workflow will see no git diff and stop.
  exit 0
else
  echo "   Updating manifest from $CURRENT_VERSION → $LATEST_VERSION"
  if [[ "$OSTYPE" == "darwin"* ]]; then SED_INPLACE="sed -i ''"; else SED_INPLACE="sed -i"; fi

  # --- Update Manifest Files ---
  $SED_INPLACE -E "s|(helium-linux/releases/download/)$CURRENT_VERSION|\1$LATEST_VERSION|g" "$MANIFEST_FILE"
  $SED_INPLACE -E "s|(helium-$CURRENT_VERSION-x86_64_linux)|helium-$LATEST_VERSION-x86_64_linux|g" "$MANIFEST_FILE"
  $SED_INPLACE -E "s|(helium-$CURRENT_VERSION-arm64_linux)|helium-$LATEST_VERSION-arm64_linux|g" "$MANIFEST_FILE"
  
  $SED_INPLACE -E "s|(<release version=['\"])$CURRENT_VERSION|\1$LATEST_VERSION|g" "$METADATA_FILE"
  $SED_INPLACE -E "s|(<release date=['\"])[0-9]{4}-[0-9]{2}-[0-9]{2}|\1$CURRENT_DATE|g" "$METADATA_FILE"
  
  # Update the version tracker
  echo "version: $LATEST_VERSION" > version.txt
  echo "prerelease: $IS_PRERELEASE" >> version.txt
fi

echo "   Downloading binaries to compute SHA256..."

DL_X86="$REPO_URL/$LATEST_VERSION/helium-$LATEST_VERSION-x86_64_linux.tar.xz"
TMP_X86=$(mktemp)
curl -L -s -o "$TMP_X86" "$DL_X86"
NEW_SHA256_X86=$(sha256sum "$TMP_X86" | awk '{print $1}')
rm -f "$TMP_X86"

DL_ARM="$REPO_URL/$LATEST_VERSION/helium-$LATEST_VERSION-arm64_linux.tar.xz"
TMP_ARM=$(mktemp)
curl -L -s -o "$TMP_ARM" "$DL_ARM"
NEW_SHA256_ARM=$(sha256sum "$TMP_ARM" | awk '{print $1}')
rm -f "$TMP_ARM"

if [[ -z "$NEW_SHA256_X86" || -z "$NEW_SHA256_ARM" ]]; then
  echo "   Failed to compute SHA256 checksums."
  exit 1
fi

echo "   New x86_64 SHA256: $NEW_SHA256_X86"
echo "   New aarch64 SHA256: $NEW_SHA256_ARM"

# This finds the URL line for each architecture, moves to the next line (n), and replaces the hash.
$SED_INPLACE -E "/x86_64_linux\.tar\.xz/{n;s/sha256: [a-f0-9]+/sha256: $NEW_SHA256_X86/;}" "$MANIFEST_FILE"
$SED_INPLACE -E "/arm64_linux\.tar\.xz/{n;s/sha256: [a-f0-9]+/sha256: $NEW_SHA256_ARM/;}" "$MANIFEST_FILE"

echo "   Manifest updated successfully."
