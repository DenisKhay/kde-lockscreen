# kde-lockscreen

A custom KDE Plasma 5 lock screen for Kubuntu 24.04. Replaces the default Breeze lock screen with:

- **Sub-200 ms unlock** (vs. the default 3+ s caused by `pam_fprintd` in common-auth)
- **Rotating backgrounds** curated daily from Bing, Wikimedia POTD, NASA APOD, and Picsum
- **No-focus PIN entry** — just start typing; physical-mm-sized dots show progress
- **Sleep-inhibit** while locked (laptop doesn't suspend; display DPMS still works)
- **Image navigation** — `→` to see the next one, `←` to go back, `↓` to save the current to `~/Pictures/kde-lockscreen-saves/`
- **Interaction-activated UI** — idle shows only the clock; any mouse move or keystroke reveals the PIN dots
- **100-image cache** with priority-preserving eviction (Bing/Wikimedia/NASA kept longer than Picsum), topped up every 5 minutes

## Requirements

- **Kubuntu 24.04** / KDE Plasma **5.27** / Qt 5
- Python **3.11+**
- `kwriteconfig5`, `kpackagetool5` (included in Plasma)
- `pamtester` (`sudo apt install pamtester`) — optional, needed only for PAM diagnostics
- `Pillow` — used once during install to generate the fallback gradient (`pip3 install --user Pillow`)

## Install

```bash
git clone https://github.com/DenisKhay/kde-lockscreen.git
cd kde-lockscreen
make install
```

What `make install` does:

1. Copies the Plasma Look-and-Feel package to `~/.local/share/plasma/look-and-feel/com.denisk.lockscreen/` (substituting `$HOME` into the QML at copy time).
2. Creates a Python venv at `~/.local/lib/kde-lockscreen/venv/` and installs the daemon into it.
3. Installs three systemd `--user` units and enables them:
   - `kde-lockscreen-fetcher.timer` (daily 06:00 — pulls curated + Picsum seed)
   - `kde-lockscreen-refill.timer` (every 5 min — tops up Picsum when low)
   - `kde-lockscreen-inhibitd.service` (always-on — D-Bus sleep-inhibit + save queue)
4. Runs the fetcher once to seed `~/.cache/kde-lockscreen/`.
5. Sets `kscreenlockerrc.Theme` and `LookAndFeelPackage` to `com.denisk.lockscreen`.
6. Prompts for `sudo` and installs `/etc/pam.d/kscreenlocker` (optimized — no `pam_fprintd` timeout). Reversible via `uninstall.sh`.

## Uninstall

```bash
make uninstall
```

Reverts the theme to Breeze, removes systemd units, removes the daemon, and restores the original PAM config from the backup (`/etc/pam.d/kscreenlocker.bak.YYYY-MM-DD`) if one exists.

## Configuration

`~/.config/kde-lockscreen.conf` (INI format):

```ini
[General]
pinLength = 6
autoSubmit = true
idleSubmitMs = 10000
dotSizeMm = 4.0
blurRadius = 0
dimAlpha = 0.0
fitMode = cover

[Sources]
bing = true
wikimedia = true
nasa = true
usePicsumInstead = true
unsplashApiKey =

[Cache]
maxDays = 30
maxCacheSize = 100
dailyPicsumSeed = 20
refillCount = 15
cacheDir = ~/.cache/kde-lockscreen

[Save]
saveDir = ~/Pictures/kde-lockscreen-saves
```

Changes take effect on the next lock.

## Dev loop

```bash
# Run tests
make test

# Install just the QML package (skip venv/systemd/PAM) for quick iteration
make install-dev

# Preview in a window, no real lock
make preview

# Real lock
loginctl lock-session
```

## Keyboard shortcuts (lockscreen)

| Key | Action |
|-----|--------|
| Any printable | Append to PIN |
| Backspace | Delete last PIN char |
| Enter | Submit PIN manually |
| Escape | Clear PIN |
| `→` | Next image |
| `←` | Previous image (back through session history) |
| `↓` | Save current image to `~/Pictures/kde-lockscreen-saves/` |

## Architecture

Three runtime pieces plus one install-time system change. See `docs/superpowers/specs/2026-04-17-kde-lockscreen-design.md` for the full design.

```
┌─────────────────────────────────────────────────┐
│ kscreenlocker_greet  (per-lock; short-lived)   │
│  QML reads manifest + config, calls PAM        │
└─────────────────────────────────────────────────┘
                    ▲
                    │ reads
┌─────────────────────────────────────────────────┐
│ kde-lockscreen-fetcher (daily timer)           │
│  Pulls curated + Picsum seed → cache + manifest│
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│ kde-lockscreen-refill (5-min timer)            │
│  Tops up Picsum pool; self-throttles when full │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│ kde-lockscreen-inhibitd (always-on)            │
│  D-Bus sleep-inhibit while locked              │
│  Poll save-request → shutil.copy to Pictures   │
└─────────────────────────────────────────────────┘

Install-time: /etc/pam.d/kscreenlocker → fprintd-free auth stack
```

## Known limitations

- **Kubuntu 24.04 / Plasma 5.27 only** — the PAM service name (`kscreenlocker`) and the Look-and-Feel package format (`.desktop` + `X-Plasma-APIVersion=2`) are specific to this generation. Plasma 6 / Wayland port is not attempted.
- **Multi-monitor** shows the same image on every display. Per-monitor picks are a v2 item.
- **Teams unread indicator** is not yet wired up (v2). The `teams-notifications` sibling project exists at `~/Projects/teams-notifications` but needs a small extension to publish its state.

## License

MIT — see [LICENSE](LICENSE).
