#!/usr/bin/env bash
set -Eeuo pipefail

# Proton VPN installer for Ubuntu/Debian-based systems (GNOME)
# Based on official instructions:
#   https://protonvpn.com/support/official-linux-vpn-ubuntu/

# Configuration via env vars or flags
CHANNEL="${CHANNEL:-stable}"        # stable | beta
WITH_TRAY="${WITH_TRAY:-0}"        # 1 to install tray packages
ASSUME_YES="${ASSUME_YES:-0}"      # 1 to auto-confirm prompts
FORCE="${FORCE:-0}"                # 1 to force reinstall/switch channel

ACTION="install"                   # install | uninstall | disable_killswitch

print_usage() {
  cat <<'EOF'
Proton VPN installer

Usage:
  bash install-protonvpn.sh [options]

Options:
  --channel <stable|beta>    Select repository channel (default: stable)
  --with-tray | --tray       Install tray indicator deps (GNOME)
  -y | --yes                 Assume yes for prompts (non-interactive)
  -f | --force               Force reinstall or switch repo channel
  --uninstall                Uninstall Proton VPN app and its repo package
  --disable-killswitch       Remove Proton VPN NetworkManager kill switch profiles
  -h | --help                Show this help

Examples:
  CHANNEL=stable bash install-protonvpn.sh
  CHANNEL=beta WITH_TRAY=1 bash install-protonvpn.sh
  bash install-protonvpn.sh --uninstall
  bash install-protonvpn.sh --disable-killswitch
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --with-tray|--tray)
      WITH_TRAY=1
      shift
      ;;
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    --uninstall)
      ACTION="uninstall"
      shift
      ;;
    --disable-killswitch)
      ACTION="disable_killswitch"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

ensure_prereqs() {
  require_cmd curl
  require_cmd sha256sum
  require_cmd dpkg
  require_cmd apt-get
}

prompt_for_sudo() {
  if [[ "$ASSUME_YES" != "1" ]]; then
    echo "This script needs sudo to install APT packages."
    read -p "Proceed with sudo operations? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Cancelled."
      exit 1
    fi
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo -v || true
  else
    echo "sudo is required but not found." >&2
    exit 1
  fi
}

set_channel_vars() {
  case "$CHANNEL" in
    stable)
      REPO_PKG="protonvpn-stable-release"
      DEB_NAME="protonvpn-stable-release_1.0.8_all.deb"
      DEB_URL="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/${DEB_NAME}"
      DEB_SHA256="0b14e71586b22e498eb20926c48c7b434b751149b1f2af9902ef1cfe6b03e180"
      ;;
    beta)
      REPO_PKG="protonvpn-beta-release"
      DEB_NAME="protonvpn-beta-release_1.0.8_all.deb"
      DEB_URL="https://repo.protonvpn.com/debian/dists/unstable/main/binary-all/${DEB_NAME}"
      DEB_SHA256="0f3c88b11aae384d76fc63547c4fbea1161c2aef376fb4b73d32786cbf9fa019"
      ;;
    *)
      echo "Invalid CHANNEL: $CHANNEL (use stable|beta)" >&2
      exit 1
      ;;
  esac
}

installed_repo_channel() {
  if dpkg -s protonvpn-stable-release >/dev/null 2>&1; then
    echo "stable"
    return 0
  fi
  if dpkg -s protonvpn-beta-release >/dev/null 2>&1; then
    echo "beta"
    return 0
  fi
  echo "none"
}

is_app_installed() {
  dpkg -s proton-vpn-gnome-desktop >/dev/null 2>&1
}

download_and_verify_repo_deb() {
  local tmpdir deb_path
  tmpdir="$(mktemp -d)"
  deb_path="$tmpdir/$DEB_NAME"
  echo "Downloading repository package: $DEB_URL" >&2
  curl -fL -o "$deb_path" "$DEB_URL"
  echo "Verifying checksum..." >&2
  local actual
  actual="$(sha256sum "$deb_path" | awk '{print $1}')"
  if [[ "$actual" != "$DEB_SHA256" ]]; then
    echo "Checksum mismatch for $DEB_NAME" >&2
    echo "Expected: $DEB_SHA256" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
  echo "$deb_path"
}

install_repo_if_needed() {
  local current_channel
  current_channel="$(installed_repo_channel)"

  if [[ "$current_channel" == "$CHANNEL" && "$FORCE" != "1" ]]; then
    echo "Proton VPN $CHANNEL repository already configured."
    return 0
  fi

  if [[ "$current_channel" != "none" && "$current_channel" != "$CHANNEL" ]]; then
    if [[ "$FORCE" == "1" ]]; then
      echo "Switching repository channel: $current_channel -> $CHANNEL"
      prompt_for_sudo
      if [[ "$current_channel" == "stable" ]]; then
        sudo apt-get -y purge protonvpn-stable-release || true
      else
        sudo apt-get -y purge protonvpn-beta-release || true
      fi
    else
      echo "WARNING: Repo channel '$current_channel' already installed; requested '$CHANNEL'. Use --force to switch."
      CHANNEL="$current_channel"
      set_channel_vars
      return 0
    fi
  fi

  local deb_path
  deb_path="$(download_and_verify_repo_deb)"
  prompt_for_sudo
  sudo dpkg -i "$deb_path"
  sudo apt-get update -y
}

install_app() {
  if is_app_installed && [[ "$FORCE" != "1" ]]; then
    echo "Proton VPN app already installed. Skipping reinstall."
  else
    prompt_for_sudo
    sudo apt-get install -y proton-vpn-gnome-desktop
  fi
}

install_tray_packages() {
  if [[ "$WITH_TRAY" == "1" ]]; then
    echo "Installing GNOME tray indicator dependencies..."
    prompt_for_sudo
    sudo apt-get install -y libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 gnome-shell-extension-appindicator
  fi
}

uninstall_app_and_repo() {
  prompt_for_sudo
  echo "Uninstalling Proton VPN app..."
  sudo apt-get -y autoremove proton-vpn-gnome-desktop || true

  echo "Removing Proton VPN repository package..."
  if dpkg -s protonvpn-stable-release >/dev/null 2>&1; then
    sudo apt-get -y purge protonvpn-stable-release || true
  fi
  if dpkg -s protonvpn-beta-release >/dev/null 2>&1; then
    sudo apt-get -y purge protonvpn-beta-release || true
  fi
  sudo apt-get update -y || true
}

disable_killswitch_profiles() {
  if ! command -v nmcli >/dev/null 2>&1; then
    echo "nmcli not found. NetworkManager is required to manage kill switch profiles." >&2
    exit 1
  fi

  echo "Checking active Proton VPN connections..."
  local names
  names="$(nmcli -t -f NAME connection show --active | grep '^pvpn-' || true)"
  if [[ -z "$names" ]]; then
    echo "No active Proton VPN kill switch profiles found."
  fi

  # Attempt to delete known pvpn connections whether active or not
  local all
  all="$(nmcli -t -f NAME connection show | grep '^pvpn-' || true)"
  if [[ -z "$all" ]]; then
    echo "No Proton VPN profiles to delete."
    return 0
  fi

  while IFS= read -r conn; do
    [[ -n "$conn" ]] || continue
    echo "Deleting connection: $conn"
    nmcli connection delete "$conn" || true
  done <<< "$all"

  echo "Remaining active Proton VPN connections:"
  nmcli connection show --active | grep pvpn- || true
}

main() {
  ensure_prereqs
  case "$ACTION" in
    uninstall)
      uninstall_app_and_repo
      echo "Proton VPN uninstalled."
      return 0
      ;;
    disable_killswitch)
      disable_killswitch_profiles
      return 0
      ;;
    install)
      ;;
    *)
      echo "Unknown action: $ACTION" >&2
      exit 1
      ;;
  esac

  set_channel_vars
  install_repo_if_needed
  install_app
  install_tray_packages

  echo "Done. Launch 'Proton VPN' from your applications menu."
  echo "Tip: You can enable Beta access inside the app settings if desired."
}

main "$@"


