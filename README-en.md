# JMComic3 Mod

[![Latest release](https://img.shields.io/github/v/release/khxw/JMcomic3-flutter)](https://github.com/khxw/JMcomic3-flutter/releases/latest)
[![Android](https://img.shields.io/badge/Android-ARM64-3DDC84?logo=android&logoColor=white)](https://github.com/khxw/JMcomic3-flutter/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.2-02569B?logo=flutter)](https://flutter.dev/)
[![Rust](https://img.shields.io/badge/Backend-Rust-000000?logo=rust)](https://www.rust-lang.org/)

[简体中文](README.md) · English

> This is an **unofficial modified fork** of JMComic3 Flutter and is not affiliated
> with the upstream maintainer. This fork focuses on responsive UI, download and
> export workflows, storage access, reader performance, and navigation.

Starting with the next build, the Android package ID will be
`io.github.khxw.jmcomic3mod`, allowing side-by-side installation with upstream.
The current `v1.7.45+74` APK still uses the old package ID.

<p align="center">
  <img src="mockup/home-redesign.png" width="330" alt="JMComic3 Mod home screen">
</p>

## Current release

**v1.7.45+74** · Android ARM64 · API 24+

- [Latest GitHub Release](https://github.com/khxw/JMcomic3-flutter/releases/latest)
- [Changelog](CHANGELOG.md)
- [Source branch](https://github.com/khxw/JMcomic3-flutter/tree/main)

## Download

| File | Purpose |
| --- | --- |
| `JMComic3-Flutter-v1.7.45-arm64-v8a-release.apk` | Android ARM64 devices |
| `SHA256SUMS.txt` | APK integrity verification |

This fork currently publishes only an **Android ARM64 APK**. ARM32, Windows,
and AAB packages are not provided for this modified release.

The APK is signed with a local debug certificate. It may not upgrade an
installation signed with another key. Back up bookshelf, history, and download
settings before upgrading. If a signature conflict appears, uninstall the old
version before installing this build.

## Features

- Redesigned home, search, profile, bookshelf, download detail, batch export,
  and settings screens.
- Responsive navigation and compact layouts for narrow screens, large text,
  light mode, and dark mode.
- Redesigned download cards with status, cover, percentage, and image counts.
- Successful downloads open the download list and highlight the new task.
- Chapter selection, select all, clear, batch export, and export result states.
- Custom download directory selection, storage permissions, write checks, and
  restoration of saved paths.
- Continuous, zoomable continuous, single-page, and double-page readers.
- Visible-page reading progress and safe reader cache/resource cleanup.
- Themes, locales, fonts, display refresh modes, network routes, and WebDAV.

## Installation

1. Download the ARM64 APK from the
   [latest release](https://github.com/khxw/JMcomic3-flutter/releases/latest).
2. Download and verify `SHA256SUMS.txt`.
3. Allow installation from the file manager if required.
4. Back up app data before replacing an installation with a different signature.

PowerShell verification:

```powershell
Get-FileHash .\JMComic3-Flutter-v1.7.45-arm64-v8a-release.apk -Algorithm SHA256
```

Current APK SHA-256:

```text
743DC7848F2733FDC6931482A86BD790567AC79A411C7897A85735A5FA465E23
```

## Build

See [docs/BUILDING.md](docs/BUILDING.md) and
[docs/RELEASING.md](docs/RELEASING.md).

- Flutter is pinned by [.fvmrc](.fvmrc).
- JDK 17 or newer is required.
- Android SDK 36 and NDK `25.2.9519653` are used by the current release setup.
- A complete Rust backend checkout or prebuilt JNI libraries are required.

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos lib test integration_test test_driver
flutter test --no-pub
flutter build apk --release --no-pub --target-platform android-arm64 --split-per-abi
```

## Security and privacy

- Login state, download paths, reading history, and WebDAV settings remain in
  app-local storage or user-selected folders.
- Keystores, `key.properties`, `android/local.properties`, APKs, and build
  outputs are not committed.
- Third-party services control their own availability and data policies.
- Download APKs only from this repository's Releases page.

## Known limitations

- The current Rust JNI backend has no per-comic pause/resume API.
- A custom download directory currently keeps a copy in addition to app-local
  download storage; deleting a task may not remove old external copies.
- Rust backend source is not included in this repository; the release uses the
  tracked prebuilt JNI libraries.

## References

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine): reader structure,
  continuous reading, gallery zoom, and progress interaction reference.
- [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python):
  mobile API protocol, request signing, login, and domain fallback reference.
- `zoomable_positioned_list` 1.1.0: vendored continuous-reader component.

See [REFERENCES.md](REFERENCES.md) for the complete reference scope and retained
notices. Upstream names, code, and content remain the property of their authors.

## Usage policy

Follow applicable laws, service terms, and content rights. The inherited project
policy prohibits commercial use and redistribution of content assets. This
repository provides application modifications and build instructions only, not
comic content.
