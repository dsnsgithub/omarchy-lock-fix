## Why?
Fixes issues with S3 Sleep and screen blanking issues in Omarchy.

With this plugin, sleep and lock work perfectly.

The default in Omarchy is to blank the screen and keyboard RGB on the lock screen after only 5 seconds. This creates issues as some PC peripherals such as monitors take longer than 5 seconds to wake from sleep.

Installation:
```bash
omarchy plugin add https://github.com/dsnsgithub/omarchy-lock-fix
omarchy restart shell
```

## Fixed issues:
- Fixes issue where screen will turn off when I wake my computer from sleep, requiring many clicks on each monitor to wake them up. => Solution: Remove screen blanking after 5 seconds
- Fixes issue where I am unable to type the password to unlock => Solution: Remove keyboard rgb blanking after 5 seconds

This plugin solves:
- https://github.com/basecamp/omarchy/issues/7749
- https://github.com/basecamp/omarchy/issues/7399
- https://github.com/basecamp/omarchy/issues/7507

## Longer term solution
My plugin works, but it serves as a temporary fix while they work out a better solution. Here are a couple suggestions:

Make screen blank wait time configurable, increase it to >30 seconds. Create a configuration to disable this "screen blanking" entirely.

A combination of these 2 PRs (with some polish):
- https://github.com/basecamp/omarchy/pull/7673
- https://github.com/basecamp/omarchy/pull/7643

## Gaze face unlock (Windows Hello style)

Version 2 adds [Gaze](https://github.com/GunduLabs/gaze) integration: on-device face recognition through the camera, so the lock screen unlocks by looking at it. Your password keeps working exactly as before - face scanning rides alongside it, never instead of it.

### What the plugin does

**Guides setup automatically.** When the shell starts and Gaze is missing, its daemon (`gazed`) is stopped, or no face is enrolled, a small card appears at the bottom-right of the desktop (never over the lock screen). One button runs the bundled `gaze-setup.sh` in a terminal:

1. Installs `gaze-bin` from the AUR (via `omarchy pkg aur add`, `paru` or `yay`)
2. Enables and starts the `gazed` system daemon
3. Enrolls a face (`gaze add-face default`) with the live camera preview
4. Verifies with `gaze auth`

The card re-checks every few seconds while open and disappears when everything is ready. Run it again anytime with `omarchy-shell ipc call lock gazeSetupRun`.

**Scans on lock.** Once configured (gaze installed + daemon running + face enrolled), every lock starts a short burst of face scans through PAM (`pam_gaze.so`). A match unlocks instantly, Windows Hello style. After 3 failed scans it goes quiet so it never fights your typing, and any mouse move or keystroke rearms it. A face icon appears on the left of the password field and the placeholder reads "Scanning Face…" while scanning.

**No system file edits.** The plugin ships its own PAM service file (`omarchy-lock-gaze`, `auth required pam_gaze.so`) next to `Service.qml` and points Quickshell's PamContext at the plugin directory - nothing is written to `/etc/pam.d`. Note that installing the upstream `gaze-bin` package itself adds `auth sufficient pam_gaze.so` to `sudo` and `polkit-1`; that is upstream behavior and also makes `sudo` work with your face.

**Fingerprint coexists.** If you already have fingerprint auth, both work; each starts its own PAM conversation and the first success wins.

### CLI status and control

```bash
omarchy-shell ipc call lock gazeStatus    # JSON: state, configured, enabled, scanning
omarchy-shell ipc call lock gazeSetup     # show the setup card
omarchy-shell ipc call lock gazeSetupRun  # open a terminal and run the setup script
omarchy-shell ipc call lock gazeSetupHide # hide the setup card for this session
omarchy-shell ipc call lock gazeDisable   # stop face auth (write ~/.local/state/omarchy/dsns.lock-gaze-disabled)
omarchy-shell ipc call lock gazeEnable    # re-enable face auth
```

Card dismissals also persist as state files in `~/.local/state/omarchy/` (`dsns.lock-gaze-disabled`, `dsns.lock-gaze-dismissed`); remove them to bring the guide back.

### Troubleshooting

- `gaze doctor` checks the daemon, camera, enrollment and PAM wiring
- `journalctl -u gazed` for daemon logs
- Scans never start if the daemon or an enrollment is missing - the plugin only arms `pam_gaze.so` when `gaze list-faces` reports a face
- The setup script can be run by hand from any terminal: `bash <plugin dir>/gaze-setup.sh`

## Compare changes:

Diff vs the stock lock plugin (`omarchy.lock`):
`diff /usr/share/omarchy/shell/plugins/lock Service.qml` => [dsns.diff](https://github.com/dsnsgithub/omarchy-lock-fix/blob/main/dsns.diff)

New files beyond the diff: `GazeSetupCard.qml`, `gaze-setup.sh`, `omarchy-lock-gaze` (plugin-local PAM service).

## Creating your own plugin

```bash
omarchy clone omarchy.lock
```

Edit the resulting [user].lock file.
