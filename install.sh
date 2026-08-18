#!/usr/bin/env bash
# Installer for the Keyboard layout + IME bar widget.
# Idempotent: safe to re-run, skips everything already in place.
# Run from a terminal (package install may ask for your password):
#   bash install.sh
set -euo pipefail

PLUGIN_ID="matteo.keyboard-layout"
PLUGIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
REPO_URL="https://github.com/MattMangoni/omarchy-keyboard-layout-ime"
FCITX5_PROFILE="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5/profile"
SHELL_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
CHROMIUM_FLAGS="${XDG_CONFIG_HOME:-$HOME/.config}/chromium-flags.conf"
FCITX5_DBUS_SERVICE="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/org.fcitx.Fcitx5.service"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
skip() { printf '\033[1;32m ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*"; }

command -v omarchy >/dev/null || { warn "This installer needs an Omarchy system."; exit 1; }

# 1. Mozc engine ------------------------------------------------------------
if pacman -Q fcitx5-mozc >/dev/null 2>&1; then
  skip "fcitx5-mozc is already installed"
else
  say "Installing fcitx5-mozc (may ask for your password)"
  omarchy pkg add fcitx5-mozc
fi

# Keep fcitx5-remote from D-Bus-activating an unmanaged second instance while
# the Omarchy service is starting or restarting.
say "Routing Fcitx5 D-Bus activation through the Omarchy service"
mkdir -p "$(dirname "$FCITX5_DBUS_SERVICE")"
cat > "$FCITX5_DBUS_SERVICE" <<'EOF'
[D-BUS Service]
Name=org.fcitx.Fcitx5
Exec=/usr/bin/systemctl --user start omarchy-fcitx5.service
SystemdService=omarchy-fcitx5.service
EOF

# 2. Mozc in the fcitx5 profile ---------------------------------------------
if [[ -f "$FCITX5_PROFILE" ]] && grep -qx 'Name=mozc' "$FCITX5_PROFILE"; then
  skip "Mozc is already in the fcitx5 profile"
else
  say "Adding Mozc to the fcitx5 profile"
  # fcitx5 writes the profile on exit, so stop it around the edit.
  systemctl --user stop omarchy-fcitx5.service 2>/dev/null || true

  if [[ ! -f "$FCITX5_PROFILE" ]]; then
    mkdir -p "$(dirname "$FCITX5_PROFILE")"
    cat > "$FCITX5_PROFILE" <<'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=keyboard-us

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[GroupOrder]
0=Default
EOF
  fi

  next_item=$(grep -c '^\[Groups/0/Items/' "$FCITX5_PROFILE" || true)
  awk -v n="$next_item" '
    /^\[GroupOrder\]/ && !done {
      print "[Groups/0/Items/" n "]"
      print "# Name"
      print "Name=mozc"
      print "# Layout"
      print "Layout="
      print ""
      done = 1
    }
    { print }
  ' "$FCITX5_PROFILE" > "$FCITX5_PROFILE.tmp"
  mv "$FCITX5_PROFILE.tmp" "$FCITX5_PROFILE"

  systemctl --user start omarchy-fcitx5.service 2>/dev/null || true
fi

# 3. Plugin files ------------------------------------------------------------
if [[ -f "$PLUGIN_DIR/manifest.json" ]]; then
  skip "Plugin files are already at $PLUGIN_DIR"
else
  say "Cloning the plugin into $PLUGIN_DIR"
  git clone "$REPO_URL" "$PLUGIN_DIR"
fi

# 4. Register with the shell -------------------------------------------------
say "Registering the widget with omarchy-shell"
omarchy-shell shell rescanPlugins || true
omarchy plugin enable "$PLUGIN_ID" || true
omarchy plugin disable omarchy.keyboard-layout || true

if [[ -f "$SHELL_JSON" ]] && grep -q "$PLUGIN_ID" "$SHELL_JSON"; then
  skip "Widget is already placed on the bar"
else
  say "Placing the widget on the right side of the bar"
  omarchy bar move "$PLUGIN_ID" --section right
fi

# 5. Chromium IME flags ------------------------------------------------------
if [[ -f "$CHROMIUM_FLAGS" ]]; then
  if grep -q -- '--enable-wayland-ime' "$CHROMIUM_FLAGS"; then
    skip "Chromium Wayland IME flags are already set"
  else
    say "Adding Wayland IME flags to $CHROMIUM_FLAGS"
    printf -- '--enable-wayland-ime\n--wayland-text-input-version=3\n' >> "$CHROMIUM_FLAGS"
    warn "Restart Chromium to apply the IME flags."
  fi
fi

# 6. Layout check (your config stays yours) ----------------------------------
kb_layout=$(hyprctl getoption input:kb_layout -j 2>/dev/null | grep -o '"str": *"[^"]*"' | cut -d'"' -f4 || true)
if [[ "$kb_layout" == *,* ]]; then
  skip "Hyprland has multiple layouts ($kb_layout)"
else
  skip "Hyprland has one layout ($kb_layout); the widget will cycle between it and Japanese"
fi

say "Done. Click the layout label on the bar to cycle; Ctrl+Space toggles Japanese."
