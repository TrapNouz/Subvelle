# Subspace

A native, local-first iPhone subscription manager for **iOS 26+**, using SwiftUI, native Liquid Glass, Swift Charts, SwiftData, and UserNotifications. No account, ads, tracking SDKs, bank access, paid APIs, or signing secrets.

## What’s included

- Four native glass tabs: Overview, Subscriptions, Analytics, Settings. Glass add action, native sheets, accessible labels, Dynamic Type, dark/system appearance, spring/number transitions, and system-aware motion.
- Dashboard with normalized monthly/annual/weekly costs, active count, next-payment countdown, upcoming renewals, and largest annual commitments.
- Interactive monthly/daily and annual/monthly payment charts, year navigation, current normalized average comparison, category donut selection, per-service cost chart, and converted spending grouped by original billing currency.
- Full-screen month/year payment calendar, daily payment totals, and subscription detail sheets.
- Add/edit, search/filter, pause/cancel, archive/restore, and confirmed deletion. Weekly, biweekly, monthly, quarterly, semiannual, annual, and custom day/week/month/year intervals. Trial, notes, end date, reminder, currency, category, and SF Symbol icon selection.
- 147 service presets across 13 categories, with original monograms and SF Symbols. No downloaded logos or assumed prices.
- Decimal financial logic; CAD reporting default; ISO billing currencies; offline FX cache from Frankfurter’s central-bank reference rates; source-date display and explicit partial totals when rates are unavailable.
- Local versioned SwiftData storage, transactional JSON merge/import, JSON export, and renewal notifications at 9 AM local time (1/3/7/14 days ahead).
- Unit tests for recurrence, financial summaries, Decimal conversion, input validation, backup validation, and SwiftData CRUD/round trips.
- macOS GitHub Actions tests, unsigned device build, standard Payload IPA packaging, downloadable artifacts, and automatic tagged releases.

## Download and verified build status

**[Download Subspace 1.0.0 from Releases](https://github.com/TrapNouz/Subvelle-Ios/releases/tag/v1.0.0)**. Choose `Subspace-1.0.0-3.ipa` and import it into SideStore on an iOS 26+ iPhone. A SHA-256 checksum is attached. This is a private repository: sign in with your authorized GitHub account to download it.

The iOS app was compiled and tested successfully on GitHub’s macOS runner under Xcode 26.6. All **12 financial tests and four SwiftData tests passed**, followed by a successful unsigned ARM64 iPhone Release build. Both the [pull-request build](https://github.com/TrapNouz/Subvelle-Ios/actions/runs/43567761519) and [merged-main build](https://github.com/TrapNouz/Subvelle-Ios/actions/runs/43567908281) passed. The [publishing job](https://github.com/TrapNouz/Subvelle-Ios/actions/runs/43568662620) verified the IPA and attached it to the release.

The released IPA comes from successful run `43567761519`, source revision `9aae990ba5b1190831286090921d44454213f0d7`. That revision and merged-main revision `7202ddc435e98ab96008ccb954e52fc44f03d802` have the exact same Git tree. GitHub Actions handled the asset upload using its built-in token; no personal signing secrets were added. See `VALIDATION.md` for the full report. Physical-device installation, visual review, and real notification delivery have not been manually verified.

## Build on GitHub from Windows

1. Create a GitHub repository and commit this directory, including `.github/workflows/build.yml`, `Package.swift`, `Tests`, `Subspace`, and `project.yml`. The generated Xcode project is intentionally not checked in: CI generates it with XcodeGen.
2. Open **Actions → Test and build SideStore IPA → Run workflow**. Pushes to `main`/`master` and pull requests also run it.
3. The hosted **macos-26** runner selects current stable Xcode and verifies an iOS 26+ SDK. It runs `swift test`, compiles the whole iOS app, and runs SwiftData tests on an available iOS 26 iPhone simulator. It then builds for `generic/platform=iOS` with signing disabled.
4. When the run succeeds, open its **Artifacts** section and download `Subspace-<version>-unsigned-IPA`. Extract the artifact ZIP to obtain `Subspace-<version>-<run number>.ipa`.
5. For a release, push a semantic version tag, for example:

   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```

   On a successful run, **Releases → Subspace v1.0.0** contains the IPA directly. The tag sets the app’s marketing version; the Actions run number sets its build version. Tags must use `vMAJOR.MINOR.PATCH`.

6. Open/import the IPA with **SideStore** on an iOS 26+ iPhone. SideStore handles signing and sideloading using its own setup and account requirements. The IPA is deliberately unsigned; iOS cannot install it unsigned. This repository does not require an Apple ID, signing certificates, an Apple Developer membership, or App Store Connect secrets. GitHub’s built-in token grants release permission only to the release job.

GitHub-hosted runner availability, repository Actions quotas, and runner image changes are controlled by GitHub. If a future runner lacks an iOS 26 simulator, install a matching runtime or adjust the simulator-selection step for a newer compatible runtime. Use the test-result artifact to diagnose CI failures. Failed tests prevent IPA publication.

## Publish an existing verified build

The additional **Actions → Publish verified SideStore IPA** workflow publishes an already-tested artifact without rebuilding. Enter a successful `build.yml` run ID and a tag matching the IPA's marketing version (for example `v1.0.0`). It validates the source run, version, bundle identifier, device platform, ARM64 executable, and ZIP integrity, then uploads the IPA and its SHA-256 checksum using GitHub’s built-in token. Future version-tag pushes still use the automatic build-and-release workflow described above.

## Local development on a Mac

Install Xcode 26+ and XcodeGen, then:

```sh
brew install xcodegen
xcodegen generate
open Subspace.xcodeproj
swift test
```

Select the Subspace scheme and an iOS 26 iPhone simulator. To run the persistence tests, use **Product → Test**. The Swift package is platform-independent Foundation logic and also runs on Linux with Swift 6.0+.

The bundle identifier is **`app.subspace.ios`**. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`, then regenerate the project. The test target uses `app.subspace.tests`. Changing an installed app’s bundle ID creates a separate sandbox, so export a backup first. There are no unsupported entitlements, app groups, iCloud containers, background push capabilities, or keychain groups.

## Architecture and financial rules

`Subspace/Core` is the independent `SubspaceCore` package: Codable domain types, recurrence, FX, summaries, presets, and money parsing/formatting. The app links it as a local package. `Services/AppStore.swift` is a main-actor observable state owner: it coordinates persistence, transactional mutations, exchange rates, backup operations, and serial notification refreshes. Views read this shared state, so saves update all screens immediately. `Models/Persistence.swift` defines the SwiftData versioned schema and migration plan.

`annual = amount × periodsPerYear`, `monthly = annual / 12`, and `weekly = annual × 7 / 365.2425`. Fixed day/week plans use the Gregorian mean year of 365.2425 days; calendar month/year plans use 12 months per year. Values remain Decimal until chart rendering, which requires Double. Totals use full precision and round only for localized display. Each original amount is converted independently through a common FX base **before** summation. Unsupported currencies are excluded and flagged, never silently treated as the reporting currency.

An annual $120 plan contributes $10 to normalized monthly cost but one $120 scheduled charge in its renewal month. Normalized figures express the current active commitment, not a calendar cash-flow total or prorated remaining-year bill. Paused/canceled/archived/expired records are excluded from current averages and future reminders. The active count includes subscriptions with missing FX; converted totals do not.

Recurrence is anchored to the supplied renewal date. Month and year occurrences are calculated from that anchor with day clamping, rather than adding repeatedly to February’s shortened date. January 31 → February 28/29 → March 31; February 29 annual plans recover February 29 in leap years. A February 28 anchor itself remains a day-28 plan; users should choose an original day-31 anchor for day-31 schedules. Date intervals are half-open; the optional end date includes that day’s charge. Trial end bounds the first eligible payment, and the editor requires the paid renewal anchor to fall on/after it. Schedules use the user’s current calendar and time zone, with local date-only occurrences; reminders use local 9 AM, respecting DST.

There is **no bank transaction ledger**: past bars are reconstructed scheduled estimates, clearly labeled. Changing amount, anchor, currency, or status recalculates the schedule; canceled and archived records do not contribute reconstructed charts. Historical conversion uses the cached reference rate, not historical daily FX. Irregular schedules are supported as custom fixed intervals; arbitrary varying charge amounts or manual exceptions are not modeled.

## Privacy, backups, and resilience

The only network request is an HTTPS request for public exchange rates; subscription records are never included. Frankfurter does not cover every ISO currency. Rates older than four days are labeled stale; missing rates produce partial-total warnings. Same-currency calculations always work offline. A failed refresh preserves the previous cache.

SwiftData stores a unique ID and versioned Codable payload for each record. Schema V1 and an explicit migration plan provide a stable starting point. Future incompatible schema changes must introduce a new `VersionedSchema` and migration stage; incompatible payload changes must introduce a payload migration/default decoding policy. The app never deletes/recreates a failed database. A launch failure presents a storage error, and corrupted record loading is reported while preserving stored bytes.

Exports are readable JSON with `schemaVersion`, `exportedAt`, and all records (including archived records). Imports validate the complete backup before modifying anything, merge by UUID in one transaction, and roll back on save failure. Unsupported versions, duplicate IDs, invalid records, >10,000 records, and files larger than 20 MB are rejected. There is a confirmation before merging. JSON uses Foundation’s standard numeric Date encoding and exact Decimal values. Keep exports private. Device/iCloud backups follow the user’s OS backup settings; Subspace itself does not sync.

Notifications are local and permission-based. iOS limits pending notifications; Subspace schedules the earliest 60 eligible reminders in a rolling two-year window and replenishes them on foreground and edits. Reminders due earlier than the current time are not backfilled. Opening the app periodically is necessary for continued coverage; delivery is subject to Focus, permission, and OS scheduling. Rescheduling is serialized to prevent overlapping edits from restoring obsolete reminders. No background execution or remote notification delivery is promised.

## Design and accessibility

Native `TabView` provides the iOS 26 glass tab bar and navigation surfaces. `GlassEffectContainer`, `.glassEffect`, `.buttonStyle(.glass)`, and `.glassProminent` are used for floating and contextual controls. Large reading/financial surfaces use quiet opaque/tinted cards for legibility. The app uses semantic font styles, screen-reader labels, localized currency, Reduce Motion-aware explicit animations, and native system handling of Reduce Transparency. An original orbital app icon is bundled. Verify appearance, contrast, chart interaction, large Dynamic Type, VoiceOver, and notification behavior on real devices before distribution.
