# Implementation progress

## Phase 1 — Product shell and source assessment

- [x] Inspect the six available source checkouts and record platform, extension points, and licensing constraints.
- [x] Establish an original SwiftUI navigation shell and shared design language.
- [x] Mark empty states and unavailable integrations accurately.

## Phase 2 — Shared local catalog and baseline playback (in progress)

- [x] Add a shared SwiftData catalog record for local and future provider-backed media.
- [x] Add document-picker import into the app container for audio, video, EPUB, and CBZ files.
- [x] Add local search, favorites, recents, and per-category empty states.
- [x] Confirm media removal, delete its imported file and artwork after catalog save, remove playlist references and queued entries, and stop it if currently playing.
- [x] Add AVPlayer-based local audio/video controls and progress checkpoints.
- [x] Add a manually triggered GitHub Actions workflow and first importer unit tests.
- [x] Adapt LocalMusic metadata tags and embedded artwork into shared records and artwork rendering; extend import recognition to FLAC and Opus.
- [x] Add a shared playback queue, previous/next controls, lock-screen/remote commands, now-playing metadata, audio interruption handling, and headphone-removal pause behavior.
- [x] Add an Up Next panel to the player with queue selection, reordering, and removal controls.
- [x] Add persistent local music playlists with create/edit/delete, reorderable track membership, playlist browsing, and playlist queue playback.
- [x] Add grouped album and artist browsing with detail lists and queue playback.
- [x] Add a playlist persistence unit test for ordered track IDs.
- [x] Verify playlist ordered-ID persistence with the new GitHub iOS unit test (checkpoint run #20 passed).
- [ ] Verify playlist editing, unavailable tracks, and playback progression on an iOS simulator/device.
- [ ] Verify album and artist grouping/detail playback on the GitHub iOS runner/device.
- [ ] Verify music tags/artwork, queue progression, background controls, interruptions, and supported formats on the GitHub iOS runner/device.
- [ ] Verify import/play/resume/unavailable-file behavior on an iOS device or simulator.

## Phase 3 — Readium and typography

- [x] Add Readium Shared, Streamer, and Navigator from the checked-out revision through a pinned Swift package dependency.
- [x] Add Readium EPUB navigation, saved locators, bookmarks, table of contents, and font-size controls.
- [x] Add CBZ parsing with an app-owned page navigator over Readium's image resources (no CBZ navigator implementation exists in the checked-out source), including saved-page restoration and bookmark navigation.
- [x] Include the MIT-licensed Fast Serif face as an optional reader font.
- [ ] Verify EPUB/CBZ rendering, restored positions, bookmarks, and font injection on the GitHub iOS simulator.
- [ ] Retain the verified CBR limitation unless a separate implementation is selected.

## Phase 4 — Jellyfin server provider (in progress)

- [x] Add Jellyfin Swift SDK 2.0.0 as a pinned Swift package dependency; 3.4.0 failed in SDK WebSocket source under the GitHub runner's Swift compiler.
- [x] Add manual URL and username/password sign-in and save the returned session token in iOS Keychain (password is not retained).
- [x] Fetch server audio, albums, videos, episodes, and books and normalize title, creator, category, duration, and primary-artwork URL for the shared search/library UI.
- [x] Add server browsing, media-type filters, local-plus-server search, refresh, and disconnect controls.
- [x] Open Jellyfin search results in an in-app detail view with direct playback for playable items and a clear browse-only state for server books.
- [x] Wire Jellyfin playback-info/stream URLs into the shared AVPlayer and report server playback start, periodic progress, stop, and resume position.
- [ ] Verify package resolution, authentication, artwork, pagination, and network failures with a live Jellyfin server on the GitHub runner/device; revisit a newer SDK pin after upstream compiler compatibility is confirmed.
- [ ] Verify remote audio/video streaming, resume seeking, and Jellyfin session progress/stopped reporting against a live server; subtitle selection and server-side transcoding profile negotiation remain unimplemented.

## Phase 5 — Video engine decision

- [x] Add embedded audio and subtitle selection for AVPlayer-supported video assets.
- [x] Read local video title, creator, and duration tags and save embedded cover art or an asynchronously generated poster frame.
- [ ] Verify selectable tracks on sample local and Jellyfin assets; external subtitle loading remains unimplemented.
- [ ] Verify imported video metadata and poster extraction on the GitHub iOS runner/device.
- [ ] Compare AVPlayer format coverage with the desired formats using sample files.
- [ ] Review MPVKit binary provenance, transitive licenses, distribution size, and thermal behavior.
- [ ] Decide whether MPVKit's LGPL product is needed for formats AVPlayer cannot play, then validate its iOS integration and distribution costs.

## Phase 6 — Retro games and optional signature feature

- [x] Import local game files for the listed cartridge and disc image extensions, identify the associated system, and use shared favorites/search/catalog details.
- [x] Clearly mark game launch unavailable until a suitable licensed and iOS-compatible core runtime is linked.
- [x] Verify local game-file import and system classification with the GitHub iOS unit test (checkpoint run #20 passed).
- [ ] Verify game browsing and favorites on an iOS simulator/device.
- [ ] Select a Libretro boundary and audit each proposed core's license and iOS build.
- [x] Inspect the added JellyEmu source: it is a .NET 9/Jellyfin server plugin, not a linkable iOS emulator. Confirm its Jellyfin book/tag catalog convention, web player route, ROM streaming, saves, sessions, and RetroArch playlist API.
- [x] Classify JellyEmu-tagged Jellyfin book items as games, expose the game system tag and Games filter, and connect game details to the plugin's `/jellyemu/play/{itemId}` route in a native-hosted WKWebView with its expected token hook.
- [ ] Verify plugin compatibility, player loading, touch/gamepad controls, save-state behavior, and exit/session handling on a supported iOS simulator/device with a live server; this integration is currently unverified.
- [ ] Audit EmulatorJS and emulator core licenses/provenance independently from JellyEmu's MIT license.
- [ ] Implement controller mapping, save paths, favorites, and game metadata without bundling copyrighted game content.
- [ ] Prototype the cross-media 2D collection experience after core media paths are usable.

## Verification policy

This project is being edited on Windows without Xcode or iOS Simulator. GitHub iOS checkpoint run #23 passed on commit `086aaa3f013ef9755d8516f18f685ab21898a1af`. JellyEmu catalog and WKWebView changes are newer and have not been built or tested. Device playback, artwork extraction, reader presentation, video track selection, game UI, and live Jellyfin/JellyEmu behavior still need runtime verification. Live-server testing requires a Jellyfin server with JellyEmu installed and accessible.
