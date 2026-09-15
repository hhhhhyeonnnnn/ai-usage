#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
swift build --configuration debug --product AIUsage
binary_dir="$(swift build --configuration debug --show-bin-path)"
app_dir="$project_dir/build/AI Usage.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/AIUsage" "$app_dir/Contents/MacOS/AIUsage"
cp AIUsage/Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
print -r -- "App: $app_dir"
