#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$project_dir/Scripts/generate_project.py"
signing=()
if [[ -n "${AWAKE_LITE_TEAM:-}" ]]; then
 signing+=("DEVELOPMENT_TEAM=$AWAKE_LITE_TEAM" "CODE_SIGN_IDENTITY=${AWAKE_LITE_IDENTITY:-Apple Development}")
fi
xcodebuild -project "$project_dir/AwakeLite.xcodeproj" -scheme AwakeLite -configuration Release \
 -derivedDataPath "$project_dir/build" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO "${signing[@]}" build
app_path="$project_dir/build/Build/Products/Release/AwakeLite.app"
"$app_path/Contents/MacOS/AwakeLite" --self-test
"$app_path/Contents/MacOS/AwakeLiteLidHelper" --self-test
codesign --verify --deep --strict "$app_path"
print "Built: $app_path"
