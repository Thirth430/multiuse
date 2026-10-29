import AVFoundation
import MediaPlayer
import Observation
import UIKit

@MainActor
@Observable
final class PlaybackCoordinator {
    let player = AVPlayer()
    private(set) var currentItem: MediaLibraryRecord?
    private(set) var isPlaying = false
    private(set) var elapsedSeconds: Double = 0
    private(set) var durationSeconds: Double = 0
    private(set) var errorMessage: String?
    private(set) var videoAudioTrackTitles: [String] = []
    private(set) var videoSubtitleTrackTitles: [String] = []
    @ObservationIgnored private var remoteSession: JellyfinPlaybackSession?
    @ObservationIgnored private var remoteProvider: JellyfinProvider?
    @ObservationIgnored private var lastRemoteProgressReport = Date.distantPast
    @ObservationIgnored private var queue: [MediaLibraryRecord] = []
    @ObservationIgnored private var queueIndex = 0
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var shouldResumeAfterInterruption = false
    @ObservationIgnored private var videoAudioGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var videoSubtitleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var videoAudioOptions: [AVMediaSelectionOption] = []
    @ObservationIgnored private var videoSubtitleOptions: [AVMediaSelectionOption] = []

    init() {
        configureRemoteCommands()
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let shouldResume = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .began {
                    self.shouldResumeAfterInterruption = self.isPlaying
                    self.player.pause(); self.isPlaying = false
                }
                else if shouldResume, self.currentItem != nil, self.shouldResumeAfterInterruption {
                    self.player.play(); self.isPlaying = true
                }
                self.shouldResumeAfterInterruption = false
            }
        })
        notificationTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.player.pause(); self.isPlaying = false
            }
        })
        notificationTokens.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.advanceAfterCompletion() }
        })
    }

    func play(_ item: MediaLibraryRecord, queue items: [MediaLibraryRecord] = [], startIndex: Int = 0) {
        guard item.kind == .music || item.kind == .video else { return }
        queue = items.isEmpty ? [item] : items
        queueIndex = min(max(startIndex, 0), queue.count - 1)
        endRemoteSession()
        guard FileManager.default.fileExists(atPath: item.localURL.path) else {
            errorMessage = "This file is no longer available in the app library. You can remove it and import it again."
            return
        }

        _ = start(item, from: item.localURL, at: item.progressSeconds)
    }

    func playRemote(
        _ item: MediaLibraryRecord,
        session: JellyfinPlaybackSession,
        provider: JellyfinProvider
    ) {
        guard item.kind == .music || item.kind == .video else { return }
        endRemoteSession()
        queue = [item]
        queueIndex = 0
        remoteSession = session
        remoteProvider = provider
        lastRemoteProgressReport = .now
        guard start(item, from: session.streamURL, at: item.progressSeconds) else {
            endRemoteSession()
            return
        }
        Task { await provider.reportPlaybackStarted(session, positionSeconds: item.progressSeconds) }
    }

    @discardableResult
    private func start(_ item: MediaLibraryRecord, from url: URL, at position: Double) -> Bool {

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "Audio playback could not start: \(error.localizedDescription)"
            return false
        }

        currentItem = item
        item.lastOpenedAt = .now
        videoAudioGroup = nil
        videoSubtitleGroup = nil
        videoAudioOptions = []
        videoSubtitleOptions = []
        videoAudioTrackTitles = []
        videoSubtitleTrackTitles = []
        let playerItem = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: playerItem)
        if item.kind == .video {
            Task { await loadVideoTrackOptions(from: playerItem.asset, itemID: item.id) }
        }
        if position > 0 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        errorMessage = nil
        refreshProgress()
        updateNowPlayingInfo(refreshArtwork: true)
        return true
    }

    func togglePlayback() {
        guard currentItem != nil else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func playNext() {
        guard !queue.isEmpty else { return }
        queueIndex = (queueIndex + 1) % queue.count
        play(queue[queueIndex], queue: queue, startIndex: queueIndex)
    }

    private func advanceAfterCompletion() {
        guard queueIndex + 1 < queue.count else { stop(); return }
        queueIndex += 1
        play(queue[queueIndex], queue: queue, startIndex: queueIndex)
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        if elapsedSeconds > 3 { seek(to: 0); return }
        queueIndex = (queueIndex - 1 + queue.count) % queue.count
        play(queue[queueIndex], queue: queue, startIndex: queueIndex)
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        elapsedSeconds = seconds
        currentItem?.progressSeconds = seconds
        updateNowPlayingInfo()
    }

    func selectVideoAudioTrack(_ index: Int) {
        guard videoAudioOptions.indices.contains(index), let group = videoAudioGroup else { return }
        player.currentItem?.select(videoAudioOptions[index], in: group)
    }

    func selectVideoSubtitleTrack(_ index: Int?) {
        guard let group = videoSubtitleGroup else { return }
        let option = index.flatMap { videoSubtitleOptions.indices.contains($0) ? videoSubtitleOptions[$0] : nil }
        player.currentItem?.select(option, in: group)
    }

    private func loadVideoTrackOptions(from asset: AVAsset, itemID: String) async {
        // AVAsset is not Sendable. Load its selection groups sequentially so
        // Swift 6 does not send the same asset into two concurrent child tasks.
        let audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
        let subtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)
        guard currentItem?.id == itemID else { return }

        videoAudioGroup = audioGroup
        videoSubtitleGroup = subtitleGroup
        videoAudioOptions = audioGroup?.options ?? []
        videoSubtitleOptions = subtitleGroup?.options ?? []
        videoAudioTrackTitles = videoAudioOptions.map(\.displayName)
        videoSubtitleTrackTitles = videoSubtitleOptions.map(\.displayName)
    }

    func refreshProgress() {
        guard let currentItem else { return }
        let elapsed = player.currentTime().seconds
        if elapsed.isFinite, elapsed >= 0 {
            elapsedSeconds = elapsed
            currentItem.progressSeconds = elapsed
        }
        let duration = player.currentItem?.duration.seconds ?? 0
        if duration.isFinite, duration > 0 {
            durationSeconds = duration
            currentItem.durationSeconds = duration
        }
        isPlaying = player.rate > 0
        updateNowPlayingInfo()
        if let remoteSession, let remoteProvider {
            let now = Date.now
            if durationSeconds > 0, elapsedSeconds >= durationSeconds - 1 {
                endRemoteSession()
            } else if now.timeIntervalSince(lastRemoteProgressReport) >= 15 {
                lastRemoteProgressReport = now
                Task {
                    await remoteProvider.reportPlaybackProgress(
                        remoteSession,
                        positionSeconds: elapsedSeconds,
                        isPaused: !isPlaying
                    )
                }
            }
        }
    }

    func stop() {
        endRemoteSession()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        isPlaying = false
        elapsedSeconds = 0
        durationSeconds = 0
        queue = []
        queueIndex = 0
        videoAudioGroup = nil
        videoSubtitleGroup = nil
        videoAudioOptions = []
        videoSubtitleOptions = []
        videoAudioTrackTitles = []
        videoSubtitleTrackTitles = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func endRemoteSession() {
        guard let remoteSession, let remoteProvider else { return }
        let position = elapsedSeconds
        self.remoteSession = nil
        self.remoteProvider = nil
        Task { await remoteProvider.reportPlaybackStopped(remoteSession, positionSeconds: position) }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard self != nil else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.toggleToPlaying() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard self != nil else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.toggleToPaused() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard self != nil else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.playNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard self != nil else { return .noSuchContent }
            Task { @MainActor [weak self] in self?.playPrevious() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard self != nil, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: position) }
            return .success
        }
    }

    private func toggleToPlaying() { if !isPlaying { togglePlayback() } }
    private func toggleToPaused() { if isPlaying { togglePlayback() } }

    private func updateNowPlayingInfo(refreshArtwork: Bool = false) {
        guard let currentItem else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info.merge([
            MPMediaItemPropertyTitle: currentItem.title,
            MPMediaItemPropertyArtist: currentItem.creator,
            MPMediaItemPropertyAlbumTitle: currentItem.collection,
            MPMediaItemPropertyPlaybackDuration: durationSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]) { _, new in new }
        if refreshArtwork, let url = currentItem.artworkURL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
