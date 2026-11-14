# Validation report

Performed in the Linux authoring workspace on 2026-11-14.

## Passed

- Downloaded Apple's Swift 6.2.1 Ubuntu toolchain to `/tmp` (not a project dependency).
- Compiled the `SubspaceCore` package and executed its complete XCTest suite: **12 tests, 0 failures**.
- Parsed all app and SwiftData test Swift source using `swiftc -frontend -parse`: no syntax errors. This does **not** resolve Apple frameworks, expand SwiftData macros, or type-check SwiftUI.
- Independently parsed all Swift files using the Tree-sitter Swift grammar: no syntax errors.
- Parsed `project.yml` and `.github/workflows/build.yml` as YAML.
- Validated asset catalog JSON and the bundled original 1024×1024 RGB app icon.
- Reviewed the workflow: test jobs precede unsigned build/IPA packaging; release job depends on successful build; release permissions are limited to tagged releases.

The package test command in this restricted environment was:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/subspace-clang-cache \
SWIFT_MODULECACHE_PATH=/tmp/subspace-module-cache \
XDG_CACHE_HOME=/tmp/subspace-xdg \
/tmp/subspace-swift/usr/bin/swift test \
  --scratch-path /tmp/subspace-build \
  --cache-path /tmp/subspace-swift-cache
```

## Not run / not claimed

- XcodeGen generation on macOS.
- SwiftUI/Charts/SwiftData/UserNotifications framework compilation and type checking.
- The four iOS persistence tests (including database reopening from disk).
- Simulator/device rendering, VoiceOver, Dynamic Type, real notification delivery, or interaction testing.
- GitHub Actions execution, IPA creation, release publication, or SideStore installation.

There is no Xcode or iOS SDK on this machine and the workspace has no usable Git remote. The supplied GitHub workflow is the reproducible path for these build and iOS test checks. A passing Linux domain suite is not an iOS build certification.
