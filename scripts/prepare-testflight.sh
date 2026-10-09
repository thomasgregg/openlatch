#!/bin/bash
# Creates an archive and exports an IPA locally. Does not upload or invite testers.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
team_id="${TEAM_ID:?Set TEAM_ID to your Apple Developer team identifier}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid TEAM_ID" >&2; exit 1; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Use a three-part VERSION" >&2; exit 1; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo "BUILD_NUMBER must be an integer" >&2; exit 1; }

output="$project_root/work/testflight/$version-$build_number"
archive="$output/OpenLatch.xcarchive"
if [[ -e "$archive" ]]; then
    echo "Archive already exists at $archive. Use a new BUILD_NUMBER." >&2
    exit 1
fi
mkdir -p "$output"
cat > "$output/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>export</string>
    <key>signingStyle</key><string>automatic</string>
    <key>teamID</key><string>$team_id</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
    <key>uploadSymbols</key><true/>
</dict></plist>
EOF

xcodebuild -project "$project_root/OpenLatch.xcodeproj" -scheme OpenLatch \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$project_root/work/TestFlightDerivedData" \
    -archivePath "$archive" DEVELOPMENT_TEAM="$team_id" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    -allowProvisioningUpdates archive

xcodebuild -exportArchive -archivePath "$archive" \
    -exportPath "$output/ipa" -exportOptionsPlist "$output/ExportOptions.plist" \
    -allowProvisioningUpdates

echo "TestFlight package: $output/ipa/OpenLatch.ipa"
