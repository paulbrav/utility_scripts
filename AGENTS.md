# Repository Guidelines

See `README.md` for a high-level overview and usage of each installer.

## Available Installers
- `install-cursor.sh` — Install/upgrade Cursor editor (AppImage) under `$HOME` with wrapper and desktop entry.
- `install-lm_studio.sh` — Install/upgrade LM Studio (AppImage), wrapper `lmstudio-gui`, optional `lms` CLI.
- `install-obsidian.sh` — Install/upgrade Obsidian (AppImage) under `$HOME` with `obsidian` command.
- `install-protonvpn.sh` — Manage Proton VPN via official apt repository (install/uninstall, channel switch).
- `install-power-mode-auto-switch.sh` — User-level systemd service to auto-switch GNOME power profiles.
- `install-power-mode-udev.sh` — Root-level udev rules to auto-switch GNOME power profiles.

## Project Structure & Module Organization
- Source: Bash installer scripts live at the repo root (e.g., `install-cursor.sh`, `install-lm_studio.sh`, `install-obsidian.sh`).
- New tools: Add as `install-<tool>.sh` in the root. Keep each script self‑contained and idempotent.
- Install targets (runtime): place app binaries under `$HOME/Applications/<app>/`, create wrappers in `~/.local/bin/`, and `.desktop` files in `~/.local/share/applications/`. Icons go under `~/.local/share/icons/`.

## Build, Test, and Development Commands
- Run locally: `bash install-cursor.sh` and `bash install-lm_studio.sh`. For LM Studio channel selection: `CHANNEL=stable bash install-lm_studio.sh` (default is `beta`).
- Lint: `shellcheck *.sh` — fix all warnings before opening a PR.
- Format: `shfmt -i 2 -w *.sh` — use 2‑space indentation.
- Sanity check: run scripts twice to confirm idempotency and safe prompts when processes are active.

## Coding Style & Naming Conventions
- Shebang and safety: `#!/usr/bin/env bash` with `set -Eeuo pipefail` at the top.
- Naming: functions `lower_snake_case`; constants `UPPER_SNAKE_CASE`; files `install-<tool>.sh`.
- Practices: use `local` for function variables; prefer `curl -fsSL` and `jq` for JSON; avoid `sudo` — target user‑level locations.

## Testing Guidelines
- Framework: if adding tests, use Bats. Place tests in `tests/` (e.g., `tests/install_cursor.bats`).
- Strategy: mock network calls and external binaries; verify idempotency, prompts, and file placements under `$HOME`.
- Run: `bats tests/` (when Bats is installed). Keep meaningful coverage for new functionality.

## Commit & Pull Request Guidelines
- Commits: follow Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`). Example: `feat(cursor): add prerelease channel fallback`.
- PRs: include a clear summary, rationale, manual test plan (commands run, expected output), relevant logs/screenshots, and environment notes (distro, PATH).

## Security & Configuration Tips
- Prefer HTTPS endpoints; validate downloads when possible. Write only under `$HOME`.
- Ensure `~/.local/bin` is in `PATH`; scripts should print hints if missing.
- Prompt before terminating processes; never assume elevated privileges.

