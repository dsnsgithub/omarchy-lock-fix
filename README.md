Fixes issues with S3 Sleep and screen blanking issues in Omarchy.

With this plugin, sleep and lock work perfectly.

For some reason in Omarchy, the default is to blank the screen and keyboard RGB on the lock screen, which makes no sense to me.

## Fixed issues:
- Fixes issue where screen will just turn off when I wake my computer from sleep, forcing me to click many times on each monitor to wake them up. => Remove screen blanking after 5 seconds
- Fixes issue where I am unable to type the password to unlock => remove keyboard rgb blanking after 5 seconds (only causes problems)

## Compare changes:

The changes are intentionally verbose that they were created by me so that any issues caused by this removed blanking can be traced back to the plugin, sorry about that 😅.

diff /usr/share/omarchy/shell/plugins/lock Service.qml
No changes to LockView.qml, manifest.json is for metadata.

```bash
omarchy clone omarchy.lock
```

Edit the resulting [user].lock file.
