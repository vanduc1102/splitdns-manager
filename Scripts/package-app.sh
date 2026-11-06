#!/usr/bin/env bash
# Builds a universal "SplitDNS Manager.app" from the SwiftPM executable and signs it.
#
# Environment:
#   VERSION            version to stamp into the app, e.g. 1.2.3 or 1.2.3-rc.1 (default: 0.0.0-dev)
#   BUILD_NUMBER       CFBundleVersion (default: 1)
#   BUNDLE_ID          bundle identifier (default: io.github.vanduc1102.splitdns-manager)
#   ARCHS              architectures to build, space separated (default: "arm64 x86_64")
#   CODESIGN_IDENTITY  signing identity; "-" signs ad hoc, which needs no Apple account (default: -)
#   DIST_DIR           output directory (default: dist)
set -euo pipefail

cd "$(dirname "$0")/.."

: "${VERSION:=0.0.0-dev}"
: "${BUILD_NUMBER:=1}"
: "${BUNDLE_ID:=io.github.vanduc1102.splitdns-manager}"
: "${ARCHS:=arm64 x86_64}"
: "${CODESIGN_IDENTITY:=-}"
: "${DIST_DIR:=dist}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]]; then
    echo "error: VERSION '$VERSION' must look like 1.2.3 or 1.2.3-rc.1" >&2
    exit 1
fi
if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: BUILD_NUMBER '$BUILD_NUMBER' must be a number" >&2
    exit 1
fi
# CFBundleShortVersionString only allows up to three dot-separated integers.
short_version="${VERSION%%[-+]*}"

arch_flags=()
for arch in $ARCHS; do
    arch_flags+=(--arch "$arch")
done

echo "==> Building $VERSION ($ARCHS)"
swift build --configuration release --product SplitDNSManager "${arch_flags[@]}"
bin_dir="$(swift build --configuration release --product SplitDNSManager "${arch_flags[@]}" --show-bin-path)"

app="$DIST_DIR/SplitDNS Manager.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/SplitDNSManager" "$app/Contents/MacOS/SplitDNSManager"
cp Packaging/Info.plist "$app/Contents/Info.plist"
cp Packaging/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

plist="$app/Contents/Info.plist"
set_plist() {
    /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist"
}
set_plist CFBundleIdentifier "$BUNDLE_ID"
set_plist CFBundleShortVersionString "$short_version"
set_plist CFBundleVersion "$BUILD_NUMBER"
plutil -lint "$plist" >/dev/null

actual_archs="$(lipo -archs "$app/Contents/MacOS/SplitDNSManager")"
for arch in $ARCHS; do
    if [[ " $actual_archs " != *" $arch "* ]]; then
        echo "error: the executable lacks $arch (it has: $actual_archs)" >&2
        exit 1
    fi
done

echo "==> Signing with '$CODESIGN_IDENTITY'"
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$app"
else
    # The hardened runtime and a secure timestamp are what notarization requires.
    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp "$app"
fi
codesign --verify --strict --verbose=2 "$app"

echo "==> Created $app ($actual_archs)"
