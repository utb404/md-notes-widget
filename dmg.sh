#!/bin/zsh
# Builds the app and packs it into "MD-Widgets-<version>.dmg".
#   VERSION=1.2 ./dmg.sh
# Optional, for a notarized DMG that opens without Gatekeeper warnings:
#   SIGN_IDENTITY   e.g. "Developer ID Application"
#   NOTARY_PROFILE  keychain profile from `xcrun notarytool store-credentials`
#   or NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER  App Store Connect API key (.p8 path)
set -euo pipefail
cd "$(dirname "$0")"

export VERSION=${VERSION:-1.0}
./build.sh

DMG="MD-Widgets-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "MD Widgets.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
# hdiutil create is deprecated on macOS 27 and fails intermittently there
if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from --format UDZO --volumeName "MD Widgets" "$STAGE" "$PWD/$DMG"
else
    hdiutil create -volname "MD Widgets" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
fi

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if [[ -n "${NOTARY_KEY:-}" ]]; then
        AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
        AUTH=(--keychain-profile "$NOTARY_PROFILE")
    else
        AUTH=()
    fi
    if (( ${#AUTH} )); then
        xcrun notarytool submit "$DMG" --wait "${AUTH[@]}"
        xcrun stapler staple "$DMG"
    fi
fi
echo "Packed $PWD/$DMG"
