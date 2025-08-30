#!/usr/bin/env bash
set -Eeuo pipefail

# --- discover latest build -------------------------------------------------
# Obsidian provides Linux AppImages via GitHub Releases. We query the GitHub
# API for the latest release and select the AppImage asset. If that fails, we
# fall back to the website download endpoint which redirects to the latest
# AppImage URL.
#  • Primary: https://api.github.com/repos/obsidianmd/obsidian-releases/latest
#  • Fallback: https://obsidian.md/download?platform=linux

JSON=$(curl -fsSL \
       "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" \
       -H "Accept: application/vnd.github+json" \
       -H "User-Agent: ObsidianInstaller/1.0" || true)

ARCH="$(uname -m)"

# Extract download URL and version from GitHub API if available.
URL=""
VER=""

if [[ -n "${JSON}" && "${JSON}" != "null" ]]; then
  VER=$(echo "${JSON}" | jq -r '.tag_name' | sed 's/^v//')
  if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    URL=$(echo "${JSON}" | jq -r '.assets[] | select(.name | test("arm64\\.AppImage$")) | .browser_download_url' | head -n1)
  else
    URL=$(echo "${JSON}" | jq -r '.assets[] | select((.name | endswith(".AppImage")) and (.name | test("arm64") | not)) | .browser_download_url' | head -n1)
  fi
fi

# Fallback to website redirect if API lookup failed or returned no AppImage.
if [[ -z "${URL}" || -z "${VER}" ]]; then
  # Fallback: parse the releases/latest HTML for an AppImage link
  PAGE=$(curl -fsSL "https://github.com/obsidianmd/obsidian-releases/releases/latest" || true)
  if [[ -n "$PAGE" ]]; then
    if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
      URL=$(printf "%s" "$PAGE" | grep -Eo 'href=\"/obsidianmd/obsidian-releases/releases/download/[^\"]+/Obsidian-[0-9][^\"]*arm64\.AppImage\"' | sed 's/^href=\"/https:\/\/github.com/' | sed 's/\"$//' | head -n1)
    else
      URL=$(printf "%s" "$PAGE" | grep -Eo 'href=\"/obsidianmd/obsidian-releases/releases/download/[^\"]+/Obsidian-[0-9][^\"]*\.AppImage\"' | grep -v arm64 | sed 's/^href=\"/https:\/\/github.com/' | sed 's/\"$//' | head -n1)
    fi
    if [[ -n "$URL" ]]; then
      FNAME="$(basename "$URL")"
      VER=$(echo "$FNAME" | sed -E 's/Obsidian-([0-9][0-9.]+)\.AppImage/\1/')
    fi
  fi
fi

if [[ -z "${URL}" || -z "${VER}" ]]; then
  echo "ERROR: Failed to discover the latest Obsidian AppImage URL/version."
  echo "       Check your network connection or try again later."
  exit 1
fi

# --- create local obsidian command -----------------------------------------
create_obsidian_command() {
  local new_bin="$1"

  # Ensure ~/.local/bin exists
  mkdir -p "$HOME/.local/bin"

  # Create symlink to new version
  ln -sf "$new_bin" "$HOME/.local/bin/obsidian"
  echo "Created command: ~/.local/bin/obsidian -> $new_bin"

  # Check if ~/.local/bin is in PATH
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo "WARNING: ~/.local/bin is not in your PATH. Add this to your shell profile:"
    echo "     export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

# --- check current version -------------------------------------------------
get_installed_version() {
  local appdir="$HOME/Applications/obsidian"
  if [[ ! -d "$appdir" ]]; then
    return 1
  fi

  # Find the most recent obsidian AppImage by modification time
  local current_appimage
  current_appimage=$(find "$appdir" -name "obsidian-*.AppImage" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)

  if [[ -z "$current_appimage" || ! -f "$current_appimage" ]]; then
    return 1
  fi

  # Extract version from filename (obsidian-X.Y.Z.AppImage)
  basename "$current_appimage" | sed 's/obsidian-\(.*\)\.AppImage/\1/'
}

CURRENT_VER=$(get_installed_version 2>/dev/null || echo "")

if [[ -n "$CURRENT_VER" && "$CURRENT_VER" == "$VER" ]]; then
  echo "Obsidian $VER is already installed and up to date."
  # Still ensure the obsidian command is available
  APPDIR="$HOME/Applications/obsidian"
  BIN="$APPDIR/obsidian-$VER.AppImage"
  create_obsidian_command "$BIN"
  exit 0
fi

if [[ -n "$CURRENT_VER" ]]; then
  echo "Current version: $CURRENT_VER"
  echo "Available version: $VER"
else
  echo "No existing installation found"
  echo "Installing version: $VER"
fi

# --- check for running instances -------------------------------------------
if pgrep -x "Obsidian" >/dev/null 2>&1 || pgrep -x "obsidian" >/dev/null 2>&1; then
  echo "WARNING: Obsidian appears to be running."
  read -p "Do you want to terminate running instances to proceed with the update? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Terminating Obsidian instances..."
    killall -q Obsidian 2>/dev/null || true
    killall -q obsidian 2>/dev/null || true
    # Fallback: kill any AppImage-based Obsidian processes without matching this script
    pkill -f 'Obsidian-.*\.AppImage' 2>/dev/null || true
    sleep 2
    echo "Obsidian instances terminated."
  else
    echo "Installation cancelled. Please close Obsidian manually and run the script again."
    exit 1
  fi
fi

# --- local paths ------------------------------------------------------------
APPDIR="$HOME/Applications/obsidian"
BIN="$APPDIR/obsidian-$VER.AppImage"
ICON="$APPDIR/obsidian.png"
DESK="$HOME/.local/share/applications/obsidian.desktop"

mkdir -p "$APPDIR"

echo "Downloading Obsidian $VER..."
curl -L "$URL" -o "$BIN"
chmod +x "$BIN"

echo "Fetching icon..."
curl -fsSL "https://obsidian.md/apple-touch-icon.png" -o "$ICON" || true

echo "Creating desktop entry..."
cat >"$DESK" <<EOF
[Desktop Entry]
Name=Obsidian
Exec=$BIN --no-sandbox %F
Icon=$ICON
Type=Application
Categories=Office;Utility;
EOF
update-desktop-database "$(dirname "$DESK")"

create_obsidian_command "$BIN"

echo "Installed Obsidian $VER — launch from your app launcher or run 'obsidian'"


