# Unified Media iOS — Agent Handoff

Updated: 2026-10-29 (America/Chicago)

## Instructions for the next agent

Continue the user's project autonomously from this checkout. Read this file, `IMPLEMENTATION_PROGRESS.md`, `ARCHITECTURE.md`, and `THIRD_PARTY_NOTICES.md` before changing code.

**Standing user instruction:** keep this handoff current for all future progress unless the user explicitly says otherwise. After each meaningful implementation change, runner result, architecture/licensing decision, or newly found limitation, update the current state, verification status, and dated activity notes in this file (and keep `IMPLEMENTATION_PROGRESS.md` aligned). Never claim that code built or a feature works unless that exact state was built or exercised. The user is working without a Mac and expects to run the manual GitHub iOS workflow; ask them to run it after unverified code changes and continue fixing any failures they report.

## Workspace and checkout

- Repository: `C:\Users\elias\Desktop\multiuse\multiuse`
- Remote: `https://github.com/Thirth430/multiuse.git`
- Branch: `main`
- Last observed `HEAD`: `772858cf50cb9482ba8590acf902bdb4243e1e50`
- Current working tree at handoff: `IMPLEMENTATION_PROGRESS.md` and `Sources/App/AppShellView.swift` modified; `HANDOFF.md` and `Sources/Services/ArtworkDataCache.swift` untracked. The implementation changes are the artwork-cache work described below. None of these working-tree changes are represented by the observed HEAD commit.
- Other checked-out source projects live in the parent folder: `Fast-Font`, `JellyEmu`, `jellyfin-sdk-swift`, `localmusic`, `MPVKit`, `retroarch`, and `swift-toolkit` (Readium).
- The session has no Xcode or iOS Simulator. `git diff --check` passed for tracked edits at the last check. It does not compile Swift and does not include the untracked file in its output.
- Manual CI: `.github/workflows/ios-checkpoint.yml` (`workflow_dispatch`, `macos-latest`, latest-stable Xcode, XcodeGen, `xcodebuild test` on an available iPhone simulator). Ask the user to push and run it after the current edits. The workflow does not test against a live Jellyfin server.

## Original user brief

The user wants one polished iOS application combining useful functionality from Jellyfin, FastFont, LocalMusic, RetroArch, MPVKit, and Readium. Some source checkouts are templates, libraries, SDKs, or server plugins rather than complete apps; build the unified GUI and product shell in this repository. Use proven source engines where practical, inspect actual source rather than relying on READMEs, preserve licenses and functionality, and clearly distinguish implemented work from unverified or unavailable features.

### Product requirements to preserve

1. **Unified media hub.** One app for local and server-backed books, music, videos, and retro games. A shared home/library/search/navigation/settings/design system; specialized, native-feeling media experiences. Include artwork, metadata, collections, favorites, recents, resume state, playlists, and useful empty/error/loading states. Avoid a generic file browser or embedded-app launcher feel.
2. **Music.** Local library import and management, metadata/artwork, artists/albums, persistent playlists, queue/up-next, transport controls, background/lock-screen commands, resume, and formats supported by the chosen engine.
3. **Video.** Dedicated playback, local and Jellyfin streams, format support, resume, audio/subtitle tracks, metadata/posters, and robust errors. Evaluate MPVKit against AVPlayer before linking it; do not make unsupported claims.
4. **Books/comics.** Readium EPUB reader with locators/progress, bookmarks, table of contents, text/font customization. CBZ has an app-owned navigator over Readium archive resources. The inspected Readium source does not support CBR/RAR; keep this limitation explicit until a suitable implementation is selected.
5. **Games.** Local game catalog, metadata/favorites/system labels, launch/runtime, controller support, save-state behavior. Determine whether a legally and technically suitable Libretro core can be embedded in iOS. Do not bundle copyrighted ROMs or BIOS. JellyEmu is a Jellyfin server plugin, not an iOS emulator.
6. **Shared foundations.** Reuse catalog/search, origin/provider identity, metadata normalization, artwork caching, favorites, recents, settings, and playback coordination across media types.
7. **Optional signature feature.** Consider a small cross-media interactive 2D experience only after the core media flows are working; it must not delay them.

### Architecture and development requirements

- Establish a concrete integration strategy from actual source: language/frameworks/deployment targets, dependencies, compatibility, integration boundaries, licensing/attribution, file access/storage, shared models, playback sessions, performance/battery/background behavior.
- Prefer modular adapters over embedding other complete apps or deeply coupling features. Avoid unnecessary rewrites, fragile patches, and mock screens that imply functionality exists.
- Implement incrementally. Handle unavailable files and provider failures. Test real navigation/open/play/read/progress flows on GitHub macOS runners or devices. Do not report test success without a user/runner result.
- Current platform minimum is iOS 18, Swift 6, generated Xcode project via XcodeGen.

### User's follow-up constraints

The user explicitly said that some inputs are templates rather than apps, so the GUI must be created here. They asked for a plan and then follow-through, and said they cannot access a Mac outside GitHub runners, so ask them to run tests. They have repeatedly supplied GitHub workflow results and replied “success”; treat those replies as confirmation of the checkpoint just requested, while recording the commit association carefully. If a success arrives while local `HEAD` is unchanged and edits are dirty, say so rather than attributing the result to a commit that is not present.

## Work completed

The authoritative granular checklist is `IMPLEMENTATION_PROGRESS.md`; source capability/licensing decisions are in `ARCHITECTURE.md`; current bundled notices are in `THIRD_PARTY_NOTICES.md`.

### App shell and shared catalog

- Built the Atlas SwiftUI app shell with Home, Music, Video, Books, and Games sections, common visual styling, local/server search, settings, import entry points, media details, favorites, recent/resume surfaces, and consistent loading/error/empty states.
- Added SwiftData catalog records with local/provider identity, media kind, origin, metadata, favorites, artwork references, reading progress, and playback progress.
- Added document import for audio, video, EPUB, CBZ, and supported local game-image extensions. Copies imports into app storage, classifies systems, and handles removal/queue cleanup.
- Local music includes adapted LocalMusic metadata/artwork behavior, albums/artists, persistent ordered playlists, queue/up-next, and AVPlayer-based playback.
- Playback coordinator handles queue navigation/editing, remote/lock-screen commands, now-playing metadata, audio interruptions, headphone removal, progress, and player failures/buffering. It can now host Jellyfin album/playlist queues as well as local queues.

### Readium/Fast-Font

- Pinned Readium Shared/Streamer/Navigator to revision `e20d5cfc847c2cfa02aaf7be409848b504bd46ca`.
- EPUB reader includes navigation, saved Readium locators, bookmarks, TOC, and font-size customization.
- CBZ uses Readium's image parsing with an app-owned page navigator and saved page/bookmark state.
- Included Fast Serif font as an optional reader typeface. Audit all font provenance before release.
- CBR is not supported by checked-out Readium source; it remains explicitly unsupported.

### Jellyfin/JellyEmu

- Pinned Jellyfin Swift SDK 2.0.0 revision `185ef233c05bd889dbb9d9fa49ceb34b1dd16b43`; the inspected 3.4.0 source failed Swift compilation on `Error?` existential syntax.
- URL and username/password sign-in; access token stored in Keychain, password not retained. Restore connection, disconnect, browse/search/filter local + remote libraries.
- Normalizes songs/albums/artists/playlists, videos/episodes, books, JellyEmu-tagged games, image URLs, favorite state, and resume data. Pages catalogs in 200-item batches.
- Server details support favorites, album track listing, artist-to-album navigation, playlist track listing, and shared AVPlayer playback. Album/playlist tracks enter shared Up Next; Play All, next/previous, auto-advance, reorder, and remove are wired.
- Server playback reports start/progress/stop and uses a posted iOS playback device profile with direct-play capabilities plus HLS video/audio fallback and subtitle manifest support. HLS transcoding URL is normalized to the configured server origin/base path; incompatible/missing transcode URL reports an error.
- AVPlayer handles server and local streams, shows audio/subtitle selections when AVFoundation exposes them, and surfaces item failures/buffering.
- JellyEmu source is MIT C#/.NET 9/Jellyfin 10.11 server plugin. The app recognizes its `Book` + `JellyEmu` tag convention and loads `/jellyemu/play/{itemId}` in WKWebView with the expected token hook. It is not an embedded emulator and needs live-server/device verification.

### Video decision

- Full-screen native AVPlayer experience for local/server video; track controls, progress, error messages, and embedded metadata/poster extraction.
- MPVKit source was inspected. It is a low-level shim plus many prebuilt XCFrameworks, has LGPL/GPL products and a low-maintenance/learning-tool warning. It is deferred until AVPlayer gaps, Mac prototype, binary provenance, license obligations, size, and thermal costs are established. Do not link GPL MPVKit by default.

### Current artwork-cache change

- `Sources/Services/ArtworkDataCache.swift` adds a bounded shared NSCache memory cache. File URLs load off the main actor; remote URLs use URLSession and its HTTP cache. `MediaArtwork` uses it for local/remote art; Jellyfin detail and row art now use `RemoteArtwork` instead of direct AsyncImage.
- The user most recently reported “Success” after being asked to push/run the artwork checkpoint. However, current observed Git state remains at `772858c` with these artwork edits dirty/untracked. Treat the test result as user-reported but do not claim the currently observed commit contains it. Ask/confirm current runner commit if needed, or have the user run after pushing these files.
- No local Xcode build was possible. The last `git diff --check` passed for tracked edits.

## Checkpoint and failure history

The user has supplied these failures during GitHub testing; subsequent `success` replies confirmed fixes for the checkpoints requested at the time:

1. Test compile errors: `LibraryItem` ambiguous, generic parameter uninferred, `Equatable` missing `.music`; fixed test/source type qualification.
2. Simulator install failed due missing/invalid `CFBundleExecutable`; fixed app target/plist configuration.
3. Readium `NavigatorDelegate` conformance, locator progress label/string visibility/argument-order compile failures; fixed against pinned Readium APIs.
4. Jellyfin SDK Swift compile error `Optional 'any' type must be written '(any Error)?'`; moved to compatible SDK 2.0.0 pin.
5. Jellyfin provider enum contextual-type errors in music/book/video normalization; fixed explicit `MediaKind` typing.
6. Local importer test initially persisted a UUID as title instead of filename fallback `Late Night`; fixed filename fallback. Later output showed importer checkpoint passing.
7. Swift 6 data-race diagnostics around sending `AVAsset`; changed AVFoundation metadata/track loading to sequential operations and adjusted concurrency handling.
8. JellyEmu changes hit renamed WebKit handler API, SDK named argument order, and inferred `Any` item errors; corrected to the SDK/WebKit APIs, then runner passed.
9. A sequence of later server/UI enhancements was runner-checked and user reported success.

Known checkpoint references captured in progress notes:

- `936f09a8090fee1a2d31c72339f478c5842e2372`: user-confirmed checkpoint including full-screen video.
- `ca55c2e`: Jellyfin catalog pagination checkpoint.
- `f682068`: Jellyfin album track browsing checkpoint.
- `5d40a98`: Jellyfin artist album browsing checkpoint.
- `808bf2a`: Jellyfin playlist browsing checkpoint.
- `586b42e`: remote album/playlist queue checkpoint.
- `49ac323`: AVPlayer failure/buffering reporting checkpoint.
- `772858c`: Jellyfin posted playback profile/HLS subtitle support checkpoint.
- Artwork-cache result was reported as successful, but the checkout did not advance beyond `772858c`; source remains dirty as described above.

## Prioritized work remaining

### Immediate

1. Reconcile the reported artwork-cache CI success with Git. Current `HEAD` is `772858cf50cb9482ba8590acf902bdb4243e1e50`; working tree has two modified tracked files and a new untracked cache source. Do not discard them. Make sure the actual GitHub checkpoint included this file; if not, ask the user to push/run it. Fix any reported Swift 6 concurrency or `NSCache` errors.
2. Keep `HANDOFF.md` and `IMPLEMENTATION_PROGRESS.md` in sync after the above result.

### Functional verification on a live Jellyfin server/device

- Authentication, Keychain restore/expired token, disconnect, reverse-proxy base path, server failures and large paginated catalogs.
- Remote artwork auth/cache/placeholder and memory behavior.
- Album/artist/playlist listing and selected track, Play All, auto-advance, next/previous, remote controls, reorder/removal.
- Direct play versus HLS transcode, server audio/subtitle tracks, seek/resume, session start/progress/stop, interruptions and unavailable media.
- JellyEmu plugin compatibility, ROM/player load, auth headers, touch/gamepad/controller, save behavior and exit/session cleanup.
- GitHub build/test success alone is not live-server verification. Keep separate checkboxes.

### Local library and reader verification

- On simulator/device: import/play/seek/resume/remove/unavailable audio/video, file-format coverage, metadata and cover/poster extraction, queue progress, background/lock-screen controls, interruptions, route changes, and local playlists.
- Verify EPUB + CBZ open, render, restore locators/pages, TOC/bookmarks/fonts and failure states. CBR remains unsupported unless a separate compatible RAR parser is chosen and audited.
- The current two importer tests are not enough for all these runtime cases. Add tests only when useful and continue to rely on GitHub Xcode CI for builds.

### Games/video engine and signature experience

- Local ROM import currently does **not** launch: no core runtime is linked. JellyEmu web player is a different server-mediated path.
- Audit Libretro ABI boundary and per-core licenses. mGBA is a candidate (MPL-2.0; source implements save-state serialize/unserialize; upstream recipe suggests iOS plausibility) but no static archive/iOS embed has been proven. Build/audit before UI claims.
- Do not embed RetroArch's GPL-3.0 frontend without an explicit GPL/distribution decision. Do not bundle copyrighted game content/BIOS.
- MPVKit remains deferred pending Mac/Xcode proof and complete LGPL binary/transitive-license/redistribution review. Test real AVPlayer format gaps first.
- Cross-media 2D mini-experience is a later milestone after books/music/video/game paths work.

### Licensing/release

- Read `THIRD_PARTY_NOTICES.md`. Verify each font's upstream provenance, MPVKit binary/transitive licenses, and every selected core's licenses/source obligations.
- Preserve Readium BSD-3-Clause, Jellyfin SDK MPL-2.0, Fast-Font MIT attribution; LocalMusic is MPL-2.0 but not linked wholesale. MPVKit has LGPL/GPL products; RetroArch frontend GPL-3.0.
- Confirm whether iOS 18 minimum is acceptable and commit dependency resolution before release.

## Source assessment summary

- **Fast-Font:** assets/userscripts, not an iOS app/library; only optional font assets were adapted. Font provenance remains a release audit.
- **LocalMusic:** complete SwiftUI app targeting iOS 18/Swift 6, AVFoundation-based. Adapted metadata/playback behavior; rebuilt GUI instead of embedding app.
- **Jellyfin:** available checkout is generated Swift API SDK, not server/client app. Adapter keeps SDK models out of views. MPL-2.0.
- **Readium:** modular Swift toolkit. App owns reader UI, SwiftData/progress integration, and CBZ page navigator; CBR/RAR unsupported in checked source. BSD-3-Clause.
- **RetroArch:** GPL-3.0 frontend and Libretro ABI header, but no emulator cores in checkout. Do not assume it supplies an embeddable core.
- **MPVKit:** prebuilt libmpv/FFmpeg frameworks and C-level demo, LGPL/GPL variants, low maintenance warning. AVPlayer baseline; link only after proof/audit.
- **JellyEmu:** server plugin only, .NET 9 and Jellyfin 10.11; app's WebKit route is interoperability, not embedded native emulator.

See `ARCHITECTURE.md` for the full integration assessment and compatibility notes.

## Activity log

- 2026-10-29: User confirmed the Jellyfin playback-profile/HLS-subtitle checkpoint passed. Added shared artwork cache and replaced remote AsyncImage call sites. User then reported the artwork-cache checkpoint passed. Current checkout still shows the artwork implementation as dirty/untracked at HEAD `772858c`; reconcile the runner commit before claiming that exact tree is verified. Created this handoff at the user's request.
- Future agents: append a dated bullet for each meaningful implementation/test/architecture update and refresh the snapshot and immediate next action above.
