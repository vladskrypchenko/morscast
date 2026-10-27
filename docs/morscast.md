# MorsCast fork

MorsCast is a personal fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar,
distributed under the same AGPL-3.0 licence. It adds Soniox cloud dictation and Caffeine (keep
awake from the menu-bar menu or the Toggle Caffeine action, `Features/Caffeine/`), and ships under its own
name, bundle id (`com.morscast.app`, Debug `com.morscast.app.dev`) and Apple Development signature.

Internal source names (`Tinycast/` folder, type names) stay unchanged so upstream rebases stay small.
The visible name comes from the string catalogs, rewritten by `Scripts/morscast-rebrand.py`.

## Pulling upstream

```sh
git checkout main && git pull --ff-only
git checkout my-soniox && git rebase main
```

If a rebase conflicts in `Localizable.xcstrings` or `InfoPlist.xcstrings`, take upstream's file
(`git checkout --theirs <file>` during the rebase), run `python3 Scripts/morscast-rebrand.py`,
then `git add` and `git rebase --continue`. Then `xcodegen generate` and rebuild.

## Updates

`com.morscast.app` is the stable channel. It checks
[vladskrypchenko/morscast](https://github.com/vladskrypchenko/morscast) releases 30 s after launch
and then every 6 hours, and installs only a zip signed by team `BV8636DZJY`. Debug builds never update.

To release: bump `MARKETING_VERSION` in `project.yml`, `xcodegen generate`, build Release, then
`ditto -c -k --keepParent MorsCast.app MorsCast-<version>.zip` and
`gh release create v<version> MorsCast-<version>.zip`.
