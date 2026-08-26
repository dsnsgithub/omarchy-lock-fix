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
- Fixes issue where pressing Enter does nothing when the password box is empty or unfocused => Solution: Enter always submits, from anywhere on the lock screen

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

## Compare changes:
manifest.json is for metadata.

Diff:
`diff /usr/share/omarchy/shell/plugins/lock .` => [dsns.diff](https://github.com/dsnsgithub/omarchy-lock-fix/blob/main/dsns.diff)

## Creating your own plugin

```bash
omarchy clone omarchy.lock
```

Edit the resulting [user].lock file.
