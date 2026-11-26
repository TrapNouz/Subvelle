# Validation report

Last updated 2026-11-26 for Subspace 1.1.0.

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

- [Subspace 1.1.0](../../releases/tag/v1.1.0): automatic backup to a chosen folder; export file names use the local date.
- [Subspace 1.0.1](../../releases/tag/v1.0.1): same-day end dates accepted; no alert when opening offline; correct "rates updated" date in the Americas.
- [Subspace 1.0.0](../../releases/tag/v1.0.0): first release.

## Not yet verified on real phones

Automated tests and simulators do not replace testing on devices. Still to check by hand:

- Installing and updating: SideStore signing on iPhone; installing over a previous version on Android.
- Notification delivery under different permission, Focus, battery-saver and Doze settings.
- Automatic backup to cloud-drive folders with each provider. Folder access is granted through the system picker; behavior depends on the provider app.
- Visual review, screen readers (VoiceOver and TalkBack), and the largest text sizes on real screens.
- Smoothness on real hardware. CI measures frame timing on an emulator without a GPU, which understates real-device performance.
