# MorsCast fork

MorsCast is a personal fork of [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar,
distributed under the same AGPL-3.0 licence. It adds Soniox cloud dictation and ships under its own
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

The app never offers upstream releases: `ReleaseChannel` treats any non-Tinycast bundle id as a
development build, which does not update.
