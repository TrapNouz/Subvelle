# Validation report

Verified on 2026-11-14.

## Successful GitHub builds and release

- [Pull-request build 43567761519](https://github.com/TrapNouz/Subvelle-Ios/actions/runs/43567761519): **success**.
- [Merged-main build 43567908281](https://github.com/TrapNouz/Subvelle-Ios/actions/runs/43567908281): **success**.
- [Release publishing job 43568662620](https://github.com/TrapNouz/Subvelle-Ios/actions/runs/43568662620): **success**.
- [Subspace 1.0.0 release](https://github.com/TrapNouz/Subvelle-Ios/releases/tag/v1.0.0).

GitHub’s macOS 26 runner used Xcode 26.6 with the iOS 26.5 SDK. XcodeGen generated the project successfully. The Financial domain suite passed **12 tests**. The app and test host compiled for an ARM64 iPhone simulator, then **all four SwiftData tests passed**, including database reopening from disk, transactional backup validation/import, decimal persistence, and CRUD/archive/restore behavior. The Release configuration then built successfully for `generic/platform=iOS` with signing disabled. The app was packaged with the standard Payload structure and uploaded as an IPA artifact.

The released file is `Subspace-1.0.0-3.ipa`, marketing version `1.0.0`, build `3`, minimum iOS `26.0`, bundle identifier `app.subspace.ios`, platform `iPhoneOS`. It came from run 43567761519, source revision `9aae990ba5b1190831286090921d44454213f0d7`. Its Git tree (`e26f7677b42f6f0dd5e97d7879f83da9f474aad1`) exactly matches the merged-main revision `7202ddc435e98ab96008ccb954e52fc44f03d802`.

The IPA was downloaded and independently checked for ZIP integrity, `Payload/Subspace.app/Info.plist`, bundle identifier, version, minimum OS, iPhoneOS platform, and an ARM64 Mach-O executable. The GitHub publishing job repeated these checks and attached the IPA plus its checksum to the release.

SHA-256:

```text
ad9cff4a9df19def945b0db5950b0afafc0aa2f1b35d18fc2f4d54630446f1a9  Subspace-1.0.0-3.ipa
```

## Additional authoring checks

The original Linux authoring environment had no Xcode. Apple's temporary Swift 6.2.1 Ubuntu toolchain compiled SubspaceCore and ran all 12 financial-domain tests successfully. The Swift frontend and an independent Tree-sitter parser accepted all Swift source. YAML, asset JSON, and the original 1024×1024 RGB app icon were checked.

The first Xcode run exposed a collision between the app's `Category` type and SwiftUI's type of the same name. Explicit `SubspaceCore.Category` qualification resolved it. A subsequent run compiled the app but was canceled when a skills-only merge started a new main run; both the PR and merged-main runs then succeeded. Local release-asset upload was denied by the connection, so a GitHub-hosted publishing workflow completed that upload successfully using its built-in token. No signing secrets were needed.

## Not manually verified

- Physical-device/SideStore installation and signing.
- Visual layout, VoiceOver, large Dynamic Type, and all interactive flows on a device.
- Real notification delivery under different Focus/permission settings.
- The future tag-triggered release path end-to-end; the supplied automatic workflow is configured, and this initial release was published using the successful verified-artifact publishing workflow.

Passing tests and a successful iOS build do not substitute for physical-device visual and notification testing. The IPA is unsigned and must be signed by SideStore before installation.
