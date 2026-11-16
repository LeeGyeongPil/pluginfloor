# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-16

### Added

- `pluginfloor check [app_dir]`: reads `.dart_tool/package_config.json` (relative, absolute and percent-encoded `rootUri`), selects packages that declare `flutter: plugin:` (federated implementation packages included) and ignores the app itself and plugin `example/` folders.
- Android floors from Groovy and Kotlin DSL `minSdk` / `minSdkVersion` / `compileSdk` / `compileSdkVersion` (space, `=` and call forms) and `AndroidManifest.xml` `uses-sdk`, with exact 1-based line numbers; one `apply from:` hop of `ext` values; `flutter.*` and `rootProject.*` reported as unknown.
- iOS and macOS floors from podspecs (`deployment_target`, `platform`) and `Package.swift` (`.iOS("13.0")`, `.iOS(.v13)`, `.iOS(.v15_5)`, `.macOS(.v10_15)`), duplicates merged, `darwin/` values assigned to both platforms.
- App values from `android/app/build.gradle(.kts)`, `android/local.properties`, `ios|macos/Podfile` and `Runner.xcodeproj/project.pbxproj` (lowest deployment target).
- Rules PF001-PF004 (floor violations), PF010 (value cannot be resolved), PF011 (CocoaPods vs SwiftPM floors differ), PF012 (app value not found).
- `--assume KEY=VALUE`, `--darwin-path cocoapods|spm|both`, `--all`, `--strict`, `--package-config`, `--output`.
- Table, JSON (`schemaVersion` 1) and SARIF 2.1.0 reports, deterministic and with app-relative paths only.
- Exit codes 0 (no errors), 1 (violations, or warnings with `--strict`), 2 (usage or input error).
- English and Korean output: `--lang en|ko`, `PLUGINFLOOR_LANG`, then `LC_ALL` / `LC_MESSAGES` / `LANG`.
- Bundled fake sample app in `example/sample_app`.
- Korean table columns are padded by display width; Korean help text includes defaults; singular title for one plugin; Apple `Package.swift` violations also point at the Runner `project.pbxproj`.

[0.1.0]: https://github.com/LeeGyeongPil/pluginfloor/releases/tag/v0.1.0
