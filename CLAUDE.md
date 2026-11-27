# Subvelle: project instructions

Subvelle is one subscription-tracker app with two native versions: iPhone (`Subspace/`, SwiftUI) and
Android (`android/`, Kotlin + Compose). Code folders and modules keep the old internal name
`Subspace`; the app name users see is **Subvelle** everywhere.

## Releases (rules from the owner)

- **Version numbers:** `MAJOR.MINOR.PATCH`, where the patch number only goes 0-9. After `x.y.9` comes
  `x.(y+1).0`: 1.3.0 → 1.3.1 → … → 1.3.9 → 1.4.0. Get the next number with
  `python3 Tools/next_version.py` (reads the latest tag) or `python3 Tools/next_version.py 1.3.9`.
- **Every release has both apps** with the same version: the iPhone IPA and the signed Android APK.
- **Publish only when both builds pass.** If a build fails, fix it and run it again; publish nothing
  from a failed run.
- **Never cancel a running CI run** (yours or anyone's). Start a new run instead if needed.
- Order that works: build both from the branch (`build.yml` with `version`, `android.yml` with
  `version`), then when both pass, update `main`, run `android.yml` on `main` with `version` and
  `release_tag=vX.Y.Z` (creates the release and attaches the APK), then `publish.yml` with the
  passing iPhone `run_id` and the same tag (adds the IPA and final notes).
- After publishing, add the release and its test results to `VALIDATION.md`.
- Publishing the iPhone build also commits the new version to `altstore/source.json` on `main`
  (the Feather/AltStore source), as `github-actions[bot]`. So **pull `main` into your branch before
  pushing to `main`**. `python3 Tools/update_altstore_source.py bootstrap` rebuilds the source from
  the GitHub releases if it ever gets out of sync.

## Generated files (regenerate, don't hand-edit)

- Services, brand colours and logos for both apps: `Tools/GenerateBrandCatalog.py` (see README).
- App icons and the in-app mark: `Tools/GenerateAppIcon.py` (`pip install cairosvg`).

## Compatibility

- Backup JSON must stay identical between the two apps (Apple reference-date seconds, exact decimal
  numbers, uppercase UUIDs, omitted nils). The Android tests read a backup made by the iPhone code.
- App IDs `app.subspace.ios` and `app.subspace.android` never change: installed apps must keep updating.
- Android release signing comes only from the four `ANDROID_*` repository secrets; never commit keys.
