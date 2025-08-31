## Utility Scripts

Bash installers and automation helpers for Linux desktops, focused on user-level installs under `$HOME`.

### Contents
- `install-cursor.sh`: Install/upgrade Cursor editor (AppImage) into `$HOME/Applications/cursor`, wrapper in `~/.local/bin/cursor`.
- `install-lm_studio.sh`: Install/upgrade LM Studio (AppImage) into `$HOME/Applications/lmstudio`, wrapper `~/.local/bin/lmstudio-gui`.
- `install-obsidian.sh`: Install/upgrade Obsidian (AppImage) into `$HOME/Applications/obsidian`, wrapper `~/.local/bin/obsidian`.
- `install-protonvpn.sh`: Install/uninstall Proton VPN via official apt repo (requires sudo).
- `install-power-mode-auto-switch.sh`: User-level systemd service that auto-switches GNOME power profiles on AC/battery.
- `install-power-mode-udev.sh`: Root-level udev rules to auto-switch GNOME power profiles on AC/battery.

### Quick start
- Cursor: `bash install-cursor.sh`
- LM Studio (beta default): `bash install-lm_studio.sh` or `CHANNEL=stable bash install-lm_studio.sh`
- Obsidian: `bash install-obsidian.sh`
- Proton VPN (stable): `bash install-protonvpn.sh` (add `-y` for non-interactive)
- Power mode (user service): `bash install-power-mode-auto-switch.sh`
- Power mode (udev): `bash install-power-mode-udev.sh`

If `~/.local/bin` is not in your PATH, add it:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
```

### Script details and usage

#### Cursor (`install-cursor.sh`)
- Resolves the latest build via `api2.cursor.sh` (falls back as needed).
- Installs to `$HOME/Applications/cursor/cursor-<ver>.AppImage`, creates wrapper `~/.local/bin/cursor` and a desktop entry.
- Prompts before terminating running instances.
- Env/flags:
  - `CHANNEL=stable|prerelease` (default: `stable`)
  - `--force` or `-f` to reinstall even if up-to-date

Examples:
```bash
bash install-cursor.sh
CHANNEL=prerelease bash install-cursor.sh
bash install-cursor.sh --force
```

#### LM Studio (`install-lm_studio.sh`)
- Resolves latest version from LM Studio downloads (stable falls back to beta if not resolvable).
- Installs to `$HOME/Applications/lmstudio/LM-Studio-<ver>-x64.AppImage`.
- Creates `~/.local/bin/lmstudio-wrapper` and `~/.local/bin/lmstudio-gui`, plus a desktop entry.
- Attempts to install the `lms` CLI if Node/npm is present: `npx --yes lmstudio install-cli`.
- Prompts before terminating running instances.
- Env:
  - `CHANNEL=beta|stable` (default: `beta`)

Examples:
```bash
bash install-lm_studio.sh
CHANNEL=stable bash install-lm_studio.sh
```

#### Obsidian (`install-obsidian.sh`)
- Fetches the latest AppImage via GitHub Releases (with HTML fallback).
- Installs to `$HOME/Applications/obsidian/obsidian-<ver>.AppImage`, symlink `~/.local/bin/obsidian`, desktop entry.
- Prompts before terminating running instances.

Examples:
```bash
bash install-obsidian.sh
```

#### Proton VPN (`install-protonvpn.sh`)
- Adds the official Proton VPN apt repository and installs the GNOME desktop app.
- Supports switching between stable/beta channels and uninstalling.
- Can optionally install tray indicator dependencies for GNOME.
- Requires `sudo` for apt operations. Use `-y` or `--yes` for non-interactive runs.

Flags/env and actions:
```bash
bash install-protonvpn.sh --help
CHANNEL=stable WITH_TRAY=1 bash install-protonvpn.sh
CHANNEL=beta bash install-protonvpn.sh -y -f
bash install-protonvpn.sh --uninstall
bash install-protonvpn.sh --disable-killswitch
```

#### Power mode auto-switch — user service (`install-power-mode-auto-switch.sh`)
- Uses a user-level systemd service and UPower events to switch power profiles:
  - AC: `performance` (fallback `balanced`)
  - Battery: `power-saver`
- Provides CLI `power-mode-auto` to manage the service and manual actions.
- Dependencies: `upower`, `powerprofilesctl`, `systemd --user`.
- Env:
  - `ENABLE=1|0` (default `1`) — enable/start service after install
  - `FORCE=1` to overwrite existing files

Examples:
```bash
bash install-power-mode-auto-switch.sh
ENABLE=0 bash install-power-mode-auto-switch.sh
power-mode-auto status
power-mode-auto pause && power-mode-auto resume
```

#### Power mode auto-switch — udev (`install-power-mode-udev.sh`)
- Installs root-level udev rules and a small helper under `/usr/local/bin`.
- Requires `sudo` (the script will call sudo when needed).
- Env:
  - `FORCE=1` to reinstall
  - `APPLY=0` to skip immediate apply
  - `UNINSTALL=1` to remove rules/helper

Examples:
```bash
bash install-power-mode-udev.sh
UNINSTALL=1 bash install-power-mode-udev.sh
```

### Development
- Lint: `shellcheck *.sh` — fix all warnings.
- Format: `shfmt -i 2 -w *.sh` — 2-space indentation.
- Sanity check: run each script twice to confirm idempotency and safe prompts.

### Testing
- If adding tests, use Bats in `tests/`.
- Mock network calls and external binaries; verify idempotency and file placements under `$HOME`.

### Notes and security
- Scripts prefer user-level locations (`$HOME/Applications`, `~/.local/bin`, `~/.local/share/applications`).
- `install-protonvpn.sh` and `install-power-mode-udev.sh` require elevated privileges for system changes.
- Ensure `~/.local/bin` is in your PATH.


