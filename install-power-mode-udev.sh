#!/usr/bin/env bash
set -Eeuo pipefail

# install-power-mode-udev.sh
# Sets up root-level udev rules to automatically switch GNOME power profiles
# when AC power is plugged/unplugged using the power_supply subsystem.
#
# Behavior:
#  - On AC: set profile to "performance" (fallback to "balanced" if unsupported)
#  - On battery: set profile to "power-saver"
#
# Usage:
#   bash install-power-mode-udev.sh                 # Install rules and helper, trigger once
#   FORCE=1 bash install-power-mode-udev.sh         # Reinstall even if present
#   APPLY=0 bash install-power-mode-udev.sh         # Skip immediate apply
#   UNINSTALL=1 bash install-power-mode-udev.sh     # Remove rules/helper

FORCE=${FORCE:-0}
APPLY=${APPLY:-1}
UNINSTALL=${UNINSTALL:-0}

RULE_PATH="/etc/udev/rules.d/99-power-mode-auto-switch.rules"
HELPER_PATH="/usr/local/bin/power-mode-udev-helper"

get_sudo() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo ""
  else
    echo "sudo"
  fi
}

require_binaries() {
  local missing=()
  command -v udevadm >/dev/null 2>&1 || missing+=("udevadm")
  command -v powerprofilesctl >/dev/null 2>&1 || missing+=("powerprofilesctl")
  command -v logger >/dev/null 2>&1 || missing+=("logger")
  if ((${#missing[@]} > 0)); then
    echo "Missing required commands: ${missing[*]}" >&2
    echo "Please install them first. On Ubuntu:" >&2
    echo "  sudo apt update && sudo apt install -y power-profiles-daemon util-linux" >&2
    exit 1
  fi
}

write_helper() {
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

LOG_TAG="power-mode-udev"

log() { logger -t "$LOG_TAG" "$*"; }

current_profile() {
  powerprofilesctl get 2>/dev/null || echo "unknown"
}

set_profile() {
  local profile="$1"
  if [[ "$(current_profile)" == "$profile" ]]; then
    return 0
  fi
  if powerprofilesctl set "$profile" 2>/dev/null; then
    log "Set power profile: $profile"
    return 0
  fi
  return 1
}

detect_ac() {
  local dev
  for dev in /sys/class/power_supply/*; do
    [[ -f "$dev/type" ]] || continue
    if grep -q '^Mains$' "$dev/type"; then
      if [[ -r "$dev/online" ]] && [[ "$(cat "$dev/online")" == "1" ]]; then
        return 0
      fi
    fi
  done
  return 1
}

apply_once() {
  if detect_ac; then
    if ! set_profile "performance"; then
      set_profile "balanced" || true
    fi
  else
    set_profile "power-saver" || true
  fi
}

case "${1:---apply}" in
  --ac)
    if ! set_profile "performance"; then
      set_profile "balanced" || true
    fi
    ;;
  --battery)
    set_profile "power-saver" || true
    ;;
  --apply|*)
    apply_once || true
    ;;
esac
EOF
  chmod +x "$tmp"
  local sudo
  sudo="$(get_sudo)"
  $sudo install -m 0755 "$tmp" "$HELPER_PATH"
  rm -f "$tmp"
  echo "Installed helper: $HELPER_PATH"
}

write_rules() {
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<EOF
# Power mode auto switch on AC adapter events
ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ENV{POWER_SUPPLY_ONLINE}=="1", RUN+="$HELPER_PATH --ac"
ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ENV{POWER_SUPPLY_ONLINE}=="0", RUN+="$HELPER_PATH --battery"
EOF
  local sudo
  sudo="$(get_sudo)"
  $sudo install -m 0644 "$tmp" "$RULE_PATH"
  rm -f "$tmp"
  echo "Installed udev rule: $RULE_PATH"
}

reload_udev() {
  local sudo
  sudo="$(get_sudo)"
  $sudo udevadm control --reload
}

trigger_once() {
  local sudo
  sudo="$(get_sudo)"
  # Trigger power_supply events to apply once, but also apply directly for robustness
  $sudo udevadm trigger --subsystem-match=power_supply || true
  "$HELPER_PATH" --apply || true
}

uninstall_all() {
  local sudo
  sudo="$(get_sudo)"
  if [[ -f "$RULE_PATH" ]]; then
    $sudo rm -f "$RULE_PATH"
    echo "Removed: $RULE_PATH"
  fi
  if [[ -f "$HELPER_PATH" ]]; then
    $sudo rm -f "$HELPER_PATH"
    echo "Removed: $HELPER_PATH"
  fi
  reload_udev || true
}

main() {
  if [[ "$UNINSTALL" == "1" ]]; then
    uninstall_all
    return 0
  fi

  require_binaries

  if [[ "$FORCE" != "1" && -f "$HELPER_PATH" ]]; then
    echo "Helper already installed; use FORCE=1 to reinstall"
  else
    write_helper
  fi

  if [[ "$FORCE" != "1" && -f "$RULE_PATH" ]]; then
    echo "Udev rule already installed; use FORCE=1 to reinstall"
  else
    write_rules
  fi

  reload_udev

  if [[ "$APPLY" == "1" ]]; then
    trigger_once
  else
    echo "Skipping immediate apply (APPLY=0)"
  fi

  echo
  echo "Done. Udev will switch power profiles on AC plug/unplug."
}

main "$@"


