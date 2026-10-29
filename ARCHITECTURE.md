# Unified Media Hub — Architecture Assessment

## Workspace inspection

The parent workspace contains these actual checkouts: `Fast-Font`, `jellyfin-sdk-swift`, `localmusic`, `MPVKit`, `retroarch`, and `swift-toolkit` (Readium). The nested `multiuse` project had no application source at the start of this task. There is no Jellyfin server or Jellyfin iOS client checkout here: the available Jellyfin component is the generated Swift API SDK.

This assessment is based on package manifests, app configuration, source entry points, API modules, and license files in those checkouts. It is a source-fit plan; the app has not been built or runtime-tested on iOS.

## Component assessment and integration decisions

| Project | What the checked-out source provides | Integration decision | Constraints |
|---|---|---|---|
| Fast-Font | TTF/OTF font assets, an OpenType feature file, and browser userscripts (including a self-contained base64 font injection script). It is not an iOS reader or a Swift library. | Use selected, license-cleared font assets as optional Readium reader themes. Expose readable names and a preview in the unified reader settings. Do not bring the userscript into the app. | The repository is MIT licensed. Verify each included font's upstream/provenance license separately, especially the OpenDyslexic-derived face, before shipping. Custom-font use must preserve reader accessibility settings and allow returning to the system font. |
| Jellyfin | `jellyfin-sdk-swift` is a Swift Package (`JellyfinAPI`) with generated endpoints/models, auth, Quick Connect, discovery, WebSocket/session and streaming APIs. The app pins version 2.0.0 (iOS 16+, Swift tools 6.0) because the checked-out 3.4.0 revision fails current runner compilation in WebSocket source (`Error?` optional existential syntax). | `JellyfinProvider` wraps the SDK. It signs in with URL plus username/password, stores only its access token in Keychain, normalizes server item projections, feeds server browsing/search, creates audio/video stream URLs, and reports playback state. Playback and server reporting still need live-server verification; server-side transcoding negotiation and subtitle selection are not wired yet. | This is an API client, not the Jellyfin server or a complete client UI/playback engine. Jellyfin iOS itself is absent. Avoid leaking generated models into SwiftUI. Recheck the version pin after upstream compiler compatibility is restored. The SDK is MPL-2.0 licensed. |
| LocalMusic | A complete SwiftUI music app targeting iOS 18 / Swift 6, with `Track`, playlists, persistence, metadata and artwork caches, queue state, document picker, and an AVPlayer-based `AudioPlayerManager` that handles security-scoped URLs, interruptions, route changes, remote commands, and now-playing data. | Adapt the model, queue and playback/service logic into `MusicFeature`; retain its useful failure and audio-session handling. Rebuild views in the new design system instead of embedding its app. Route imported files through document-picker security scopes. | It is an app target rather than a reusable package. Its existing deployment target raises the minimum if copied wholesale; isolate/adapt code deliberately. Local file formats are limited to AVFoundation's supported formats unless another decoder is intentionally introduced. |
| MPVKit | Swift Package products for LGPL and GPL variants; iOS 15+ package manifest. The package pulls many prebuilt XCFrameworks (mpv/FFmpeg and codec/rendering dependencies). Its README describes the project as a learning tool and cautions about production use; Metal support uses a patch. | Define a `VideoPlaybackEngine` boundary. Start with AVPlayer for native/HLS and evaluate the LGPL MPVKit product for formats requiring libmpv. Keep GPL MPVKit out unless the whole distribution and source obligations are intentionally compatible with GPL. | Large native binary/dependency footprint, build and update provenance, codec patent considerations, thermal/memory cost, and GPL/LGPL relinking/source obligations need a release audit. No MPVKit runtime is wired into the shell yet. |
| Readium Swift Toolkit | Actual Swift source checkout and modular SPM package (`ReadiumShared`, `ReadiumStreamer`, `ReadiumNavigator`, `ReadiumOPDS`, `ReadiumLCP`), iOS 15+, Swift tools 6.2. Provides parsing, publication models, EPUB/PDF navigation, search, positions/highlights, custom fonts, OPDS and comic archive parsing. | Use Readium Shared/Streamer/Navigator through a `BookReaderFeature`; adapt EPUB navigation into SwiftUI and persist locators/bookmarks in shared app storage. Use its publication-aware font customization for Fast-Font. CBZ page display needs a small app-owned navigator over Readium's parsed image resources: the checked-out source has `ImageParser` but no `CBZNavigatorViewController` implementation, despite the Navigator guide mentioning that type. | Readium provides low-level components, not a bookshelf UI or app data layer. Its image parser recognizes CBZ/Divina, while CBR/RAR is unsupported. LCP needs EDRLab's separately supplied private `R2LCPClient.framework`. BSD-3-Clause. |
| RetroArch | Full C frontend and platform integration, including Apple/iOS build configuration and the Libretro core API. RetroArch `COPYING` is GPL-3.0. The repo is a frontend, not a curated set of console emulator cores or game assets. | Keep the game library and controls native. Prefer an isolated `EmulationRuntime` boundary around explicitly approved Libretro cores, save storage and controller input. Reuse the Libretro API where feasible; evaluate a smaller frontend/runtime adapter before attempting to embed all of RetroArch. | Core licenses are independent and must be audited one by one; do not bundle BIOS/ROMs. A GPL RetroArch integration affects the app's distribution/source obligations. Native iOS sandbox, controller support, background suspension and code-signing constrain the runtime. |

## Shared app architecture

- **App shell / design system:** SwiftUI navigation, typography, spacing, colors, surfaces, artwork cards, accessible controls, loading/error/empty states, and one appearance setting.
- **Library domain:** `MediaItem` identity is `(provider, providerItemID)` with kind, title, people, artwork reference, collections, tags, duration/page count, and local/server origin. Feature adapters own their specialized metadata while supplying a normalized searchable projection.
- **Providers:** local document imports, local music, Jellyfin server, and local game files each implement a small catalog/search/detail interface. Server and local origins stay visible in details and filters. The initial Jellyfin projection stays separate from SwiftData until remote playback and provider identity are integrated end-to-end.
- **Playback coordination:** one `PlaybackCoordinator` owns the active session, audio-session policy, now-playing metadata, progress checkpoints, interruptions and errors. Engines implement capability-oriented interfaces (seek/subtitles/audio tracks for video; queue/remote controls for music). Reading and gameplay are foreground experiences and never display a media mini-player over the content.
- **Persistence/services:** shared favorites, recents, artwork cache, search indexing, settings and progress live outside feature views. Reader locators/bookmarks remain Readium-based; game save state stays under the app container and is keyed by game plus core/version.
- **Feature modules:** `MusicFeature`, `VideoFeature`, `BooksFeature`, `GamesFeature`, `ServerFeature`. Each has its own detail and play/read screen but consumes the same shell, navigation and library services.

## Compatibility and dependency plan

The strictest checked-in toolchain requirement is Readium's Swift 6.2 package; LocalMusic uses Swift 6 and iOS 18, Jellyfin uses Swift 6 and iOS 16, while Readium and MPVKit declare iOS 15. A practical first target is iOS 18 with a current Xcode toolchain, then lowering the target only after the LocalMusic APIs and all transitive dependencies compile at that deployment version. Keep dependencies modular and do not add the GPL products by default. Pin package versions/revisions and commit the resolved dependency graph before release.

The workspace runs on Windows, so Xcode, iOS Simulator, device signing, and iOS runtime verification are unavailable here. A successful iOS build or working playback must not be claimed until checked on macOS with Xcode and a device/simulator.

## Licensing and distribution gate

Maintain a third-party notices bundle with exact versions, copyright notices, license text, and modifications. The initial source licenses identified are Fast-Font MIT, Jellyfin SDK MPL-2.0, LocalMusic MPL-2.0, MPVKit LGPL-3.0 and GPL-3.0 product variants, Readium BSD-3-Clause, and RetroArch GPL-3.0. This is not a substitute for reviewing transitive native dependencies, each Libretro core, and all font asset provenance. Resolve whether the product will be GPL-compatible before selecting RetroArch/GPL MPVKit components for an App Store build.

## Delivery sequence

1. Establish the unified shell and design tokens (started in this change).
2. Add shared library identity, provider interfaces, persistence, search, artwork and recents.
3. Integrate Readium for EPUB/CBZ and verify positions, bookmarks and custom font settings; explicitly report CBR as unsupported unless a separately licensed extractor is selected.
4. Runner-check the Jellyfin stream and playback-reporting wiring, then complete a live-server playback/resume test.
5. Adapt local music services and prove import, play, queue and progress behavior.
6. Select a video backend only after its format coverage and license/binary footprint are approved; implement subtitle/audio track selection and resume position.
7. Prototype a Libretro runtime with a license-cleared core, save states and controller handling; do not promise the whole RetroArch catalog automatically.
8. Consider the cross-media 2D collection experience after core import, browse and playback/read paths work.

## Open verification items

- Confirm redistribution rights for all Fast-Font font files and source dates/versions for every checkout.
- Confirm exact licenses of MPVKit's pinned native binary dependencies and any chosen Libretro core.
- Test package resolution and iOS builds on a current Mac/Xcode, then runtime-test malformed/unavailable files, playback interruption, progress restoration, server failures, EPUB navigation and game suspension/resume.
- Decide whether iOS 18 is acceptable as the app minimum or invest in adapting downlevel APIs.


