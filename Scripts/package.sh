#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$project_dir/Scripts/build.sh"
mkdir -p "$project_dir/Distribution"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/awake-lite.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
/usr/bin/ditto "$project_dir/build/Build/Products/Release/AwakeLite.app" "$stage_dir/醒着Lite.app"
ln -s /Applications "$stage_dir/Applications"
cp "$project_dir/README.md" "$project_dir/LICENSE" "$project_dir/安装说明.txt" "$stage_dir/"
hdiutil create -volname '醒着Lite' -srcfolder "$stage_dir" -format UDZO -ov "$project_dir/Distribution/醒着Lite-0.2.0-未公证.dmg"
hdiutil verify "$project_dir/Distribution/醒着Lite-0.2.0-未公证.dmg"
(
 cd "$project_dir/Distribution"
 shasum -a 256 "醒着Lite-0.2.0-未公证.dmg"
) > "$project_dir/Distribution/醒着Lite-0.2.0-未公证.dmg.sha256"
