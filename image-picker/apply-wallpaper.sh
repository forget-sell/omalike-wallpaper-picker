#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  printf 'Usage: %s IMAGE\n' "${0##*/}" >&2
  exit 2
fi

image=$1
if [[ ! -f $image || ! -r $image ]]; then
  printf 'Wallpaper is not a readable file: %s\n' "$image" >&2
  exit 1
fi

if command -v caelestia >/dev/null 2>&1; then
  caelestia wallpaper --file "$image"
  exit
fi

if command -v swww >/dev/null 2>&1; then
  swww img "$image"
  exit
fi

if command -v hyprpaper >/dev/null 2>&1; then
  if ! command -v hyprctl >/dev/null 2>&1; then
    printf 'hyprpaper is installed, but hyprctl is not available.\n' >&2
    exit 1
  fi
  hyprctl hyprpaper preload "$image"
  hyprctl hyprpaper wallpaper ",$image"
  exit
fi

if command -v swaybg >/dev/null 2>&1; then
  if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
    runtime_dir=$XDG_RUNTIME_DIR/image-picker
  else
    runtime_dir=${XDG_CACHE_HOME:-$HOME/.cache}/image-picker/run
  fi
  mkdir -p "$runtime_dir"
  chmod 700 "$runtime_dir"
  pid_file=$runtime_dir/swaybg.pid
  log_file=$runtime_dir/swaybg.log
  previous_pid=
  if [[ -r $pid_file ]]; then
    read -r previous_pid <"$pid_file" || true
  fi

  swaybg -i "$image" -m fill >"$log_file" 2>&1 &
  new_pid=$!
  sleep 0.2
  if ! kill -0 "$new_pid" 2>/dev/null; then
    wait "$new_pid" || true
    cat "$log_file" >&2
    exit 1
  fi

  printf '%s\n' "$new_pid" >"$pid_file"
  if [[ $previous_pid =~ ^[0-9]+$ && -r /proc/$previous_pid/comm ]] &&
    [[ $(<"/proc/$previous_pid/comm") == swaybg ]]; then
    kill -TERM "$previous_pid" 2>/dev/null || true
  fi
  exit
fi

printf 'No supported wallpaper backend found. Install caelestia, swww, hyprpaper, or swaybg.\n' >&2
exit 1
