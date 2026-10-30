# Template Maintenance

Template version: 2026-10-30

This app started from **swiftui-starter**. The files below are owned by the
template; app-specific code and configuration belong to this repository. When
the starter gains a fix or a new capability, compare the two checkouts instead
of rediscovering the change in this app.

## Check for upstream changes

```sh
make template-diff SOURCE=/path/to/swiftui-starter
```

The script is read-only. It prints a unified diff (upstream → local) for:

- `Makefile`
- `Scripts/App.entitlements`
- `Scripts/check-l10n.py`
- `Scripts/make-app.sh`
- `Scripts/make-icon.swift`
- `Scripts/rename.sh`
- `docs/ui-testing.md`
- `Sources/*/Log.swift`
- `Sources/*/Resources/PrivacyInfo.xcprivacy`

`AGENTS.md` and `Package.swift` are intentionally not diffed: both carry
app-specific sections, so merge the relevant bullets by hand. `README.md` and
`README.ZH.md` describe this app and are not template files.

## Merge rules

- Port the upstream change, not the whole file, when this app has customized
  the file (extra Makefile targets such as `mas`, additional entitlements,
  app-specific usage descriptions, or extra UI-testing sections).
- Keep this app's identity: display name, bundle ID, version, build number,
  entitlements and privacy-manifest reason codes are app-specific.
- After merging, update the date on the `Template version` line above only if
  the app has caught up with that starter revision.
- If the change belongs in every app (a build-script fix, a macOS gotcha, a
  localization rule), send it upstream to swiftui-starter first, then sync it
  back here.

## Changelog

- 2026-10-30 — distribution pipeline: build number, `DEV=1` / `MAS=1` modes,
  universal builds, hardened runtime, App Sandbox entitlements, privacy
  manifest, App Store `.pkg`; `Scripts/template-diff.sh` and this file.
- 2026-10-30 — diagnostics: `Log` writes unified logging plus a rotating file
  log, and `Log.bootstrap()` records the bundle, sandbox and log paths;
  `template-diff.sh` now matches files under a renamed library target.
- 2026-10-30 — localization: `LocalizationTests` checks key parity, empty
  values and every enum label key in `swift test`.
- 2026-10-30 — previews: `PreviewFixtures` builds a sample folder under the
  temporary directory so `#Preview` never depends on a developer's home path.
