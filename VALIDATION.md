# Validation report

Last updated 2026-11-27 for Subvelle 1.2.0.

## Automated checks on every build

| Check | iPhone build | Android build |
|---|---|---|
| Core logic (schedules, month-end clamping, leap years, currency conversion, totals, validation, list filtering and sorting, backup rules) | 20 Swift tests, macOS and Linux | 15 JVM unit tests |
| Storage and backups (save, edit, archive, delete, reopen from disk, validated atomic import, automatic folder backup with pruning and restore) | 5 tests on the simulator | Covered by unit and UI tests |
| UI flows (add a subscription, persistence across launches, empty states, safe areas, landscape, large text, light mode, reduced motion, charts) | 5 UI tests on an iOS 26 simulator | 2 UI tests on an Android 14 emulator |
| Large data set | — | 2 more emulator tests with 300 subscriptions: every tab renders and scrolls to the end, and frame statistics are recorded during real swipe scrolling |
| Static analysis | Swift 6 strict concurrency | Android Lint with errors failing the build: no issues |
| Release package | Unsigned ARM64 IPA: version, ID, platform and architecture verified before publishing | R8-optimized APK (about 1.8 MB) with startup profiles; signature verified with `apksigner` |

## Cross-version backup compatibility

- A backup produced by the iPhone app's own `SubspaceCore` code is a fixture in the Android unit tests. Android reads every field exactly, including local times, decimals, optional fields, categories with special characters, and "reminder off".
- A backup written by the Android app was decoded and validated by `SubspaceCore`, with all fields matching.
- This check found and fixed a real bug before release: a missing reminder field would have been read as "3 days" instead of "off".

## Releases

- [Subvelle 1.2.0](../../releases/tag/v1.2.0): folder home screen on both phones (a folder pops out over the blurred home screen), 192 services with brand logos or brand-coloured monograms, opening a backup from Files or another app, and Apple's document picker for importing on iPhone. Before publishing: [iPhone build](../../actions/runs/45970492126) passed all 6 storage and import tests and all 6 simulator UI tests, including opening and closing every folder with ✕ and an outside tap; [Android release build](../../actions/runs/45973823765) passed 16 unit tests, lint, and 6 emulator UI tests, including folders (✕, Back, outside tap) and opening a backup from another app. Files: `Subvelle-1.2.0-24.ipa` and `Subvelle-1.2.0-16.apk`, each with a SHA-256 checksum.
- Subvelle 1.1.3 and 1.1.2: importing on iPhone (a single file picker), and Share / Open with Subvelle on both phones.
- [Subvelle 1.1.1](../../releases/tag/v1.1.1): first release for both phones. The app is renamed Subvelle, and the Android app (signed APK) ships alongside the iPhone IPA. Both builds passed every test before publishing: [iPhone build](../../actions/runs/45905834026) (core, storage and simulator UI tests) and [Android build](../../actions/runs/45905992066) (unit tests, lint, 4 emulator UI tests, and APK signature verified). Files: `Subvelle-1.1.1-20.ipa` and `Subvelle-1.1.1-11.apk`, each with a SHA-256 checksum.
- [Subvelle 1.1.0](../../releases/tag/v1.1.0): automatic backup to a chosen folder; export file names use the local date.
- [Subvelle 1.0.1](../../releases/tag/v1.0.1): same-day end dates accepted; no alert when opening offline; correct "rates updated" date in the Americas.
- [Subvelle 1.0.0](../../releases/tag/v1.0.0): first release.

## Verified on a real phone

- iPhone, Subvelle 1.2.0 installed with SideStore: **Settings → Import backup** with a backup file in iCloud Drive imports correctly (confirmed by the owner, 2026-11-27).

## Not yet verified on real phones

Automated tests and simulators do not replace testing on devices. Still to check by hand:

- Installing and updating: SideStore signing on iPhone; installing over a previous version on Android.
- Notification delivery under different permission, Focus, battery-saver and Doze settings.
- Automatic backup to cloud-drive folders with each provider. Folder access is granted through the system picker; behavior depends on the provider app.
- Visual review, screen readers (VoiceOver and TalkBack), and the largest text sizes on real screens.
- Smoothness on real hardware. CI measures frame timing on an emulator without a GPU, which understates real-device performance.
