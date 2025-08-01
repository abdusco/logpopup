#!/usr/bin/env bash
set -euo pipefail

# Usage: Set ARCH and VERSION env vars before running, e.g.:
#   ARCH=arm64 VERSION=1.2.3 ./build.sh

ARCH="${ARCH:-arm64}"
VERSION="${VERSION:-dev}"

# Remove 'v' prefix if present in version
echo "Building for arch: $ARCH, version: $VERSION"
VERSION_CLEAN=${VERSION#v}


# Replace currentVersion in LogPopup.swift with the build version
sed "s/var version = \".*\"/var version = \"$VERSION_CLEAN\"/" LogPopup.swift > LogPopup.build.swift


# Build the binary with version info
swiftc -o logpopup-${ARCH} LogPopup.build.swift \
  -framework Cocoa -framework WebKit -framework Foundation -framework AppKit

# Clean up temporary build file
rm LogPopup.build.swift


echo "Built logpopup-${ARCH} with version $VERSION_CLEAN"
