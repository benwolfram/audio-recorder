#!/bin/bash
# Builds "build/Audio Recorder.app". Usage: ./build.sh [--open]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/Audio Recorder.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AudioRecorder "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
cp assets/AppIcon.icns "$APP/Contents/Resources/"

# A real signing identity keeps privacy permissions across rebuilds; ad-hoc re-prompts each build.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/{print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
[[ "${1:-}" == "--open" ]] && open "$APP"
