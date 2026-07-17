import AVFoundation
import AVKit
import Combine
import SwiftUI

@MainActor
final class PlayerController: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false

    private var timeObserver: Any?

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite { self.currentTime = max(0, seconds) }
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    func load(url: URL, duration: Double) {
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        currentTime = 0
        self.duration = max(0, duration)
        isPlaying = false
    }

    func clear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentTime = 0
        duration = 0
        isPlaying = false
    }

    func shutdown() {
        clear()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    func togglePlayback() {
        if player.rate == 0 {
            if duration > 0, currentTime >= duration - 0.2 { seek(to: 0) }
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func seek(to seconds: Double) {
        let value = min(max(0, seconds), duration > 0 ? duration : seconds)
        player.seek(
            to: CMTime(seconds: value, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = value
    }
}

struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFrameSteppingButtons = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}
