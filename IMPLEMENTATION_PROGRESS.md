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
- [x] Page through Jellyfin library results in batches of 200 until the server's total record count is reached.
- [x] Add Jellyfin-backed favorite state and toggle actions in server item details; show favorite markers in server browse rows.
- [x] Browse tracks within Jellyfin music albums and start a selected server track from the album detail.
- [x] Include Jellyfin music artists in the server catalog and browse each artist's albums before opening album tracks.
- [x] Include Jellyfin playlists in the server catalog and browse playlist tracks with individual playback actions.
- [x] Queue Jellyfin album and playlist tracks in the shared Up Next controls, including next/previous, automatic advance, reordering, and removal.
- [x] Surface AVPlayer end-of-item playback failures and buffering stalls in the shared playback error state.
- [x] Open Jellyfin search results in an in-app detail view with direct playback for playable items and a clear browse-only state for server books.
- [x] Wire Jellyfin playback-info/stream URLs into the shared AVPlayer and report server playback start, periodic progress, stop, and resume position.
- [ ] Verify package resolution, authentication, artwork, paginated loading, and network failures with a live Jellyfin server on the GitHub runner/device; revisit a newer SDK pin after upstream compiler compatibility is confirmed.
- [ ] Verify Jellyfin album track listing and selected-track playback against a live server.
- [ ] Verify Jellyfin artist album browsing against a live server.
- [ ] Verify Jellyfin playlist item loading and selected-track playback against a live server.
- [ ] Verify Jellyfin collection queue progression, remote controls, reordering, and removal against a live server.
- [ ] Verify playback error and buffering recovery behavior with unavailable local files and interrupted Jellyfin streams.
- [ ] Verify remote audio/video streaming, resume seeking, and Jellyfin session progress/stopped reporting against a live server; subtitle selection and server-side transcoding profile negotiation remain unimplemented.

## Phase 5 — Video engine decision

- [x] Add embedded audio and subtitle selection for AVPlayer-supported video assets.
- [x] Add a dedicated full-screen video surface for local and Jellyfin playback, with audio/subtitle track menus and an expand action from the unified player.
- [x] Read local video title, creator, and duration tags and save embedded cover art or an asynchronously generated poster frame.
- [x] Inspect MPVKit's Package.swift, native demo entry points, bundled binary target structure, and stated maintenance scope; defer production linkage pending a Mac prototype and binary/license audit.
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
- [ ] Verify Jellyfin favorite toggling and restored favorite state against a live server.
- [ ] Audit EmulatorJS and emulator core licenses/provenance independently from JellyEmu's MIT license.
- [ ] Implement controller mapping, save paths, favorites, and game metadata without bundling copyrighted game content.
- [ ] Prototype the cross-media 2D collection experience after core media paths are usable.

## Verification policy

This project is being edited on Windows without Xcode or iOS Simulator. The user confirmed the GitHub iOS checkpoint passed on commit `936f09a8090fee1a2d31c72339f478c5842e2372`, including the full-screen video player, then confirmed later checkpoints for Jellyfin pagination (`ca55c2e`), album track browsing (`f682068`), artist album browsing (`5d40a98`), playlist browsing (`808bf2a`), and remote album/playlist queue support (current checkout `586b42e`). Local and live-server verification details are still listed separately below. Live game playback still needs a JellyEmu-enabled server and simulator/device verification. Device playback, artwork extraction, reader presentation, video track selection, game UI, and other live Jellyfin behavior also remain runtime checks.
