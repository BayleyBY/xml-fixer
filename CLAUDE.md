# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**XML Fixer** is a SwiftUI macOS app (14.0+) for batch-processing Final Cut Pro (FCP) XML files. It provides a GUI for loading hundreds of XMLs, inspecting/editing media references and timelines, relinking paths, repairing reel metadata, and exporting modified XMLs. It also includes a synced reference video player and timeline visualization. Zero external dependencies — uses Foundation, SwiftUI, AVFoundation, and AppKit only.

The original `clean_xmls.py` CLI script is still in the repo root but is unrelated to the Swift app.

## Build & Test

```bash
# Build (Release)
cd XMLFixer
xcodebuild -scheme XMLFixer -configuration Release -derivedDataPath ./build build

# Build (Debug, faster iteration)
xcodebuild -scheme XMLFixer build

# Run all tests
xcodebuild -scheme XMLFixer test

# Run a single test class
xcodebuild -scheme XMLFixer test -only-testing:XMLFixerTests/FCPXMLParserTests

# Run a single test method
xcodebuild -scheme XMLFixer test -only-testing:XMLFixerTests/FCPXMLParserTests/testParseSequences
```

The built app lands at `build/Build/Products/Release/XML Fixer.app`. Versioned builds are saved to `builds/` in the repo root (e.g., `XML Fixer V003.app`). The build version string lives in `XMLFixerApp.buildVersion` and should be bumped for each user-facing build.

Test fixtures live in `XMLFixerTests/Fixtures/sample_sequence.xml`.

## Architecture

### Data Flow

```
Import XML files → FCPXMLParser.parse() → FCPXMLDocument (holds live XMLDocument)
                                              ↓
                                   AppState.documents[]
                                              ↓
                           FCPXMLParser.extractMediaReferences() → AppState.mediaReferences[]
                                              ↓
                           TimelineExtractor.extractTimeline() → AppState.currentTimelineData
                                              ↓
                                   (User edits via UI)
                                              ↓
                           FCPXMLMutator.* (in-place DOM mutation)
                                              ↓
                           ExportService.exportAll() → writes to disk
```

All XML mutations happen in-place on the `XMLDocument` DOM — no serialization until export. `FCPXMLDocument.xmlDocument` is the single source of truth, and `FCPXMLMutator` methods modify it directly.

### State Management

Single `@Observable AppState` injected via `.environment()`. It holds all documents, media references, selections, UI sheet flags, undo stack, playback state, and timeline data. Views read from it; actions are methods on it.

Undo is snapshot-based: `pushUndo()` captures full `xmlData` + sequences for every document before mutations. Max 20 levels.

### Key Directories

- **`Models/`** — Pure data types. `FCPXMLDocument` wraps a live `XMLDocument`. `MediaReference` deduplicates media by filename across all loaded XMLs. `TimelineData`/`TimelineTrack`/`TimelineClip` are display-oriented timeline structures. `Timecode` handles frame-accurate TC arithmetic.
- **`Services/`** — Business logic with no UI dependency. `FCPXMLParser` reads XML. `FCPXMLMutator` writes XML. `TimelineExtractor` builds timeline display data. `RelinkEngine`/`ReferenceMatchEngine` do file matching. `SourcesSequenceBuilder` exports conform sequences.
- **`ViewModels/`** — Just `AppState.swift` (~1000 lines). Central hub for all state and actions.
- **`Views/`** — SwiftUI views organized by feature area. Action sheets in `Views/Actions/`. Timeline views in `Views/Timeline/`. Video player in `Views/VideoPlayer/`.

### UI Layout (ContentView)

```
NavigationSplitView
├── SidebarView (loaded XML files, sequence list)
└── Detail:
    └── VSplitView
        ├── HSplitView
        │   ├── MediaListView (deduplicated media table)
        │   └── VideoPlayerContent (embedded reference player)
        └── TimelinePanel
            ├── TimelineView (ruler + tracks + playhead + box select)
            └── ClipInspectorView (selected clip details/effects)
```

### FCP XML Structure

The app processes xmeml v4/v5 XML. Key XPath patterns used throughout:
- `//sequence` — Timeline sequences
- `//sequence/media/video/track/clipitem` — Video clips
- `//sequence/media/audio/track/clipitem` — Audio clips
- `//file[@id]` — File definitions (may be inline or root-level stubs)
- `clipitem/file` — File reference within a clip (may be `<file id="file3"/>` stub)
- `file/timecode/string` — Source timecode on media files
- `sequence/timecode/string` — Start timecode on sequences

File elements can be defined inline (with full metadata) or as ID-only stubs (`<file id="X"/>`). The parser's `buildFileMetadataMap()` pre-scans all `<file>` elements to resolve stubs. `FCPXMLMutator.buildFileMap()` maps file IDs to filenames.

### Timeline Hit Testing

Clips in the timeline use `.position(x:y:)` (NOT `.offset()`) inside a ZStack. This is critical — `.offset()` only moves visuals without relocating hit-test areas, making clips unclickable at their visual position. The playhead is rendered as an `.overlay(alignment: .topLeading)` on the content VStack.

### Video Player

`PlaybackCoordinator` wraps AVPlayer and synchronizes timeline playhead with reference video using timecode math: `timelineStartTC + playheadFrame → absoluteTC → absoluteTC - referenceStartTC → AVPlayer CMTime`. The floating player panel (`VideoPlayerWindow`) uses NSPanel with NSWindowDelegate — closing the window re-embeds the player instead of destroying the coordinator.

### Source Timecode Display

When scrubbing the timeline, the header shows the **source TC** of the clip under the playhead (not record TC). Calculation: `fileStartTimecodeFrame + clip.sourceInFrame + (playheadFrame - clip.startFrame)`. This is computed in `AppState.sourceTimecodesAtPlayhead`.

## Hardcoded Business Logic

- Reel name extraction regex: `A_\d+.*_h[A-Z0-9]{4}` → format `{A_number}_{code}` (in `ReelMetadataRepairer`)
- Only `A_`-prefixed files are eligible for reel repair
- File matching (relink/reference) uses case-insensitive stem comparison with optional fuzzy prefix matching
- R3D files get special split-sequence handling in `FileScanner`
