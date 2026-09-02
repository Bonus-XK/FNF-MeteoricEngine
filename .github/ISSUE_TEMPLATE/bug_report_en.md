---
name: Bug Report (English)
about: Report a Meteoric Engine defect (the more complete, the faster we can fix)
title: "[Bug] "
labels: ["bug"]
---

<!--
  Thank you for reporting! Please fill in as much as possible.
  Items marked * are required. For Android users, the crash log is the key to locating the issue (see "Crash Log" below).
-->

## 1. Basic Info *

- **Engine version** (`Meteoric Engine vX.X.X` shown in the main menu / FPS overlay):
- **Build/package version** (Android: Settings → Apps → Meteoric Engine, or APK filename / MD5):
- **Platform & OS**:
  - [ ] Android (device model: ____, Android version: ____, ROM such as MIUI/HyperOS/ColorOS/Stock: ____)
  - [ ] macOS (version: ____, Apple Silicon / Intel: ____)
  - [ ] Windows (version: ____)
- **Installation**:
  - [ ] Fresh install
  - [ ] Upgrade over existing (previous version: ____)

## 2. Steps to Reproduce * (required, the more specific the better)

1.
2.
3.

> Please also try reproducing with **all mods disabled** (clean environment) and note:
- Reproduces without mods: Yes / No
- Enabled mods (Mods menu):

## 3. Actual vs Expected Behavior *

- **Actual** (what happened):
- **Expected** (what should happen):

## 4. Screenshots / Screen Recording

(Optional but very helpful: drag screenshots into this box; link to a recording is fine too.)

## 5. Crash Log (Android users: please provide this) *

- **Android**: files in the `.meteoric/crash/` folder at the phone's root (**hidden folder** — enable "Show hidden files" in your file manager):
  - `MeteoricEngine_*.txt` (crash report with call stack)
  - `last_stage.txt` (last stage before a native crash)
  - Any Toast message text shown by the game
- **Desktop**: logs inside the `crash/` folder next to the game
- **adb logcat** (optional; enable USB debugging in Developer Options):
  ```
  adb logcat -d > logcat.txt
  ```
  Attach `logcat.txt`.

## 6. Related Settings (performance / rendering related)

- Performance mode (perfMode): On / Off
- High-DPI rendering: 2x High Quality / 1x High Performance
- Framerate cap: 120 / 240 / 480 / Uncapped
- HUD Only / Allow GC / Rating Popups / Combo Popups: On / Off
- Pre-render notes (early rendering): On / Off

## 7. Additional Notes

(Frequency: always / intermittent (about once every ____ times); related to a specific song/chart/mod?; recent changes, etc.)
