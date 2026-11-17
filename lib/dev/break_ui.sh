#!/usr/bin/env bash
# Runs the debug break-ui harness (lib/dev/break_ui_main.dart) on an X display, with no network and scratch XDG dirs.
# Build first: flutter build linux --debug --no-pub -t lib/dev/break_ui_main.dart
# Usage: SCRATCH=$(mktemp -d) DISPLAY_NUM=77 BB_FIXTURE=worst BB_WINDOW=412x892 BB_TEXT_SCALE=2.0 lib/dev/break_ui.sh
# Other switches (BB_THEME, BB_OPEN, BB_SNACKBAR) are documented at the top of break_ui_main.dart.
set -euo pipefail
: "${SCRATCH:?set SCRATCH to a scratch directory}"
bundle="$(cd "$(dirname "$0")/../.." && pwd)/build/linux/x64/debug/bundle/bluebubbles"
mkdir -p "$SCRATCH/data" "$SCRATCH/cache" "$SCRATCH/state" "$SCRATCH/config/glib-2.0/settings"
# The Linux embedder reads text scale from GSettings; the keyfile backend keeps it out of the real dconf.
printf '[org/gnome/desktop/interface]\ntext-scaling-factor=%s\n' "${BB_TEXT_SCALE:-1.0}" \
  >"$SCRATCH/config/glib-2.0/settings/keyfile"
exec bwrap --dev-bind / / --unshare-net --die-with-parent -- env -u WAYLAND_DISPLAY \
  DISPLAY=":${DISPLAY_NUM:-77}" GDK_BACKEND=x11 GSETTINGS_BACKEND=keyfile \
  XDG_DATA_HOME="$SCRATCH/data" XDG_CONFIG_HOME="$SCRATCH/config" \
  XDG_CACHE_HOME="$SCRATCH/cache" XDG_STATE_HOME="$SCRATCH/state" \
  dbus-run-session -- "$bundle"
