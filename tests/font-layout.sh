#!/usr/bin/env bash
# Exercise actual Toast/DeedButton geometry without starting a notification daemon.
set -euo pipefail
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_dir=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
ln -s "$shell_dir/Commons" "$test_dir/Commons"
ln -s "$shell_dir/Ui" "$test_dir/Ui"
ln -s "$plugin_dir" "$test_dir/Plugin"
cp "$plugin_dir/tests/FontLayout.qml" "$test_dir/shell.qml"
QT_QPA_PLATFORM=offscreen timeout 15 quickshell -p "$test_dir"
