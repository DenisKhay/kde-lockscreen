# KDE Lock Screen — Design Spec

**Date:** 2026-04-17
**Owner:** Denis Khaydarshin
**Target platform:** Kubuntu 24.04 · Plasma 5.27 · Qt5 · KF5

---

## 1. Goal

Replace the default KDE Plasma lock screen with a custom one that:

1. Unlocks **fast** (<200 ms from last keystroke to desktop) — the current 3+ second delay is the primary pain point.
2. Shows a **different Bing-style background image per monitor**, rotating daily, with a **"next image" gesture** if an image isn't liked.
3. Accepts the PIN **without clicking anything** (type immediately) and shows entered characters as **physically-sized dots (3–5 mm)**.
4. **Never suspends** the machine while locked, though the display may turn off.
5. Shows the **username** and a **clock/date**.
6. Ships a **config panel** (KDE System Settings) and a mirrored config file.

A second version (v2) will add a Teams unread-notification indicator integrated with the existing `teams-notifications` daemon. v1 ships without it.

---

## 2. Non-goals

- Replacing the full Plasma Look-and-Feel theme. Only the `lockscreen` component is customized.
- Supporting Plasma 6 (Wayland/Qt6). Can be ported later; not in scope.
- Teams notification indicator (v2).
- Media controls — reuse Breeze's unchanged.

---

## 3. Architecture

Three independent runtime pieces plus one one-time install-time system change.

```
┌──────────────────────────────────────────────────────────┐
│ kscreenlocker_greet  (started by kscreenlockerd on lock) │
│   └─ loads our Look-and-Feel package:                    │
│       package/contents/lockscreen/*.qml                  │
│       ← reads images from ~/.cache/kde-lockscreen/       │
│       ← reads config from ~/.config/kde-lockscreen.conf  │
│       → calls PAM via authenticator.tryUnlock(pwd)       │
└──────────────────────────────────────────────────────────┘
                       ▲
                       │ reads cache dir
                       │
┌──────────────────────────────────────────────────────────┐
│ kde-lockscreen-fetcher.service  (systemd --user, daily)  │
│   Python. Pulls one image per enabled source per day.    │
│   Writes ~/.cache/kde-lockscreen/YYYY-MM-DD-<source>.jpg │
│   + manifest.json (metadata + disliked flags).           │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│ kde-lockscreen-inhibitd.service  (systemd --user, always)│
│   Python. Watches org.freedesktop.ScreenSaver D-Bus.     │
│   On ActiveChanged(true): spawns systemd-inhibit sleep.  │
│   On ActiveChanged(false): kills the inhibit subprocess. │
│   Inhibits sleep + idle-transition, not DPMS.            │
└──────────────────────────────────────────────────────────┘

       One-time at install (reversible):
       /etc/pam.d/kde → backed up, replaced by optimized version.
```

**Why three separated pieces:** `kscreenlocker_greet` is short-lived; it starts on lock and exits on unlock. It can't hold a persistent cache, own a D-Bus subscription, or fetch over the network with a UX-acceptable latency. So fetching lives in a daily user timer, sleep-inhibit lives in a long-running user service, and the greeter stays purely reactive.

---

## 4. Repository layout

```
kde-lockscreen/
├── package/
│   └── contents/
│       └── lockscreen/
│           ├── LockScreen.qml          # ~30 LOC, entry point
│           ├── LockScreenUi.qml        # ~150 LOC, root UI
│           ├── BackgroundLayer.qml     # ~60 LOC, image + blur + dim
│           ├── CenterStack.qml         # ~100 LOC, clock/user/dots
│           ├── Clock.qml               # ~40 LOC
│           ├── PinInput.qml            # ~80 LOC, invisible TextInput
│           ├── PinDots.qml             # ~60 LOC, mm-sized circles
│           ├── ImageRegistry.qml       # ~50 LOC, reads manifest
│           ├── NextImageHint.qml       # ~30 LOC, bottom-right cue
│           ├── config.qml              # ~120 LOC, settings panel
│           ├── config.xml              # ~40 LOC, schema
│           └── fallback.jpg            # bundled gradient
│   └── metadata.desktop                # ~25 LOC, KPackage manifest
├── daemon/
│   ├── fetcher.py                      # daily image fetch
│   ├── inhibitd.py                     # sleep-inhibit daemon
│   └── sources/                        # per-source fetchers
│       ├── bing.py
│       ├── wikimedia.py
│       ├── nasa.py
│       └── unsplash.py                 # with picsum fallback
├── systemd/
│   ├── kde-lockscreen-fetcher.service
│   ├── kde-lockscreen-fetcher.timer
│   └── kde-lockscreen-inhibitd.service
├── pam/
│   └── kde.optimized                   # target /etc/pam.d/kde
├── scripts/
│   ├── install.sh
│   ├── install-dev.sh                  # symlink mode
│   ├── install-pam.sh                  # sudo portion
│   ├── uninstall.sh
│   ├── pam-diagnose.sh                 # per-module timing profiler
│   └── test-greeter.sh                 # kscreenlocker_greet --testing
├── docs/
│   └── superpowers/specs/2026-04-17-kde-lockscreen-design.md
├── CLAUDE.md
└── README.md
```

Total QML/config: ~755 LOC, 10 files, none over 150 LOC. Python: ~400 LOC, 2 daemons + 4 source modules.

---

## 5. QML component details

### 5.1 Typing without focus

`LockScreenUi` takes focus on `Component.onCompleted` (`forceActiveFocus()`), then the root-level `Keys.onPressed` handler forwards every keystroke to an invisible `PinInput`'s `TextInput`. This is the load-bearing trick that lets the user type immediately on lock.

Special keys:
- **Digits / letters**: appended to PIN text.
- **Backspace**: removes one character.
- **Enter**: submits (even if autoSubmit is on and length is unmet).
- **Right arrow** or **N key**: "next image" on the **primary screen**. To target the secondary screen, click its own `NextImageHint` (each screen renders its own hint in its own bottom-right corner).
- **Escape**: clears the current PIN input without error.

### 5.2 Multi-monitor backgrounds

`LockScreenUi` uses `QtQuick.Window.Screen` and a `Repeater` over `Qt.application.screens` to instantiate one `BackgroundLayer` per monitor. `ImageRegistry.pickForScreen(index)` deterministically assigns an image per screen (seeded by date + screen index) so the same config gives the same pair until "next image" is invoked.

### 5.3 Physical-size dots

`PinDots` sets each dot's width/height to `config.dotSizeMm * Screen.pixelDensity` (Qt exposes `pixelDensity` in dots-per-mm). Default 4 mm → ~29 px on a 188-DPI 2560×1600 panel.

### 5.4 Smart fit

`BackgroundLayer` checks `image.sourceSize` vs screen aspect:
- Landscape image on landscape screen → `Image.PreserveAspectCrop` (cover).
- Portrait / odd-ratio image → `PreserveAspectFit` (contain) + a second blurred `Image` behind it filling the bars with a blown-up, heavily-blurred copy of the same image.

### 5.5 Auto-submit

`PinInput.onTextChanged`: if `autoSubmit && text.length === pinLength`, call `authenticator.tryUnlock(text)`. Enter key is always a valid submit regardless.

### 5.6 Error feedback

Wrong PIN → `ErrorHint` runs a 300 ms shake animation on `CenterStack`, clears `PinInput.text`, dims PIN dots briefly. No text error message — shake is enough.

---

## 6. Data flow

### 6.1 Install

`scripts/install.sh`:
1. Copies `package/` → `~/.local/share/plasma/look-and-feel/com.denisk.lockscreen/`.
2. Copies `daemon/` → `~/.local/lib/kde-lockscreen/`.
3. Installs systemd units to `~/.config/systemd/user/`, enables + starts them.
4. Runs fetcher once to seed `~/.cache/kde-lockscreen/`.
5. Sets `kscreenlockerrc.[Greeter].Theme=com.denisk.lockscreen` via `kwriteconfig5`.
6. Prompts for sudo → runs `scripts/install-pam.sh` (step 7).
7. `cp /etc/pam.d/kde /etc/pam.d/kde.bak.YYYY-MM-DD && install -m644 pam/kde.optimized /etc/pam.d/kde`.

### 6.2 Daily fetch

`kde-lockscreen-fetcher.timer` fires at 06:00 daily. For each enabled source:
1. GET today's image URL; GET image bytes.
2. Atomic write `~/.cache/kde-lockscreen/YYYY-MM-DD-<source>.jpg` (temp + rename).
3. Update `manifest.json` with `{path, source, date, width, height, disliked: false, assigned_to_screen: null}` — advisory flock.
4. Evict entries older than `maxDays` (default 14).

Failure of one source does not abort others; each failure logged to journal.

### 6.3 Lock cycle

1. User presses unlock hotkey / laptop lid / idle trigger → `kscreenlockerd` launches `kscreenlocker_greet`.
2. Greeter loads `com.denisk.lockscreen` Look-and-Feel → QML boots.
3. `ImageRegistry` reads `manifest.json`, picks 2 non-disliked images (date-seeded, one per screen).
4. `BackgroundLayer` instances render on each screen; root takes focus.
5. User types PIN → at target length, `authenticator.tryUnlock(pin)` fires.
6. PAM stack (now optimized) validates → success returns control to `kscreenlockerd` → greeter exits.
7. If PAM fails → shake + clear + retry (respects `pam_faillock` from PAM itself).

### 6.4 Sleep-inhibit lifecycle

`kde-lockscreen-inhibitd.service` runs as a long-lived user service:

```python
async for active in dbus.signal("org.freedesktop.ScreenSaver", "ActiveChanged"):
    if active and not inhibit_proc:
        inhibit_proc = subprocess.Popen([
            "systemd-inhibit",
            "--what=sleep:idle",
            "--why=KDE lock screen active",
            "--mode=block",
            "sleep", "infinity"
        ])
    elif not active and inhibit_proc:
        inhibit_proc.terminate()
        inhibit_proc = None
```

`--what=sleep:idle` explicitly excludes `handle-power-key` and `idle:display-off`, so DPMS still turns off the display — you wanted the screen to sleep but not the box.

### 6.5 "Next image" gesture

Right arrow / N key targets the primary screen's image. Clicking a per-screen `NextImageHint` targets that screen. Either path fires `ImageRegistry.markDisliked(currentPath, screenIndex)`:
1. Sets `disliked: true` in manifest (persists across reboots).
2. Picks a replacement image for that screen.
3. Rebinds `BackgroundLayer.source` → QML re-renders.

Tomorrow's fetch sees the disliked flag and won't re-pick that exact image (by URL hash). Disliked entries are evicted with the normal age policy.

---

## 7. PAM optimization strategy

### 7.1 Diagnose

`scripts/pam-diagnose.sh`:

1. Read `/etc/pam.d/kde` and the files it `@include`s.
2. Build `/etc/pam.d/kde-timed` — a copy of the live file with `pam_exec.so /tmp/pam-time.sh <module-name>` inserted between each module line. `pam-time.sh` appends `$(date +%s%N) <module>` to `/tmp/pam-time.log`. This staging file is only used by the profiler; the live `/etc/pam.d/kde` is untouched during diagnosis.
3. Run `pamtester kde-timed "$USER" authenticate` with a deliberately-wrong input 3 times.
4. Parse log, compute per-module deltas, print sorted.

### 7.2 Expected culprits (Kubuntu 24.04, order of likelihood)

1. **`pam_kwallet5.so`** in the `auth` section — waits on kwallet socket, blocks auth success. Fix: remove from `/etc/pam.d/kde`; let Plasma autostart open kwallet via its normal autostart entry.
2. **`pam_systemd.so`** — usually fast but can stall on cgroup setup. Fix: nothing unless diagnosis says so.
3. **`sss_pam` / `pam_krb5`** — network-auth modules with default timeouts. Fix: add `[default=ignore]` line-flags so they don't block on timeout.

### 7.3 Ship

`pam/kde.optimized` is committed to the repo as a reference diff. `scripts/install-pam.sh` (sudo) backs up the live file to `/etc/pam.d/kde.bak.YYYY-MM-DD` and installs the optimized version. `scripts/uninstall.sh` restores the most recent backup.

### 7.4 Success criterion

After install, `time pamtester kde $USER authenticate <<< "$PIN"` reports **< 200 ms real time**. If diagnosis shows the delay isn't in PAM (e.g. it's in Qt's `authenticator` wrapper itself), the spec requires raising a scope change — we don't ship a solution that fails the speed goal.

---

## 8. Image source adapters

Each in `daemon/sources/<name>.py`, exports one function: `fetch() -> (bytes, meta_dict)`.

- **Bing**: `https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US` → parse `images[0].url`, prepend `https://www.bing.com`, GET.
- **Wikimedia POTD**: `https://en.wikipedia.org/w/api.php?action=featuredfeed&feed=potd&feedformat=atom` → parse first `<enclosure>`, GET.
- **NASA APOD**: `https://api.nasa.gov/planetary/apod?api_key=DEMO_KEY` → if `media_type == "image"`, GET `hdurl` else `url`. Skip if video.
- **Unsplash / Picsum**: config flag `usePicsumInstead=true` (default) → GET `https://picsum.photos/2560/1600` (no key, truly registration-free). Else GET `https://api.unsplash.com/photos/random?orientation=landscape&client_id=<key>`.

All HTTP via `urllib.request` with a 10-second timeout. Bytes written atomically.

---

## 9. Configuration

Stored at `~/.config/kde-lockscreen.conf`, mirrored to `kscreenlockerrc` keys under `[Greeter]`. **File wins on conflict** (per user choice). The KDE config panel (System Settings → Screen Locking → Configure) edits both.

```ini
[General]
pinLength=6
autoSubmit=true
dotSizeMm=4
blurRadius=32
dimAlpha=0.4
fitMode=smart          # cover | contain | smart

[Sources]
bing=true
wikimedia=true
nasa=true
unsplash=false
unsplashApiKey=
usePicsumInstead=true

[Cache]
maxDays=14
cacheDir=~/.cache/kde-lockscreen
```

Reload behavior: config changes apply on next lock. No hot-reload in v1.

---

## 10. Error handling

| Condition                      | Behavior                                              |
| ------------------------------ | ----------------------------------------------------- |
| Cache dir empty                | Render bundled `fallback.jpg` (~50 KB gradient)       |
| `manifest.json` corrupt/missing| `ImageRegistry` rebuilds by scanning filenames        |
| PAM call fails                 | Shake + clear PIN; no hang, no cryptic message        |
| Fetcher offline                | Log to journal; retry next timer tick; don't crash    |
| Inhibitd D-Bus drops           | systemd `Restart=on-failure` respawns                 |
| Wrong PIN                      | Delegate lockout to `pam_faillock` — don't duplicate  |
| Image source 404 / 500         | Skip that source; other sources still attempted       |
| Image > 50 MB                  | Reject; log; try next source                          |

---

## 11. Testing / dev loop

1. **`scripts/test-greeter.sh`**: `QT_QPA_PLATFORM=xcb kscreenlocker_greet --testing --theme com.denisk.lockscreen` — runs the greeter in a window without actually locking. `authenticator` is stubbed in testing mode.
2. **`scripts/install-dev.sh`**: symlinks `package/` → `~/.local/share/plasma/look-and-feel/com.denisk.lockscreen/` so QML edits are live. Reload by re-locking.
3. **QML error tail**: `journalctl --user -b -t kscreenlocker_greet -t ksmserver -t plasmashell`.
4. **PAM benchmark**: `time pamtester kde $USER authenticate <<< "$PIN"`. Must be < 200 ms after install.
5. **Real lock flow**: `loginctl lock-session` → type PIN. Verify dots render, multi-monitor, unlock latency.
6. **"Next image"**: press N / right arrow mid-lock; cached manifest should gain a `disliked: true` entry for that path.

No automated unit tests for the QML layer in v1 — manual smoke on each of the 6 steps above is sufficient for this scope. Python daemons get simple `pytest` coverage for the source adapters and manifest-manipulation logic.

---

## 12. Open gaps deferred to v2

- Teams unread indicator — requires extending `teams-notifications` daemon to write a state file.
- Avatar display alongside username.
- Multi-user support (currently assumes single-user system).
- Wayland / Plasma 6 port.
- Hot-reload config without re-locking.
