#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
install_dir=$config_home/quickshell/image-picker
picker_config_dir=$config_home/image-picker

mkdir -p "$install_dir" "$picker_config_dir"
install -m 644 \
  "$source_dir/ImagePicker.qml" \
  "$source_dir/ImagePickerModel.js" \
  "$source_dir/shell.qml" \
  "$source_dir/manifest.json" \
  "$install_dir/"
install -m 755 "$source_dir/apply-wallpaper.sh" "$install_dir/apply-wallpaper.sh"
install -m 755 "$source_dir/list.sh" "$install_dir/list.sh"

if [[ ! -e $picker_config_dir/directories ]]; then
  install -m 644 "$source_dir/directories.conf" "$picker_config_dir/directories"
fi

printf 'Installed Quickshell config: %s\n' "$install_dir"
printf 'Wallpaper directories: %s/directories\n' "$picker_config_dir"
printf 'Add this to your Hyprland config: source = %s/hyprland.conf\n' "$install_dir"
