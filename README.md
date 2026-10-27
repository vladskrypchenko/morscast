# MorsCast

**A tiny, fully native macOS launcher. One hotkey, everything you reach for all day, under 100 MB of
RAM.**

<p align="center">
  <a href="https://github.com/vladskrypchenko/morscast/releases/latest">
    <img alt="Latest release"
         src="https://img.shields.io/github/v/release/vladskrypchenko/morscast?sort=semver&style=flat&label=release&color=1F6FEB"></a>
  <img alt="Swift 6.0"
       src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white">
  <img alt="macOS 26 or later"
       src="https://img.shields.io/badge/macOS-26%2B-000000?style=flat&logo=apple&logoColor=white">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

SwiftUI and AppKit, **zero third-party dependencies**, no Electron and no telemetry. It also **runs
real Raycast extensions**, rendered as native SwiftUI.

MorsCast is based on [Tinycast](https://github.com/abue-ammar/tinycast) by Abue Ammar.

<p align="center">
  <img src="docs/screenshot.png" alt="MorsCast command palette" width="720">
</p>

## Install

<p align="center">
  <a href="https://github.com/vladskrypchenko/morscast/releases/latest">
    <img alt="Download MorsCast"
         src="https://img.shields.io/badge/Download-MorsCast-1F6FEB?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>

1. Download `MorsCast-<version>.zip` from the
   [latest release](https://github.com/vladskrypchenko/morscast/releases/latest) and unzip it.
2. Move `MorsCast.app` to **Applications**.
3. Open it. MorsCast is signed but not notarized, so on first launch macOS blocks it: go to
   **System Settings → Privacy & Security** and click **Open Anyway** next to MorsCast. Once is enough.

Requires an Apple silicon Mac with macOS 26 or newer. MorsCast checks for new releases on its own and
installs them after you confirm.

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).
- **Search Files** — open files and folders from the folders you choose, through Spotlight, with no
  index of our own.
- **Dictionary** — look a word up with the Define Word command, or define whatever you typed from the
  launcher's fallbacks, read from the Mac's own dictionaries.
- **Dictation** — hold a key and talk: streams to Soniox and types each word as it is recognized,
  with a live preview in one small capsule. Local on-device models work too.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Calculator** — do math, unit, live currency and crypto conversions inline, right in the palette.
- **Quicklinks** — turn a URL, search, file or deeplink into a command, with placeholders for typed
  input, the clipboard or the date.
- **Apple Shortcuts** — search and run the shortcuts you built in the Shortcuts app, with aliases and
  global hotkeys.
- **Snippets** — reusable Markdown templates with dynamic placeholders, arguments, nested references
  and optional keyword expansion.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Window management** — 34 Rectangle-style actions: halves, quarters, thirds, sizing, nudging,
  display moves, fullscreen and Spaces.
- **System actions** — lock, sleep, restart, empty trash, toggle appearance, Bluetooth, mute, hidden
  files, and more.
- **Calendar and meetings** — your next meeting on the empty palette and in the menu bar, one key to
  join it, or let it join itself.
- **Notes** — an unlimited collection of plain Markdown files in one floating editor, searchable from
  the palette and rendered as you write.
- **Emoji picker** — a searchable emoji grid, one keystroke away.
- **AI chat** — use your own key or an installed AI account: ask Quick AI from the palette, or keep
  longer conversations in the AI Chat window, with a searchable, pinnable history. Off out of the box,
  like every AI feature.
- **Quick Actions** — fix grammar, rewrite, translate or summarize the selected text in any app.
- **Raycast extensions** — run the ones you already have natively, rendered as SwiftUI.
- **Backup and import** — export your settings to a file, or import your setup from Raycast.

## License

[AGPL-3.0](LICENSE)
