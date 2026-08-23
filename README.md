Fixes issues with S3 Sleep and screen blanking issues in Omarchy.

With this plugin, sleep and lock work perfectly.

The default in Omarchy is to blank the screen and keyboard RGB on the lock screen after only 5 seconds. This creates issues as some PC peripherals such as monitors take longer than 5 seconds to wake from sleep.

## Fixed issues:
- Fixes issue where screen will turn off when I wake my computer from sleep, requiring many clicks on each monitor to wake them up. => Solution: Remove screen blanking after 5 seconds
- Fixes issue where I am unable to type the password to unlock => Solution: Remove keyboard rgb blanking after 5 seconds

## Compare changes:
The changes are intentionally verbose so that any issues caused by this removed blanking can be traced back to the plugin, sorry about that 😅.

diff /usr/share/omarchy/shell/plugins/lock Service.qml
No changes to LockView.qml, manifest.json is for metadata.

```bash
omarchy clone omarchy.lock
```

Edit the resulting [user].lock file.
