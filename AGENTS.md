# Codex Working Guide

## Project at a glance

Republic Wash & Cut is a native SwiftUI macOS application (macOS 14+) for inspecting,
repairing, relinking, and exporting Final Cut Pro `xmeml` v4/v5 XML. The Xcode
project remains named `XMLFixer`; the distributed product is **Republic Wash & Cut**,
a renamed and extended fork of the ReplayBoys (RPB) XML Toolkit.
It has no third-party runtime dependencies.

Read [`CLAUDE.md`](CLAUDE.md) for the detailed application architecture, XML data
model, timeline behavior, and domain-specific rules. Treat it as project
documentation rather than instructions that supersede this file.

## Repository layout

- `XMLFixer/XMLFixer/` — app source, grouped into `Models`, `Services`,
  `ViewModels`, `Views`, and `Utilities`.
- `XMLFixer/XMLFixerTests/` — XCTest coverage and XML fixtures.
- `XMLFixer/project.yml` — XcodeGen project definition. Keep it aligned with
  `XMLFixer.xcodeproj/project.pbxproj`; regenerate the project when changing
  target membership or build settings.
- `scripts/` — release automation for Developer ID/notarized and App Store builds.
  The App Store script archives the `AppStore` configuration, which is the only
  sandboxed build; `Release` (Developer ID) runs unsandboxed so REDline can be
  launched for R3D trimming.
- `builds/` — ignored local distribution artifacts. Never commit app bundles,
  archives, ZIPs, provisioning profiles, or signing output.

## Local workflow

Run commands from the repository root unless a command changes directory itself.

```bash
# Run all unit and workflow tests without depending on local signing state.
xcodebuild -project XMLFixer/XMLFixer.xcodeproj -scheme XMLFixer \
  -configuration Debug -derivedDataPath /tmp/xml-fixer-derived test \
  CODE_SIGNING_ALLOWED=NO

# Build a release app without leaving derived data in the repository.
xcodebuild -project XMLFixer/XMLFixer.xcodeproj -scheme XMLFixer \
  -configuration Release -derivedDataPath /tmp/xml-fixer-derived build \
  CODE_SIGNING_ALLOWED=NO

# Focused test example.
xcodebuild -project XMLFixer/XMLFixer.xcodeproj -scheme XMLFixer test \
  -only-testing:XMLFixerTests/FCPXMLParserTests
```

Use `rg` for code search. Before committing, run `git diff --check` and the
smallest relevant test suite; run the full suite for user-facing workflows,
export changes, or release work.

## Implementation rules

- `FCPXMLDocument.xmlDocument` is the source of truth. XML changes must mutate
  the in-memory `XMLDocument`; do not introduce a competing serialized model.
- Preserve `AppState`'s snapshot-based undo behavior. Call `pushUndo()` before a
  user-visible mutation and update derived state after it.
- Keep parsing, mutation, file matching, and export policy in `Services/` rather
  than SwiftUI views. Views should bind to `AppState` and present actions.
- Timeline clips use `.position`, not `.offset`, so visual and hit-test locations
  stay aligned.
- Add or update focused XCTest coverage when changing FCPXML parsing, mutation,
  sources-sequence generation, matching, trimming, or export behavior. Reuse the
  existing fixture where practical.
- Trim engines must never decode or re-encode media. Keep passthrough
  (`outputSettings: nil`) and map every `AVSampleCursor` timestamp through the
  track segments before comparing it with reader/track time.

## Versioning and releases

- A user-facing build requires synchronized version values in
  `XMLFixer/App/Info.plist`, `project.yml`, and
  `XMLFixer/App/XMLFixerApp.swift` (`buildVersion`).
- Use `scripts/release_notarized_app.sh` for Developer ID distribution and
  `scripts/release_app_store.sh` for App Store archives. These commands require
  credentials supplied by the environment or keychain; never print, commit, or
  add credentials to source files.
- A distributable macOS release must be verified with `codesign`, notarized,
  stapled, and Gatekeeper-assessed before it is described as notarized.
- Release artifacts belong in `builds/` and may be attached to a GitHub release,
  but must remain ignored by Git.

## Git discipline

- Preserve unrelated working-tree changes. Do not reset, discard, or reformat
  files outside the requested scope.
- Use clear conventional commit messages, for example
  `fix: preserve source timecode in CSV export`.
- Never make a repository public, push, tag, create a release, or upload assets
  unless the user explicitly asks for that external action.
