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

- [x] Add Readium Shared, Streamer, and Navigator from the checked-out revision through a pinned Swift package dependency.
- [x] Add Readium EPUB navigation, saved locators, bookmarks, table of contents, and font-size controls.
- [x] Add CBZ parsing with an app-owned page navigator over Readium's image resources (no CBZ navigator implementation exists in the checked-out source), including saved-page restoration and bookmark navigation.
- [x] Include the MIT-licensed Fast Serif face as an optional reader font.
- [ ] Verify EPUB/CBZ rendering, restored positions, bookmarks, and font injection on the GitHub iOS simulator.
- [ ] Retain the verified CBR limitation unless a separate implementation is selected.

## Phase 4 — Jellyfin server provider (in progress)

- [x] Add the checked-out Jellyfin Swift SDK as a pinned Swift package dependency.
- [x] Add manual URL and username/password sign-in and save the returned session token in iOS Keychain (password is not retained).
- [x] Fetch server audio, albums, videos, episodes, and books and normalize title, creator, category, duration, and primary-artwork URL for the shared search/library UI.
- [x] Add server browsing, media-type filters, local-plus-server search, refresh, and disconnect controls.
- [ ] Verify package resolution, authentication, artwork, pagination, and network failures with a live Jellyfin server on the GitHub runner/device.
- [ ] Add remote playback, session reporting, and server resume progress; remote catalog entries are browse-only in this checkpoint.

## Phase 5 — Video engine decision

- [ ] Compare AVPlayer format coverage with the desired formats using sample files.
- [ ] Review MPVKit binary provenance, transitive licenses, distribution size, and thermal behavior.
- [ ] Add subtitle/audio track controls and resume only after selecting and validating an engine.

## Phase 6 — Retro games and optional signature feature

- [ ] Select a Libretro boundary and audit each proposed core's license and iOS build.
- [ ] Implement controller mapping, save paths, favorites, and game metadata without bundling copyrighted game content.
- [ ] Prototype the cross-media 2D collection experience after core media paths are usable.

## Verification policy

This project is being edited on Windows without Xcode or iOS Simulator. No iOS build or simulator test has been claimed for the Jellyfin changes. The checkpoint workflow is `.github/workflows/ios-checkpoint.yml`, and this project has an `origin` remote. After the Jellyfin changes are committed and pushed, the user should run the workflow and share its result before platform-specific fixes are treated as verified. Live-server behavior also needs a real Jellyfin server account and network test.
