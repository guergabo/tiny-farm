#!/bin/bash
set -euo pipefail

# Build the SwiftUI app into a .app bundle for the iOS Simulator.
# No Xcode project required: the core simulation and the renderer are compiled
# together as a single module.

cd "$(dirname "$0")/.."

if [ "${VERBOSE:-0}" = "1" ]; then set -x; fi

APP_NAME="TinyFarm"
DEPLOY_TARGET="${DEPLOY_TARGET:-17.0}"
ARCH="$(uname -m)"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "==> Cleaning"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR"

echo "==> Compiling for ${ARCH}-apple-ios${DEPLOY_TARGET}-simulator"
echo "    sdk=$SDK_PATH"
xcrun --sdk iphonesimulator swiftc \
    -target "${ARCH}-apple-ios${DEPLOY_TARGET}-simulator" \
    -sdk "$SDK_PATH" \
    -parse-as-library \
    -O \
    ${VERBOSE:+-v} \
    Sources/TinyFarmCore/FarmCore.swift \
    App/FarmApp.swift \
    -o "$APP_DIR/$APP_NAME"

echo "==> Adding Info.plist"
cp App/Info.plist "$APP_DIR/Info.plist"

echo "==> Built $APP_DIR"
ls -la "$APP_DIR"
