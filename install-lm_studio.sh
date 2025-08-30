#!/usr/bin/env bash
set -Eeuo pipefail

# Channel: beta | stable  (stable falls back to beta if not resolvable)
CHANNEL="${CHANNEL:-beta}"

ARCH="$(uname -m)"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" ]]; then
  echo "LM Studio Linux is x64-only. Detected: $ARCH" >&2
  exit 1
fi

APPDIR="$HOME/Applications/lmstudio"
ICON_PATH="$HOME/.local/share/icons/hicolor/512x512/apps/lmstudio.png"
DESK="$HOME/.local/share/applications/lmstudio.desktop"
WRAPPER="$HOME/.local/bin/lmstudio-wrapper"
mkdir -p "$APPDIR"

# Function to check for running LM Studio processes
check_running_lmstudio() {
  # Look for processes with the AppImage in their command line
  local appimage_processes
  appimage_processes=$(pgrep -f "LM-Studio.*AppImage" || true)

  # Also check for any processes that might be accessing the app directory
  local lsof_processes=""
  if command -v lsof >/dev/null 2>&1; then
    lsof_processes=$(lsof "$APPDIR" 2>/dev/null | grep -v PID | awk '{print $2}' | sort -u || true)
  fi

  if [[ -n "$appimage_processes" ]]; then
    echo "$appimage_processes"
  elif [[ -n "$lsof_processes" ]]; then
    echo "$lsof_processes"
  fi
}

get_latest_beta() {
  local html fname ver
  html="$(curl -fsSL 'https://lmstudio.ai/beta-releases')"
  # e.g. LM-Studio-0.3.24-3-x64.AppImage
  fname="$(grep -oE 'LM-Studio-[0-9]+(\.[0-9]+)*-[0-9]+-x64\.AppImage' <<<"$html" | head -n1)" || true
  [[ -n "$fname" ]] || return 1
  ver="$(sed -E 's/LM-Studio-([0-9.]+-[0-9]+)-x64\.AppImage/\1/' <<<"$fname")"
  echo "$ver"
}

get_latest_stable() {
  local html fname
  html="$(curl -fsSL 'https://lmstudio.ai/download?os=linux' || true)"
  fname="$(grep -oE 'LM-Studio-[0-9]+(\.[0-9]+)*-[0-9]+-x64\.AppImage' <<<"$html" | head -n1)" || true
  if [[ -z "$fname" ]]; then
    get_latest_beta || return 1   # fallback
  else
    sed -E 's/LM-Studio-([0-9.]+-[0-9]+)-x64\.AppImage/\1/' <<<"$fname"
  fi
}

VER=""
if [[ "$CHANNEL" == "beta" ]]; then
  VER="$(get_latest_beta)" || { echo "Failed to resolve latest beta."; exit 1; }
else
  VER="$(get_latest_stable)" || { echo "Failed to resolve latest release."; exit 1; }
fi

URL="https://installers.lmstudio.ai/linux/x64/${VER}/LM-Studio-${VER}-x64.AppImage"
BIN="$APPDIR/LM-Studio-${VER}-x64.AppImage"

get_installed_version() {
  local current
  current=$(find "$APPDIR" -maxdepth 1 -name 'LM-Studio-*-x64.AppImage' -type f -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr | head -n1 | awk '{print $2}')
  [[ -n "$current" ]] || return 1
  basename "$current" | sed -E 's/LM-Studio-([0-9.]+-[0-9]+)-x64\.AppImage/\1/'
}

CURRENT_VER="$(get_installed_version || true)"

if [[ -n "${CURRENT_VER:-}" && "$CURRENT_VER" == "$VER" ]]; then
  echo "LM Studio $VER is already installed."
else
  [[ -n "${CURRENT_VER:-}" ]] && echo "Updating LM Studio: $CURRENT_VER -> $VER" || echo "Installing LM Studio $VER"

  # Check for running LM Studio processes using improved detection
  running_processes=$(check_running_lmstudio)
  if [[ -n "$running_processes" ]]; then
    echo "WARNING: LM Studio appears to be running (PIDs: $running_processes)"
    read -p "Terminate running instances to proceed? (y/N): " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Terminating LM Studio processes..."

      # Try to terminate gracefully first
      pkill -f "LM-Studio.*AppImage" || true

      # Wait and check if termination was successful
      sleep 3
      remaining_processes=$(check_running_lmstudio)

      if [[ -n "$remaining_processes" ]]; then
        echo "Warning: Some processes may still be running (PIDs: $remaining_processes)"
        echo "Attempting force kill..."
        kill -9 $remaining_processes 2>/dev/null || true
        sleep 2

        # Final check
        final_processes=$(check_running_lmstudio)
        if [[ -n "$final_processes" ]]; then
          echo "Error: Unable to terminate all LM Studio processes."
          echo "Please manually terminate these processes: $final_processes"
          exit 1
        else
          echo "LM Studio processes terminated successfully."
        fi
      else
        echo "LM Studio processes terminated successfully."
      fi
    else
      echo "Cancelled."
      exit 1
    fi
  fi

  echo "Downloading: $URL"
  curl -fL -o "$BIN" "$URL"
  chmod +x "$BIN"

  echo "Extracting icon..."
  tmpdir="$(mktemp -d)"
  (cd "$tmpdir" && "$BIN" --appimage-extract >/dev/null 2>&1 || true)
  mkdir -p "$(dirname "$ICON_PATH")"
  cp "$tmpdir/squashfs-root/usr/share/icons/hicolor/512x512/apps/"*.png "$ICON_PATH" 2>/dev/null \
    || cp "$tmpdir/squashfs-root/.DirIcon" "$ICON_PATH" 2>/dev/null \
    || cp "$tmpdir/squashfs-root/"*.png "$ICON_PATH" 2>/dev/null || true
  rm -rf "$tmpdir"
fi

echo "Creating wrapper script..."
mkdir -p "$HOME/.local/bin"
cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
# LM Studio wrapper script - fixes sandbox permission issues
exec "$BIN" --no-sandbox "\$@"
EOF
chmod +x "$WRAPPER"

echo "Creating desktop entry..."
mkdir -p "$HOME/.local/share/applications"
cat > "$DESK" <<EOF
[Desktop Entry]
Name=LM Studio
Comment=Download and run local LLMs
Exec=$WRAPPER %U
TryExec=$WRAPPER
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Development;Utility;AI;
EOF
chmod +x "$DESK"
command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" >/dev/null || true

# Handy command alias
mkdir -p "$HOME/.local/bin"
ln -sf "$WRAPPER" "$HOME/.local/bin/lmstudio-gui"

# Optional: install the 'lms' CLI into PATH if Node/npm is present
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  echo "Bootstrapping 'lms' CLI..."
  npx --yes lmstudio install-cli || true
else
  echo "Tip: install Node.js to enable 'npx lmstudio install-cli' (LM Studio CLI)."
fi

# PATH hint
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  echo 'NOTE: ~/.local/bin not in PATH. Add: export PATH="$HOME/.local/bin:$PATH"'
fi

echo "Done. Launch from your app menu (LM Studio) or run: $WRAPPER"
