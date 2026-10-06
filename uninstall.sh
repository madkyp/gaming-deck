#!/usr/bin/env bash
# Uninstaller for Gaming Deck — removes only the deck itself
set -euo pipefail

# the in-game panel's key in Hyprland's config goes first (it's the deck that removes it)
[[ -x "$HOME/.local/bin/gaming-deck" ]] && "$HOME/.local/bin/gaming-deck" panel key off >/dev/null 2>&1 || true
rm -f "$HOME/.local/bin/gaming-deck"
rm -f "$HOME/.local/bin/gaming-deck-web"
rm -f "$HOME/.config/quickshell/gaming-deck/shell.qml"
rm -f "$HOME/.config/quickshell/gaming-deck/es.js"
rm -f "$HOME/.config/quickshell/gaming-deck-overlay/shell.qml"
rmdir "$HOME/.config/quickshell/gaming-deck-overlay" 2>/dev/null || true
rm -f "$HOME/.config/quickshell/gaming-deck-panel/shell.qml"
rmdir "$HOME/.config/quickshell/gaming-deck-panel" 2>/dev/null || true
rmdir "$HOME/.config/quickshell/gaming-deck" 2>/dev/null || true
rm -f "$HOME/.local/share/applications/gaming-deck.desktop"
rm -f "$HOME/.local/share/icons/hicolor/scalable/apps/gaming-deck.svg"
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

echo "✔ Gaming Deck uninstalled."
echo "  Your game profiles, shader looks and ReShade live in ~/.local/share/gaming-deck (delete it if you like)."
echo "  Games still launched through it from Steam: remove \"…/gaming-deck run\" from their launch options."
