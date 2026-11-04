#!/bin/sh
# Registers tools/redirect-handler.sh as the desktop handler for mymacsdk:// links (per user, freedesktop).
# Usage: tools/install-redirect-handler.sh [--uninstall]; set PORT when the server does not run on 3000.
set -e
APPLICATIONS_DIR="$HOME/.local/share/applications"
DESKTOP_NAME=psa-proeftuin-mymacsdk.desktop
HANDLER="$(cd "$(dirname "$0")" && pwd)/redirect-handler.sh"
PORT="${PORT:-3000}"

if [ "$1" = "--uninstall" ]; then
  rm -f "$APPLICATIONS_DIR/$DESKTOP_NAME"
  echo "Removed $APPLICATIONS_DIR/$DESKTOP_NAME; mymacsdk:// links have no handler any more"
else
  chmod 755 "$HANDLER"
  mkdir -p "$APPLICATIONS_DIR"
  cat > "$APPLICATIONS_DIR/$DESKTOP_NAME" <<EOF
[Desktop Entry]
Name=PSA proeftuin login
Comment=Hands mymacsdk:// OAuth redirects to the PSA proeftuin on port $PORT
Exec="$HANDLER" $PORT %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/mymacsdk;
EOF
  xdg-mime default "$DESKTOP_NAME" x-scheme-handler/mymacsdk
  echo "Registered $APPLICATIONS_DIR/$DESKTOP_NAME for mymacsdk:// links"
fi
update-desktop-database "$APPLICATIONS_DIR"
