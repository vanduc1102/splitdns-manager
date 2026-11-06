#!/usr/bin/env bash
# Wraps "SplitDNS Manager.app" into a .dmg (with an /Applications shortcut) and a .zip.
#
# Environment:
#   VERSION            used in the file names (default: 0.0.0-dev)
#   CODESIGN_IDENTITY  signing identity for the .dmg; "-" leaves it unsigned (default: -)
#   DIST_DIR           directory holding the .app and receiving the outputs (default: dist)
set -euo pipefail

cd "$(dirname "$0")/.."

: "${VERSION:=0.0.0-dev}"
: "${CODESIGN_IDENTITY:=-}"
: "${DIST_DIR:=dist}"

app="$DIST_DIR/SplitDNS Manager.app"
if [ ! -d "$app" ]; then
    echo "error: $app not found; run Scripts/package-app.sh first" >&2
    exit 1
fi

dmg="$DIST_DIR/SplitDNSManager-$VERSION.dmg"
archive="$DIST_DIR/SplitDNSManager-$VERSION.zip"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/SplitDNS Manager.app"
ln -s /Applications "$staging/Applications"

echo "==> Creating $dmg"
rm -f "$dmg"
# hdiutil occasionally fails with "Resource busy" right after other disk activity, so retry a few times.
for attempt in 1 2 3; do
    if hdiutil create -volname "SplitDNS Manager" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"; then
        break
    fi
    if [ "$attempt" -eq 3 ]; then
        echo "error: hdiutil failed three times" >&2
        exit 1
    fi
    sleep 5
done

if [ "$CODESIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$dmg"
fi

echo "==> Creating $archive"
rm -f "$archive"
# --norsrc also drops extended attributes (e.g. com.apple.provenance), which would otherwise become
# stray ._* entries for extractors other than Archive Utility. The signature lives in _CodeSignature.
ditto -c -k --keepParent --norsrc --noqtn "$app" "$archive"

echo "==> Created:"
ls -lh "$dmg" "$archive"
