#!/bin/bash
# Builds a Release archive of Verbatim for Apple Silicon, ad-hoc signs it with its entitlements, verifies the
# signature, and packages it as a zip and a DMG with a SHA256SUMS.txt file.
#
#   Scripts/package-release.sh <version> <build-number>
#
# Needs no Team ID, certificate or secret: the app is signed ad hoc ("Sign to Run Locally"), which is what makes
# App Sandbox and Hardened Runtime take effect. It is not signed with a Developer ID and not notarized.
#
# Environment: DERIVED_DATA (default DerivedData), OUTPUT_DIR (default build/release).
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <version> <build-number>, for example: $0 0.1.0 1" >&2
    exit 64
fi
version=$1
build_number=$2
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "The version must look like 1.2.3, got '$version'." >&2
    exit 64
fi
if [[ ! $build_number =~ ^[1-9][0-9]*$ ]]; then
    echo "The build number must be a positive integer, got '$build_number'." >&2
    exit 64
fi

cd "$(dirname "$0")/.."
derived_data=${DERIVED_DATA:-DerivedData}
output_dir=${OUTPUT_DIR:-build/release}
name="Verbatim-$version-macos-arm64"
work="$output_dir/work"
archive="$work/Verbatim.xcarchive"
stage="$work/Verbatim"
dmg_root="$work/dmg"
zip_file="$output_dir/$name.zip"
dmg_file="$output_dir/$name.dmg"
entitlements=Verbatim/Verbatim.entitlements

fail() {
    echo "error: $*" >&2
    exit 1
}

rm -rf "$work" "$zip_file" "$dmg_file" "$output_dir/SHA256SUMS.txt"
mkdir -p "$work"

echo "==> Archiving Verbatim $version ($build_number) for arm64"
# The version comes from the release tag, not from the project file. Manual signing with the "-" identity signs
# the app and everything nested in it ad hoc, inside out, with the target's entitlements and Hardened Runtime.
xcodebuild archive \
    -project Verbatim.xcodeproj \
    -scheme Verbatim \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    -disableAutomaticPackageResolution \
    -archivePath "$archive" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

app="$archive/Products/Applications/Verbatim.app"
[[ -d $app ]] || fail "the archive has no Verbatim.app at $app"

echo "==> Staging Verbatim.app, LICENSE and THIRD_PARTY_NOTICES.md"
mkdir -p "$stage"
ditto "$app" "$stage/Verbatim.app"
cp LICENSE THIRD_PARTY_NOTICES.md "$stage/"
# Local extended attributes such as com.apple.provenance would otherwise end up as __MACOSX entries in the zip.
xattr -cr "$stage"
app="$stage/Verbatim.app"

echo "==> Verifying the signature, entitlements and versions"
codesign --verify --deep --strict --verbose=2 "$app"
signature=$(codesign --display --verbose=2 "$app" 2>&1)
grep -q '^Signature=adhoc$' <<<"$signature" || fail "the app is not signed ad hoc"
grep -q '^CodeDirectory .*flags=.*runtime' <<<"$signature" || fail "Hardened Runtime is not enabled"
codesign --display --entitlements - --xml "$app" >"$work/signed.entitlements" 2>/dev/null
if ! diff -u <(plutil -p "$entitlements") <(plutil -p "$work/signed.entitlements"); then
    fail "the signed entitlements differ from $entitlements"
fi
info_plist="$app/Contents/Info.plist"
short_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
[[ $short_version == "$version" ]] || fail "CFBundleShortVersionString is $short_version, expected $version"
[[ $bundle_version == "$build_number" ]] || fail "CFBundleVersion is $bundle_version, expected $build_number"
architectures=$(lipo -archs "$app/Contents/MacOS/Verbatim")
[[ $architectures == arm64 ]] || fail "the executable is built for '$architectures', expected arm64"

echo "==> Creating $zip_file"
ditto -c -k --norsrc --noextattr --noacl --keepParent "$stage" "$zip_file"

echo "==> Creating $dmg_file"
mkdir -p "$dmg_root"
ditto "$stage" "$dmg_root"
ln -s /Applications "$dmg_root/Applications"
# hdiutil occasionally fails with "Resource busy" on CI runners; a retry is the usual remedy.
for attempt in 1 2 3; do
    if hdiutil create -volname "Verbatim $version" -srcfolder "$dmg_root" -fs HFS+ -format UDZO -ov "$dmg_file"; then
        break
    fi
    [[ $attempt -lt 3 ]] || fail "hdiutil could not create the DMG"
    echo "hdiutil failed, retrying in 5 seconds" >&2
    sleep 5
done
hdiutil verify "$dmg_file"

echo "==> Writing checksums"
(cd "$output_dir" && shasum -a 256 "$name.zip" "$name.dmg" >SHA256SUMS.txt && shasum -a 256 -c SHA256SUMS.txt)

echo "==> Done"
ls -l "$zip_file" "$dmg_file" "$output_dir/SHA256SUMS.txt"
