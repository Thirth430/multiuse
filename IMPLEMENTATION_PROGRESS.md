# Implementation progress

## Phase 1 — Product shell and source assessment

- [x] Inspect the six available source checkouts and record platform, extension points, and licensing constraints.
- [x] Establish an original SwiftUI navigation shell and shared design language.
- [x] Mark empty states and unavailable integrations accurately.

## Phase 2 — Shared local catalog and baseline playback (in progress)

- [x] Add a shared SwiftData catalog record for local and future provider-backed media.
- [x] Add document-picker import into the app container for audio, video, EPUB, and CBZ files.
- [x] Add local search, favorites, recents, and per-category empty states.
- [x] Add AVPlayer-based local audio/video controls and progress checkpoints.
- [x] Add a manually triggered GitHub Actions workflow and first importer unit tests.
- [ ] Adapt LocalMusic queue, metadata/artwork, remote commands, and interruption handling.
- [ ] Verify import/play/resume/unavailable-file behavior on an iOS device or simulator.

## Phase 3 — Readium and typography

- [ ] Add Readium through modular Swift package products.
- [ ] Integrate EPUB navigation, locator persistence, bookmarks, and reading preferences.
- [ ] Integrate CBZ browsing; retain the verified CBR limitation unless a separate implementation is selected.
- [ ] Add Fast-Font faces after checking font asset redistribution rights.

## Phase 4 — Jellyfin server provider

- [ ] Add server connection, auth/discovery, secure account storage, and source filters.
- [ ] Normalize server metadata and artwork into the shared catalog projection.
- [ ] Connect remote playback, session reporting, and resume progress.

## Phase 5 — Video engine decision

- [ ] Compare AVPlayer format coverage with the desired formats using sample files.
- [ ] Review MPVKit binary provenance, transitive licenses, distribution size, and thermal behavior.
- [ ] Add subtitle/audio track controls and resume only after selecting and validating an engine.

## Phase 6 — Retro games and optional signature feature

- [ ] Select a Libretro boundary and audit each proposed core's license and iOS build.
- [ ] Implement controller mapping, save paths, favorites, and game metadata without bundling copyrighted game content.
- [ ] Prototype the cross-media 2D collection experience after core media paths are usable.

## Verification policy

This project is being edited on Windows without Xcode or iOS Simulator. No iOS build or simulator test has been claimed. The first checkpoint tests are in `.github/workflows/ios-checkpoint.yml`; the nested project repository currently has no GitHub remote, so it must be pushed to a GitHub repository before the workflow can run. The user will run that workflow and share its result before platform-specific fixes are treated as verified.
