import AVKit
import SwiftUI

struct NowPlayingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var playback
    @Binding var showingFullscreenVideo: Bool

    var body: some View {
        VStack(spacing: 17) {
            HStack {
                Text("NOW PLAYING").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.3).foregroundStyle(MediaPalette.muted)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(.white).padding(9).background(MediaPalette.surface, in: Circle()) }
                    .accessibilityLabel("Close now playing")
            }
            if let item = playback.currentItem {
                if item.kind == .video {
                    VideoPlayer(player: playback.player)
                        .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .topTrailing) {
                            Button { showingFullscreenVideo = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    .padding(10).background(.black.opacity(0.65), in: Circle())
                            }
                            .accessibilityLabel("Expand video")
                            .padding(9)
                        }
                    videoTrackControls
                }
                else { MediaArtwork(kind: item.kind, size: 180, artworkURL: item.artworkURL).frame(maxWidth: .infinity).padding(.vertical, 13) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                    Text(item.creator.isEmpty ? "\(item.kind.title) · \(item.origin == "Jellyfin" ? "Jellyfin server" : "Local library")" : item.creator)
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(MediaPalette.muted)
                }
                Slider(value: Binding(get: { playback.elapsedSeconds }, set: { playback.seek(to: $0) }), in: 0...max(playback.durationSeconds, 1))
                    .tint(MediaPalette.accent)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue(Text("\(timeLabel(playback.elapsedSeconds)) of \(timeLabel(playback.durationSeconds))"))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: playback.seek(to: playback.elapsedSeconds + 15)
                        case .decrement: playback.seek(to: max(0, playback.elapsedSeconds - 15))
                        @unknown default: break
                        }
                    }
                HStack { Text(timeLabel(playback.elapsedSeconds)); Spacer(); Text(timeLabel(playback.durationSeconds)) }
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(MediaPalette.muted)
                HStack(spacing: 38) {
                    Button { playback.playPrevious() } label: { Image(systemName: "backward.end.fill") }
                        .accessibilityLabel("Previous item")
                    Button { playback.seek(to: max(0, playback.elapsedSeconds - 15)) } label: { Image(systemName: "gobackward.15") }
                        .accessibilityLabel("Rewind 15 seconds")
                    Button { playback.togglePlayback() } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 21, weight: .bold))
                            .foregroundStyle(MediaPalette.background).frame(width: 60, height: 60).background(MediaPalette.accent, in: Circle())
                    }
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                    Button { playback.seek(to: playback.elapsedSeconds + 15) } label: { Image(systemName: "goforward.15") }
                        .accessibilityLabel("Forward 15 seconds")
                    Button { playback.playNext() } label: { Image(systemName: "forward.end.fill") }
                        .accessibilityLabel("Next item")
                }
                .font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                UpNextQueuePanel(playback: playback)
                if let error = playback.errorMessage { Text(error).font(.system(size: 12, design: .rounded)).foregroundStyle(.orange) }
            }
            Spacer(minLength: 0)
        }
        .padding(20).background(MediaPalette.background.ignoresSafeArea())
        .presentationDetents([.medium, .large]).preferredColorScheme(.dark)
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let wholeSeconds = Int(seconds)
        let minutes = wholeSeconds / 60
        let secondsPart = String(format: "%02d", wholeSeconds % 60)
        if minutes >= 60 {
            return "\(minutes / 60):\(String(format: "%02d", minutes % 60)):\(secondsPart)"
        }
        return "\(minutes):\(secondsPart)"
    }

    @ViewBuilder
    private var videoTrackControls: some View {
        if playback.videoAudioTrackTitles.count > 1 || !playback.videoSubtitleTrackTitles.isEmpty {
            HStack(spacing: 10) {
                if playback.videoAudioTrackTitles.count > 1 {
                    Menu {
                        ForEach(Array(playback.videoAudioTrackTitles.enumerated()), id: \.offset) { index, title in
                            Button(title) { playback.selectVideoAudioTrack(index) }
                        }
                    } label: {
                        Label("Audio", systemImage: "speaker.wave.2").font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
                if !playback.videoSubtitleTrackTitles.isEmpty {
                    Menu {
                        Button("Off") { playback.selectVideoSubtitleTrack(nil) }
                        ForEach(Array(playback.videoSubtitleTrackTitles.enumerated()), id: \.offset) { index, title in
                            Button(title) { playback.selectVideoSubtitleTrack(index) }
                        }
                    } label: {
                        Label("Subtitles", systemImage: "captions.bubble").font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                }
                Spacer()
            }
            .foregroundStyle(MediaPalette.accent)
        }
    }
}

struct FullScreenVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: playback.player).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(.black.opacity(0.62), in: Circle())
                    }
                    .accessibilityLabel("Close video player")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(playback.currentItem?.title ?? "Video")
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                        Text(playback.currentItem?.origin == "Jellyfin" ? "Jellyfin server" : "Local library")
                            .font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.72))
                    }
                    Spacer(minLength: 0)
                    fullscreenTrackControls
                }
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 24)
                .background(LinearGradient(colors: [.black.opacity(0.78), .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
                if let error = playback.errorMessage {
                    Text(error).font(.system(size: 12, design: .rounded)).foregroundStyle(.white)
                        .padding(12).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 28)
                }
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var fullscreenTrackControls: some View {
        HStack(spacing: 8) {
            if playback.videoAudioTrackTitles.count > 1 {
                Menu {
                    ForEach(Array(playback.videoAudioTrackTitles.enumerated()), id: \.offset) { index, title in
                        Button(title) { playback.selectVideoAudioTrack(index) }
                    }
                } label: {
                    Image(systemName: "speaker.wave.2").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 38, height: 38).background(.black.opacity(0.62), in: Circle())
                }
                .accessibilityLabel("Audio tracks")
            }
            if !playback.videoSubtitleTrackTitles.isEmpty {
                Menu {
                    Button("Off") { playback.selectVideoSubtitleTrack(nil) }
                    ForEach(Array(playback.videoSubtitleTrackTitles.enumerated()), id: \.offset) { index, title in
                        Button(title) { playback.selectVideoSubtitleTrack(index) }
                    }
                } label: {
                    Image(systemName: "captions.bubble").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 38, height: 38).background(.black.opacity(0.62), in: Circle())
                }
                .accessibilityLabel("Subtitle tracks")
            }
        }
    }
}

struct UpNextQueuePanel: View {
    let playback: PlaybackCoordinator
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Label("Up Next", systemImage: "list.bullet")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    Text("\(playback.upcomingItems.count)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(MediaPalette.muted)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(MediaPalette.muted)
                }
                .padding(.top, 5).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Up Next, \(playback.upcomingItems.count) queued items")
            .accessibilityHint(isExpanded ? "Collapse queue" : "Expand queue")
            if isExpanded {
                if playback.upcomingItems.isEmpty {
                    Text("Nothing queued after this item.")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(MediaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(Array(playback.upcomingItems.enumerated()), id: \.offset) { offset, queuedItem in
                                HStack(spacing: 9) {
                                    Button {
                                        playback.playQueuedItem(at: playback.currentQueueIndex + offset + 1)
                                    } label: {
                                        HStack(spacing: 9) {
                                            MediaArtwork(kind: queuedItem.kind, size: 38, artworkURL: queuedItem.artworkURL)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(queuedItem.title).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                                                Text(queuedItem.creator.isEmpty ? queuedItem.kind.title : queuedItem.creator)
                                                    .font(.system(size: 9, design: .rounded)).foregroundStyle(MediaPalette.muted).lineLimit(1)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Play \(queuedItem.title)")
                                    Menu {
                                        if offset > 0 {
                                            Button("Move to next", systemImage: "arrow.up.to.line") {
                                                playback.moveUpcomingItem(from: offset, to: 0)
                                            }
                                            Button("Move up", systemImage: "arrow.up") {
                                                playback.moveUpcomingItem(from: offset, to: offset - 1)
                                            }
                                        }
                                        if offset + 1 < playback.upcomingItems.count {
                                            Button("Move down", systemImage: "arrow.down") {
                                                playback.moveUpcomingItem(from: offset, to: offset + 1)
                                            }
                                        }
                                        Button("Remove from queue", systemImage: "trash", role: .destructive) {
                                            playback.removeUpcomingItem(at: offset)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(MediaPalette.muted).frame(width: 30, height: 38)
                                    }
                                    .accessibilityLabel("Queue actions for \(queuedItem.title)")
                                }
                                .padding(7).background(MediaPalette.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
    }
}

