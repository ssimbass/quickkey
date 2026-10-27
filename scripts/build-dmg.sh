#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_skip_build=false
if [[ "${1:-}" == "--skip-build" ]]; then
    task_skip_build=true
    shift
fi
if [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--skip-build]\n' "$0" >&2
    exit 2
fi
if [[ "$task_skip_build" == false ]]; then
    "$task_root/scripts/build-app.sh"
fi

task_app="$task_root/dist/QuickKey.app"
codesign --verify --deep --strict "$task_app"
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")"
task_arch="$(lipo -archs "$task_app/Contents/MacOS/QuickKey")"
if [[ "$task_arch" == *" "* ]]; then
    task_arch="universal"
fi
task_name="QuickKey-${task_version}-macOS-${task_arch}.dmg"
task_staging="$(mktemp -d "$task_root/dist/.dmg.XXXXXX")"
trap 'rm -rf "$task_staging"' EXIT
mkdir "$task_staging/content"
ditto "$task_app" "$task_staging/content/QuickKey.app"
ln -s /Applications "$task_staging/content/Applications"
hdiutil create -volname "QuickKey $task_version" \
    -srcfolder "$task_staging/content" -format UDZO \
    "$task_staging/QuickKey.dmg"
hdiutil verify "$task_staging/QuickKey.dmg"
mv "$task_staging/QuickKey.dmg" "$task_root/dist/$task_name"
(
    cd "$task_root/dist"
    shasum -a 256 "$task_name" > "$task_name.sha256"
)
printf '\nDMG: %s\nSHA256: %s\n' "$task_root/dist/$task_name" "$task_root/dist/$task_name.sha256"
