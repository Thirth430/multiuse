import AVFoundation
import Observation

@MainActor
@Observable
final class PlaybackCoordinator {
    let player = AVPlayer()
    private(set) var currentItem: MediaLibraryRecord?
    private(set) var isPlaying = false
    private(set) var elapsedSeconds: Double = 0
    private(set) var durationSeconds: Double = 0
    private(set) var errorMessage: String?
    @ObservationIgnored private var remoteSession: JellyfinPlaybackSession?
    @ObservationIgnored private var remoteProvider: JellyfinProvider?
    @ObservationIgnored private var lastRemoteProgressReport = Date.distantPast

    func play(_ item: MediaLibraryRecord) {
        guard item.kind == .music || item.kind == .video else { return }
        endRemoteSession()
        guard FileManager.default.fileExists(atPath: item.localURL.path) else {
            errorMessage = "This file is no longer available in the app library. You can remove it and import it again."
            return
        }

        start(item, from: item.localURL, at: item.progressSeconds)
    }

    func playRemote(
        _ item: MediaLibraryRecord,
        session: JellyfinPlaybackSession,
        provider: JellyfinProvider
    ) {
        guard item.kind == .music || item.kind == .video else { return }
        endRemoteSession()
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
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        if position > 0 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        errorMessage = nil
        refreshProgress()
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
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        elapsedSeconds = seconds
        currentItem?.progressSeconds = seconds
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
    }

    private func endRemoteSession() {
        guard let remoteSession, let remoteProvider else { return }
        let position = elapsedSeconds
        self.remoteSession = nil
        self.remoteProvider = nil
        Task { await remoteProvider.reportPlaybackStopped(remoteSession, positionSeconds: position) }
    }
}
