# JMComic3 Mod

[![Latest release](https://img.shields.io/github/v/release/khxw/JMcomic3-flutter)](https://github.com/khxw/JMcomic3-flutter/releases/latest)
[![Android](https://img.shields.io/badge/Android-ARM64-3DDC84?logo=android&logoColor=white)](https://github.com/khxw/JMcomic3-flutter/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.2-02569B?logo=flutter)](https://flutter.dev/)
[![Rust](https://img.shields.io/badge/Backend-Rust-000000?logo=rust)](https://www.rust-lang.org/)

[简体中文](README.md) · English

> This is an **unofficial modified fork** of JMComic3 Flutter and is not affiliated
> with the upstream maintainer. This fork focuses on responsive UI, download and
> export workflows, storage access, reader performance, and navigation.

The Android package ID is `io.github.khxw.jmcomic3mod`. Its distinct package
identity allows the modified app and upstream JMComic3 to be installed together.

<p align="center">
  <img src="mockup/home-redesign.png" width="330" alt="JMComic3 Mod home screen">
</p>

## Current release

**v1.8.180+309** · Android ARM64 · API 24+

- [Latest GitHub Release](https://github.com/khxw/JMcomic3-flutter/releases/latest)
- [Changelog](CHANGELOG.md)
- [Source branch](https://github.com/khxw/JMcomic3-flutter/tree/main)

## Download

| File | Purpose |
| --- | --- |
| `JMComic3-Mod-v1.8.180-arm64-v8a-release.apk` | Android ARM64 devices |
| `SHA256SUMS.txt` | APK integrity verification |

This fork currently publishes only an **Android ARM64 APK**. ARM32, Windows,
and AAB packages are not provided for this modified release.

Back up bookshelf, history, and download settings before upgrading.

## Features

- Redesigned home, search, profile, bookshelf, download detail, batch export,
  and settings screens.
- Redesigned Weekly Picks with uniform three-column cards and an auto-loading infinite feed.
- Long-press bookshelf grouping.
- Responsive navigation and compact layouts for narrow screens, large text,
  light mode, and dark mode.
- Redesigned download cards with status, cover, percentage, and image counts.
- Successful downloads open the download list and highlight the new task.
- Download tasks support pause, resume, resumable existing images, and
  configurable 1–8 worker threads.
- Update downloads support pause, resume, and cancel; cancelling stops the
  request and removes temporary files.
- Before installation, the app verifies file size, SHA-256, package name,
  version, path, and signing certificate. Any mismatch rejects installation.
- Chapter selection, select all, clear, batch export, and export result states.
- Custom download directory selection, storage permissions, write checks, and
  restoration of saved paths.
- Infinite and zoomable webtoon readers automatically continue into the next chapter.
- Redesigned reader app bar, paging controls, chapter list, and settings panels.
- Configurable image preloading in both directions or forward-only.
- The onboarding page uses a slow animated gradient, soft glows, and a reduced layout.
- Back from search results returns to the search landing page before leaving search.
- Comic search now prioritizes full titles, removes author/group/language decorations,
  splits common delimiters, filters fuzzy noise, and ranks exact matches first.
- Image search (test): find comics from a gallery or file image based on a cover or screenshot.
- Comic details resolve the same original publish date shown on the web,
  avoiding the latest update time being displayed as the publish date.
- Bookshelf folders and comic covers show update dots when new chapters arrive.
- Comic upscaling is temporarily disabled and no longer appears in settings or
  triggers local inference from the reader.
- The bottom-left reading status bar shows chapter progress, network type,
  battery percentage, and current time.
- The in-app open-source license center supports component search and full license details.
- Bottom navigation keeps a single sliding indicator with lighter page transitions.
- Full release notes are shown consistently in the startup prompt and Updates page.
- Login API 404, HTML, and network failures now rotate to another API route;
  a short message is shown when every route is unavailable.
- API and image routing now includes built-in fallback routes, with parallel
  dynamic route refresh, caching, and automatic switching on invalid responses.
- Profile details refresh automatically only once at startup. Pull-to-refresh is
  available afterward with a 30-second cooldown.
- The local bookshelf supports pull-to-refresh and sends update checks through
  one Rust batch API, querying up to eight comics concurrently with at most 64 IDs per batch.
- The bookshelf displays local content immediately and keeps the current list
  visible while refresh checks run, avoiding flicker.
- Redesigned update download progress with target version, percentage, file size,
  route, and verification state.
- The Pro, Settings, and Updates entries use one compact segmented control;
  About is available at the bottom of the settings page.
- The About page lists app information, project links, the upstream repository,
  open-source licenses, and the unofficial-fork disclaimer.
- Visible-page reading progress and safe reader cache/resource cleanup.
- The oversized reader image-error placeholder is fixed.
- Themes, locales, fonts, display refresh modes, network routes, and WebDAV.
- Automatic cover-cache pruning keeps covers below about 48 MB and 30 days
  without removing downloaded comics or reading data.
- Reader pages use temporary caching, with date-based cache statistics and cleanup.
- Home, comic detail, and list API caches now have TTL and size limits; cache
  cleanup also removes disk response caches.
- Configuration, history, and cache files use recoverable atomic writes to reduce
  corruption risk after unexpected process termination.
- Startup compares all API/image routes in parallel, selects the fastest within
  an 800 ms window, and prefetches home feeds concurrently.
- Backend initialization runs off the main thread and cache cleanup is asynchronous.
  Route probes use real backend deadlines and only read response headers.
- Rust v2 backend source and the Flutter app are maintained in this repository.

## Installation

1. Download the ARM64 APK from the
   [latest release](https://github.com/khxw/JMcomic3-flutter/releases/latest).
2. Download and verify `SHA256SUMS.txt`.
3. Allow installation from the file manager if required.
4. Back up bookshelf, history, and download settings before upgrading.

PowerShell verification:

```powershell
Get-FileHash .\JMComic3-Mod-v1.8.180-arm64-v8a-release.apk -Algorithm SHA256
```

Current APK SHA-256:

```text
E360676FB1BCA4BD51EF2077F9477381807E9E944D35F4F202566BA14EADC236
```

## Build

See [docs/BUILDING.md](docs/BUILDING.md) and
[docs/RELEASING.md](docs/RELEASING.md).

- Flutter is pinned by [.fvmrc](.fvmrc).
- JDK 17 or newer is required.
- Android SDK 36 and NDK `25.2.9519653` are used by the current release setup.
- Rust v2 backend source is included under `rust-backend/rust`, and the verified
  prebuilt JNI libraries are committed under `android/app/src/main/jniLibs`.

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

- Cover cache pruning is automatic; the current UI does not expose a separate
  cover-cache size or manual cover-only cleanup control.

## References

- [ComicSparks/jasmine](https://github.com/ComicSparks/jasmine): reader structure,
  continuous reading, gallery zoom, and progress interaction reference.
- [hect0x7/JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python):
  mobile API protocol, request signing, login, and domain fallback reference.
- `zoomable_positioned_list` 1.1.0: vendored continuous-reader component.

See [REFERENCES.md](REFERENCES.md) for the complete reference scope and retained
notices. Upstream names, code, and content remain the property of their authors.

## Usage policy

By using this project, you agree to the following rules:

- **Lawful use:** Use this project only for purposes permitted by applicable
  laws. Do not access, download, store, or distribute unlawful material.
- **Content rights:** This repository provides application modifications and
  build instructions only. It does not provide, host, or license comics,
  images, comments, or other content. Content rights remain with their
  respective authors, platforms, or rights holders; obtain any required
  authorization before downloading or using content.
- **No unauthorized commercial use:** In line with the inherited project
  policy, do not use this project or content assets for unauthorized
  commercial distribution, sale, rental, paid downloading, or bundled
  redistribution.
- **Software distribution:** Prefer APKs from this repository's Releases page
  and verify their SHA-256 checksums. Before modifying, building, or
  redistributing program code, confirm upstream copyright terms and all
  third-party component licenses. The absence of a root license file does not
  grant additional rights to the project.
- **No warranty and responsibility:** The software is provided as is, without
  any guarantee that third-party services will remain available, content will
  be accurate, or the application will work on every device. Users are
  responsible for the risks and consequences of their use, downloads, and
  distribution, and must comply with the relevant service terms.
