#!/usr/bin/env bash
set -Eeuo pipefail

CHANNEL="${CHANNEL:-stable}"   # stable | prerelease
FORCE="${FORCE:-0}"             # 1 to force reinstall

# Optional CLI flag: --force | -f
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
  FORCE=1
  shift || true
fi

# --- discover latest build -------------------------------------------------
# Cursor has migrated to a new update backend (api2.cursor.sh). We query it
# first and fall back to the legacy endpoint if the request fails.
#  • api2 requires a current version and a machine id in the URL. We fake the
#    current version with 0.0.0 so it always responds with the latest build.
#  • The response contains a `.url` field that ends with ".AppImage.zsync" –
#    we strip the suffix so we download the actual AppImage.

MACHINE_ID="$(cat /etc/machine-id 2>/dev/null || echo 00000000000000000000000000000000)"
CUR_VER="0.0.0"

JSON=$(curl -fsSL \
       "https://api2.cursor.sh/updates/api/update/linux-x64/cursor/${CUR_VER}/${MACHINE_ID}/${CHANNEL}" \
       -H "User-Agent: CursorInstaller/1.0" || true)

# Extract download URL and version, handling both response formats.
URL=$(echo "${JSON}" | jq -r '.downloadUrl // .url' | sed 's/\.zsync$//')
VER=$(echo "${JSON}" | jq -r '.version // .productVersion')

# --- create local cursor command ---------------------------------------------
create_cursor_command() {
  local appimage_bin="$1"

  # Ensure ~/.local/bin exists
  mkdir -p "$HOME/.local/bin"

  # Build wrapper in a temp file to avoid ETXTBUSY, then atomically replace
  local tmp_wrapper
  tmp_wrapper="$(mktemp)"

  {
    printf '%s\n' "#!/usr/bin/env bash" "set -Eeuo pipefail" "APPIMAGE_BIN=\"${appimage_bin}\""
    cat <<'EOF'

# Resolve relative path arguments to absolute paths so the AppImage runtime
# (which may chdir to its mount point) does not treat "." as the AppImage dir.

normalized_args=()
for arg in "$@"; do
  # Leave options (start with -) and URIs (contain ://) untouched
  if [[ "$arg" == -* || "$arg" == *://* ]]; then
    normalized_args+=("$arg")
    continue
  fi

  # Treat as path-like if '.', '..', starts with ./ or ../, has a slash,
  # or points to an existing file/dir. Otherwise, pass through unchanged.
  if [[ "$arg" == "." || "$arg" == ".." || "$arg" == ./* || "$arg" == ../* || "$arg" == */* || -e "$arg" ]]; then
    if [[ "$arg" == /* ]]; then
      normalized_args+=("$arg")
    else
      normalized_args+=("$PWD/$arg")
    fi
  else
    normalized_args+=("$arg")
  fi
done

exec "$APPIMAGE_BIN" --no-sandbox -- "${normalized_args[@]}"
EOF
  } > "$tmp_wrapper"

  chmod +x "$tmp_wrapper"
  mv -f "$tmp_wrapper" "$HOME/.local/bin/cursor"
  echo "Created command: ~/.local/bin/cursor -> $appimage_bin --no-sandbox (atomic replace)"

  # Check if ~/.local/bin is in PATH
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo 'WARNING: ~/.local/bin is not in your PATH. Add this to your shell profile:'
    echo '     export PATH="$HOME/.local/bin:$PATH"'
  fi
}

# --- check current version -------------------------------------------------
get_installed_version() {
  local appdir="$HOME/Applications/cursor"
  if [[ ! -d "$appdir" ]]; then
    return 1
  fi
  
  # Find the most recent cursor AppImage by modification time
  local current_appimage
  current_appimage=$(find "$appdir" -name "cursor-*.AppImage" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)
  
  if [[ -z "$current_appimage" || ! -f "$current_appimage" ]]; then
    return 1
  fi
  
  # Extract version from filename (cursor-X.Y.Z.AppImage)
  basename "$current_appimage" | sed 's/cursor-\(.*\)\.AppImage/\1/'
}

CURRENT_VER=$(get_installed_version 2>/dev/null || echo "")

if [[ -n "$CURRENT_VER" && "$CURRENT_VER" == "$VER" && "$FORCE" != "1" ]]; then
  echo "Cursor $VER is already installed and up to date."
  # Still ensure the cursor command is available
  APPDIR="$HOME/Applications/cursor"
  BIN="$APPDIR/cursor-$VER.AppImage"
  create_cursor_command "$BIN"
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
if pgrep -x "cursor" >/dev/null 2>&1; then
  echo "WARNING: Cursor is currently running."
  read -p "Do you want to terminate running instances to proceed with the update? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Terminating Cursor instances..."
    killall cursor 2>/dev/null || true
    sleep 2
    echo "Cursor instances terminated."
  else
    echo "Installation cancelled. Please close Cursor manually and run the script again."
    exit 1
  fi
fi

# --- local paths -----------------------------------------------------------
APPDIR="$HOME/Applications/cursor"
BIN="$APPDIR/cursor-$VER.AppImage"
ICON="$APPDIR/cursor.png"
DESK="$HOME/.local/share/applications/cursor.desktop"

mkdir -p "$APPDIR"

echo "Downloading Cursor $VER..."
curl -fL "$URL" -o "$BIN"
chmod +x "$BIN"

echo "Fetching icon..."
curl -fsSL "https://avatars.githubusercontent.com/u/126759922?s=256" -o "$ICON"

echo "Creating desktop entry..."
mkdir -p "$(dirname "$DESK")"
cat >"$DESK" <<EOF
[Desktop Entry]
Name=Cursor
Exec=$HOME/.local/bin/cursor %U
TryExec=$HOME/.local/bin/cursor
Icon=$ICON
Type=Application
Categories=Development;Utility;
EOF
update-desktop-database "$(dirname "$DESK")"

create_cursor_command "$BIN"

echo "Installed Cursor $VER — launch from the Pop!_OS launcher or run 'cursor'"
