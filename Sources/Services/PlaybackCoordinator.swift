import AVFoundation
import Observation

@MainActor
@Observable
final class PlaybackCoordinator {
    let player = AVPlayer()
    private(set) var currentItem: LibraryItem?
    private(set) var isPlaying = false
    private(set) var elapsedSeconds: Double = 0
    private(set) var durationSeconds: Double = 0
    private(set) var errorMessage: String?

    func play(_ item: LibraryItem) {
        guard item.kind == .music || item.kind == .video else { return }
        guard FileManager.default.fileExists(atPath: item.localURL.path) else {
            errorMessage = "This file is no longer available in the app library. You can remove it and import it again."
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "Audio playback could not start: \(error.localizedDescription)"
            return
        }

        currentItem = item
        item.lastOpenedAt = .now
        player.replaceCurrentItem(with: AVPlayerItem(url: item.localURL))
        if item.progressSeconds > 0 {
            player.seek(to: CMTime(seconds: item.progressSeconds, preferredTimescale: 600))
        }
        player.play()
        isPlaying = true
        errorMessage = nil
        refreshProgress()
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
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        isPlaying = false
        elapsedSeconds = 0
        durationSeconds = 0
    }
}
