# Repository Guidelines

## Project Structure & Modules
- Sources: Swift sources (SwiftUI app and modules like `DMGOperations`, `DMGIconOperations`, `MountManager`, `ProcessRunner`).
- Package.swift: SwiftPM manifest (executable target `dmgTweakApp`).
- dmgTweak.app/: Local app bundle used during development.
- dist/: Output app bundle produced by `build.sh`.
- .build/: SwiftPM build artifacts; do not commit.
- packaging/: Packaging assets (if used).

## Build, Test, and Development
- Build (debug): `swift build`
- Build (release): `swift build -c release`
- Dev build: `./dev-build.sh` (updates only `dist/dmgTweak.app`; syncs localized resources; touches timestamp).
- Full build: `./build.sh` (deps check, format/lint, compile, update `dist/dmgTweak.app`; optional release packaging via `RELEASE_TAG`).
- Run app: `open dist/dmgTweak.app`
- Binary in bundle: `Contents/MacOS/dmgTweak` (unified name).

## Coding Style & Naming
- Swift 5.9+, 4‑space indentation, 120‑col soft wrap.
- Types: PascalCase (`DMGOperations`), methods/properties: lowerCamelCase, constants: upperCamelCase with `static let` where appropriate.
- One primary type per file; file names match the main type.
- Apply `MainActor` for UI/observable state. Prefer structs and value semantics for models.
- Tools: SwiftFormat and SwiftLint (run via `build.sh`). Keep lint clean before PRs.

## Testing Guidelines
- Current repo has no `Tests/` target. If adding tests:
  - Location: `Tests/dmgTweakAppTests/` with `XCTest`.
  - Names: `XYZTests.swift`; methods `testFunction_condition_expected()`.
  - Focus: `DMGOperations`, `ProcessRunner`, mounting logic. Use temp dirs; avoid mutating real files.
  - Run: `swift test` (add CI later as needed).

## Commit & Pull Request Guidelines
- Commits: Imperative, scoped prefixes observed in history: “Add …”, “Fix …”, “Remove …”. Keep to one logical change.
- PRs include: concise description, before/after notes or screenshots for UI, steps to validate, linked issue, and any docs updates (README/this file).
- Checks: `./build.sh --no-deps` passes; lint/format applied; no large binaries added.

## Security & Configuration Tips
- Do not commit signing identities or secrets; `build.sh` uses ad‑hoc signing (`codesign -s -`).
- `ProcessRunner` executes shell commands—validate inputs and sanitize paths.
- Avoid committing generated bundles (`.build/`, `dist/`, `dmgTweak.app/`).

## Localization
- Languages: English (default), Deutsch.
- Resources: `Sources/Resources/en.lproj/`, `Sources/Resources/de.lproj/`.
- SwiftPM: `defaultLocalization = "en"`; strings loaded via `Bundle.module`.
- Override per user:
  - English: `defaults write de.free.dmgTweak AppleLanguages -array en`
  - German: `defaults write de.free.dmgTweak AppleLanguages -array de`
  - Reset: `defaults delete de.free.dmgTweak AppleLanguages`

## Release Packaging
- No prebuilt binaries or zips.
- Consumers clone the repository and build locally (`./dev-build.sh` or `swift build`).

## Cutting A New Release
- Update docs: add changes to `README.md`/`README.de.md` and `Changelog` section.
- Create tag: `git tag -a vX.Y.Z -m "vX.Y.Z" && git push origin vX.Y.Z`.
- Verification: ensure main builds cleanly; users will clone and build from source.
