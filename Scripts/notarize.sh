#!/usr/bin/env bash
# Sends an app or disk image to Apple's notary service, waits for the verdict and staples the ticket.
# The target must already be signed with a Developer ID (see CODESIGN_IDENTITY in package-app.sh).
#
# Usage: Scripts/notarize.sh <path to .app or .dmg>
#
# Environment (all required):
#   NOTARY_APPLE_ID  Apple ID of the developer account
#   NOTARY_TEAM_ID   ten character team ID
#   NOTARY_PASSWORD  app-specific password for that Apple ID, not the account password
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <path to .app or .dmg>" >&2
    exit 2
fi
target="${1%/}"

: "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID is required}"
: "${NOTARY_TEAM_ID:?NOTARY_TEAM_ID is required}"
: "${NOTARY_PASSWORD:?NOTARY_PASSWORD is required}"

if [ ! -e "$target" ]; then
    echo "error: $target does not exist" >&2
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

case "$target" in
    *.app)
        # The notary service takes archives, not bundles.
        submission="$work/$(basename "$target" .app).zip"
        ditto -c -k --keepParent "$target" "$submission"
        ;;
    *.dmg)
        submission="$target"
        ;;
    *)
        echo "error: $target must be an .app or a .dmg" >&2
        exit 2
        ;;
esac

credentials=(--apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD")

echo "==> Submitting $(basename "$target") for notarization"
result="$(xcrun notarytool submit "$submission" "${credentials[@]}" --wait --timeout 30m --output-format json)"
status="$(printf '%s' "$result" | plutil -extract status raw -o - -)"
submission_id="$(printf '%s' "$result" | plutil -extract id raw -o - -)"
echo "    submission $submission_id finished as: $status"

if [ "$status" != "Accepted" ]; then
    echo "error: notarization was not accepted; Apple's log follows" >&2
    xcrun notarytool log "$submission_id" "${credentials[@]}" >&2 || true
    exit 1
fi

echo "==> Stapling the ticket"
xcrun stapler staple "$target"
xcrun stapler validate "$target"

echo "==> Checking that Gatekeeper accepts it"
if [ "${target##*.}" = "app" ]; then
    spctl --assess --type execute --verbose=2 "$target"
else
    spctl --assess --type open --context context:primary-signature --verbose=2 "$target"
fi
