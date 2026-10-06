#!/usr/bin/env bash
# Installer for Gaming Deck — Arch / CachyOS
# Copies the deck into place and (optionally) installs missing dependencies.
#
#   ./install.sh            copy + check and install dependencies
#   ./install.sh --no-deps  only copy the files
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
WITH_DEPS=1
[[ "${1:-}" == "--no-deps" ]] && WITH_DEPS=0

# Package names (official repos / AUR). The font is handled separately.
REQUIRED=(quickshell jq libarchive polkit curl)
# gaming tools the deck drives (GameMode, MangoHud, gamescope), notifications,
# the file chooser (IMPORT), python (reads a game's .exe for ReShade)
OPTIONAL=(gamemode lib32-gamemode mangohud lib32-mangohud gamescope libnotify zenity python hyprpolkitagent)

is_installed() { pacman -Qq "$1" &>/dev/null; }
in_repo()      { pacman -Si "$1" &>/dev/null; }

install_deps() {
    command -v pacman >/dev/null || { echo "⚠  Not Arch/pacman: install the dependencies by hand (see README)."; return; }

    local repo=() aur=() p
    for p in "${REQUIRED[@]}" "${OPTIONAL[@]}"; do
        is_installed "$p" && continue
        if in_repo "$p"; then repo+=("$p"); else aur+=("$p"); fi
    done

    # Nerd Font: only suggested when none is installed
    if ! fc-list 2>/dev/null | grep -qi "nerd"; then
        if in_repo ttf-jetbrains-mono-nerd; then repo+=(ttf-jetbrains-mono-nerd); fi
    fi

    if [[ ${#repo[@]} -eq 0 && ${#aur[@]} -eq 0 ]]; then
        echo "✔ All dependencies are already installed."
        return
    fi

    echo "Missing dependencies:"
    [[ ${#repo[@]} -gt 0 ]] && echo "  · repos: ${repo[*]}"
    [[ ${#aur[@]}  -gt 0 ]] && echo "  · AUR:   ${aur[*]}"
    read -rp "Install them now? [Y/n] " ans
    [[ "${ans,,}" == "n" ]] && { echo "→ Skipped. Install them by hand if something doesn't work."; return; }

    if [[ ${#repo[@]} -gt 0 ]]; then
        sudo pacman -S --needed "${repo[@]}"
    fi
    if [[ ${#aur[@]} -gt 0 ]]; then
        local helper; helper="$(command -v paru || command -v yay || true)"
        if [[ -n "$helper" ]]; then
            "$helper" -S --needed "${aur[@]}"
        else
            echo "⚠  These packages are in the AUR and you have no helper (paru/yay):"
            echo "     ${aur[*]}"
            echo "   Install them the way you usually install AUR packages."
        fi
    fi
}

# ---- dependencies -----------------------------------------------------------
if [[ $WITH_DEPS -eq 1 ]]; then
    echo "== Dependencies =="
    install_deps
    echo
fi

# ---- files ------------------------------------------------------------------
echo "== Installing Gaming Deck =="
echo "→ backend   ~/.local/bin/gaming-deck"
install -Dm755 "$SRC/bin/gaming-deck" "$HOME/.local/bin/gaming-deck"

echo "→ icon      ~/.local/share/icons/hicolor/scalable/apps/gaming-deck.svg"
install -Dm644 "$SRC/icons/gaming-deck.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/gaming-deck.svg"
gtk-update-icon-cache -qtf "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true

echo "→ launcher  ~/.local/share/applications/gaming-deck.desktop"
install -Dm644 "$SRC/gaming-deck.desktop" "$HOME/.local/share/applications/gaming-deck.desktop"
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

# version info, used by the deck to spot a newer version of itself on GitHub
commit="${GAMING_DECK_COMMIT:-$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)}"
gh_repo="${GAMING_DECK_REPO:-$(git -C "$SRC" remote get-url origin 2>/dev/null \
        | sed -nE 's#.*github\.com[:/]([^/]+/[^/]+)$#\1#p' | sed 's/\.git$//' || true)}"
branch="$(git -C "$SRC" branch --show-current 2>/dev/null || true)"
src="$SRC"; git -C "$SRC" rev-parse --git-dir >/dev/null 2>&1 || src=""
mkdir -p "$HOME/.local/share/gaming-deck"
printf 'SRC=%s\nREPO=%s\nBRANCH=%s\nCOMMIT=%s\nDATE=%s\n' \
    "$src" "${gh_repo:-madkyp/gaming-deck}" "${branch:-main}" "$commit" "$(date -Is)" \
    > "$HOME/.local/share/gaming-deck/install.env"
echo "→ version   ${commit:0:7}"

# the GUI goes last: a running deck reloads as soon as shell.qml changes
echo "→ GUI       ~/.config/quickshell/gaming-deck/shell.qml"
install -Dm644 "$SRC/quickshell/overlay.qml" "$HOME/.config/quickshell/gaming-deck-overlay/shell.qml"
install -Dm644 "$SRC/quickshell/panel.qml" "$HOME/.config/quickshell/gaming-deck-panel/shell.qml"
install -Dm644 "$SRC/quickshell/es.js" "$HOME/.config/quickshell/gaming-deck/es.js"
install -Dm644 "$SRC/quickshell/shell.qml" "$HOME/.config/quickshell/gaming-deck/shell.qml"

# game data from Control Deck (where gaming lived before the split), once
if [[ -d "$HOME/.local/share/control-deck/gaming" || -x "$HOME/.local/bin/control-deck" ]]; then
    echo
    echo "== Migrating the game data from Control Deck =="
    "$HOME/.local/bin/gaming-deck" migrate || true
fi

echo
echo "✔ Installed."
echo "  Run it with:  qs -c gaming-deck   (or \"Gaming Deck\" from your app menu)"
# the in-game panel's key, once (it edits Hyprland's config, with a backup)
if [[ -z "$(jq -r '.key // empty' "$HOME/.local/share/gaming-deck/gaming/panel.json" 2>/dev/null)" ]]; then
    echo "  In-game panel (achievements, guides, notes): set its key with  gaming-deck panel key F6"
fi
echo
case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) echo "⚠  ~/.local/bin is not in your PATH. Add it to use 'gaming-deck' from a terminal." ;;
esac
