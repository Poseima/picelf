#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Picelf.xcodeproj"
SCHEME="PicelfIOS"
SIMULATOR_NAME=""
SIMULATOR_UDID=""
CASE_ID=""
URL=""
PROFILE="generic"
STEPS="10"
SETTLE_MS="1300"
INITIAL_SETTLE_MS="4000"
PRE_RECORD_SETTLE_MS="5000"
DESTINATION_DIR="$ROOT_DIR/Tests/PicelfIOSTests/PrivateFixtures/Collected"
DERIVED_DATA_PATH="/tmp/PicelfIOS-SafariCollector"
CONFIG_PATH="/tmp/picelf-safari-collector-config.json"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") --case-id <id> --url <url> [options]

Options:
  --profile <profile>            Scroll profile: generic | youtube-search | youtube-watch | bilibili-search | bilibili-video
  --steps <count>                Number of swipe-up gestures (default: $STEPS)
  --settle-ms <ms>               Delay between swipes in milliseconds (default: $SETTLE_MS)
  --initial-settle-ms <ms>       Delay after opening Safari in milliseconds (default: $INITIAL_SETTLE_MS)
  --pre-record-settle-ms <ms>    Delay after opening the URL before video recording begins (default: $PRE_RECORD_SETTLE_MS)
  --simulator <name>             iPad simulator name (default: first available iPad)
  --udid <device-udid>           Explicit simulator UDID
  --destination-dir <path>       Directory for the captured mp4 (default: $DESTINATION_DIR)
  --derived-data-path <path>     DerivedData path for xcodebuild (default: $DERIVED_DATA_PATH)
EOF
}

resolve_udid() {
  local device_name="$1"
  xcrun simctl list devices available --json | python3 -c '
import json, sys
name = sys.argv[1]
devices = (device for group in json.load(sys.stdin)["devices"].values() for device in group)
print(next((device["udid"] for device in devices
            if device["isAvailable"] and device["name"].startswith("iPad")
            and (not name or device["name"] == name)), ""))
' "$device_name"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case-id)
      CASE_ID="$2"
      shift 2
      ;;
    --url)
      URL="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --steps)
      STEPS="$2"
      shift 2
      ;;
    --settle-ms)
      SETTLE_MS="$2"
      shift 2
      ;;
    --initial-settle-ms)
      INITIAL_SETTLE_MS="$2"
      shift 2
      ;;
    --pre-record-settle-ms)
      PRE_RECORD_SETTLE_MS="$2"
      shift 2
      ;;
    --simulator)
      SIMULATOR_NAME="$2"
      shift 2
      ;;
    --udid)
      SIMULATOR_UDID="$2"
      shift 2
      ;;
    --destination-dir)
      DESTINATION_DIR="$2"
      shift 2
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CASE_ID" || -z "$URL" ]]; then
  usage >&2
  exit 2
fi

if [[ -z "$SIMULATOR_UDID" ]]; then
  SIMULATOR_UDID="$(resolve_udid "$SIMULATOR_NAME")"
fi

if [[ -z "$SIMULATOR_UDID" ]]; then
  echo "Unable to resolve an available iPad simulator: ${SIMULATOR_NAME:-default}" >&2
  exit 3
fi

mkdir -p "$DESTINATION_DIR"
OUTPUT_PATH="$DESTINATION_DIR/$CASE_ID.mp4"
rm -f "$CONFIG_PATH"
if [[ ! -f "$OUTPUT_PATH" ]]; then
  : > "$OUTPUT_PATH"
fi

echo "[collector] simulator=${SIMULATOR_NAME:-iPad} udid=$SIMULATOR_UDID"
echo "[collector] url=$URL"
echo "[collector] output=$OUTPUT_PATH"

xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

echo "[collector] build-for-testing"
xcodebuild build-for-testing -project "$PROJECT_PATH" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:"PicelfIOSUITests/SimulatorSafariScrollCollectorUITests/test_collectSafariScrollingSession" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

cat >"$CONFIG_PATH" <<EOF
{
  "steps": $STEPS,
  "settleMS": $SETTLE_MS,
  "initialSettleMS": $INITIAL_SETTLE_MS,
  "profile": "$PROFILE"
}
EOF

xcrun simctl terminate "$SIMULATOR_UDID" com.apple.mobilesafari >/dev/null 2>&1 || true
rm -f "$OUTPUT_PATH"

xcrun simctl openurl "$SIMULATOR_UDID" "$URL"
sleep "$(awk "BEGIN { printf \"%.3f\", $PRE_RECORD_SETTLE_MS / 1000 }")"

RECORD_LOG="/tmp/picelf-safari-collector-$CASE_ID-record.log"
xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec=h264 "$OUTPUT_PATH" >"$RECORD_LOG" 2>&1 &
RECORD_PID=$!

cleanup() {
  if kill -0 "$RECORD_PID" >/dev/null 2>&1; then
    kill -INT "$RECORD_PID" >/dev/null 2>&1 || true
    wait "$RECORD_PID" || true
  fi
  rm -f "$CONFIG_PATH"
}

trap cleanup EXIT
sleep 1

xcodebuild test-without-building -project "$PROJECT_PATH" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -only-testing:"PicelfIOSUITests/SimulatorSafariScrollCollectorUITests/test_collectSafariScrollingSession" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

cleanup
trap - EXIT

if [[ ! -f "$OUTPUT_PATH" ]]; then
  echo "Collector finished but no mp4 was written: $OUTPUT_PATH" >&2
  exit 4
fi

FILE_SIZE="$(stat -f%z "$OUTPUT_PATH")"
echo "[collector] wrote $OUTPUT_PATH ($FILE_SIZE bytes)"
