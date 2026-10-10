#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mode="${1:-mac-test}"
python3 scripts/ci/verify-distribution.py
xcodegen generate
common=(-project Picelf.xcodeproj -clonedSourcePackagesDirPath .build/packages CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
case "$mode" in
  mac-build)
    xcodebuild build "${common[@]}" -scheme Picelf -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/mac ;;
  mac-test)
    xcodebuild test "${common[@]}" -scheme Picelf -destination 'platform=macOS' -derivedDataPath .build/mac -only-testing:PicelfTests -parallel-testing-enabled NO ;;
  ios-build)
    xcodebuild build "${common[@]}" -scheme PicelfIOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios ;;
  ios-test)
    destination="${IOS_TEST_DESTINATION:-}"
    if [[ -z "$destination" ]]; then
      device_id="$(xcrun simctl list devices available --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for group in d["devices"].values() for x in group if x["isAvailable"] and x["name"].startswith("iPhone")))')"
      destination="platform=iOS Simulator,id=$device_id"
    fi
    xcodebuild test "${common[@]}" -scheme PicelfIOS -destination "$destination" -derivedDataPath .build/ios -only-testing:PicelfIOSTests -parallel-testing-enabled NO ;;
  *) echo "Usage: $0 {mac-build|mac-test|ios-build|ios-test}" >&2; exit 2 ;;
esac
