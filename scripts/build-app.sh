#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_configuration="release"
task_universal=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            task_configuration="debug"
            shift
            ;;
        --universal)
            task_universal=true
            shift
            ;;
        *)
            printf '用法：%s [--debug] [--universal]\n' "$0" >&2
            exit 2
            ;;
    esac
done

cd "$task_root"
swift "$task_root/scripts/generate-icon.swift" "$task_root/Assets"
if [[ "$task_universal" == true ]]; then
    swift build --configuration "$task_configuration" --arch arm64 --arch x86_64 --product QuickKey
    task_bin_dir="$(swift build --configuration "$task_configuration" --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build --configuration "$task_configuration" --product QuickKey
    task_bin_dir="$(swift build --configuration "$task_configuration" --show-bin-path)"
fi
task_app="$task_root/dist/QuickKey.app"
task_staging="$task_root/dist/.QuickKey-$$.app"
trap 'rm -rf "$task_staging"' EXIT
mkdir -p "$task_staging/Contents/MacOS" "$task_staging/Contents/Resources"
cp "$task_bin_dir/QuickKey" "$task_staging/Contents/MacOS/QuickKey"
cp "$task_root/Sources/QuickKey/Info.plist" "$task_staging/Contents/Info.plist"
cp "$task_root/Assets/QuickKey.icns" "$task_staging/Contents/Resources/QuickKey.icns"
for task_localization in "$task_root"/Assets/Localization/*.lproj; do
    cp -R "$task_localization" "$task_staging/Contents/Resources/"
done

# ShortcutCatalog checks the app's Resources directory before SwiftPM's CLI accessor.
shopt -s nullglob
task_bundles=("$task_bin_dir"/*.bundle)
if [[ ${#task_bundles[@]} -eq 0 ]]; then
    printf '构建目录中缺少 SwiftPM 资源包。\n' >&2
    exit 1
fi
for task_bundle in "${task_bundles[@]}"; do
    cp -R "$task_bundle" "$task_staging/Contents/Resources/"
done

plutil -lint "$task_staging/Contents/Info.plist"
codesign --force --deep --sign - "$task_staging"
codesign --verify --deep --strict "$task_staging"

# Replace only this script's known build output, never any practice directory.
mkdir -p "$task_root/dist"
if [[ -e "$task_app" ]]; then
    rm -rf "$task_app"
fi
mv "$task_staging" "$task_app"
trap - EXIT
printf '\n已构建：%s\n打开：open "%s"\n' "$task_app" "$task_app"
