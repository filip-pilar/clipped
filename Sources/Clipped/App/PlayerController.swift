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

    var timeUpdateHandler: ((Double) -> Void)?

    private var timeObserver: Any?
    private var isShowingTemporaryFrame = false
    private var isSeekingInitialPosition = false
    private var initialSeekID = UUID()

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = max(0, seconds)
                    if !self.isShowingTemporaryFrame && !self.isSeekingInitialPosition {
                        self.timeUpdateHandler?(self.currentTime)
                    }
                }
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    var isReady: Bool { player.currentItem != nil }

    func configure(duration: Double) {
        self.duration = max(0, duration)
    }

    func load(url: URL, duration: Double, initialTime: Double = 0) {
        player.pause()
        isSeekingInitialPosition = true
        initialSeekID = UUID()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        self.duration = max(0, duration)
        currentTime = clamped(initialTime)
        let target = currentTime
        seekInitialPosition(to: target, id: initialSeekID, attemptsRemaining: 30)
        isShowingTemporaryFrame = false
        isPlaying = false
    }

    func clear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentTime = 0
        duration = 0
        isShowingTemporaryFrame = false
        isSeekingInitialPosition = false
        initialSeekID = UUID()
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
        guard isReady else { return }
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
        let value = clamped(seconds)
        isShowingTemporaryFrame = false
        player.seek(
            to: CMTime(seconds: value, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = value
        timeUpdateHandler?(value)
    }

    @discardableResult
    func pause() -> Bool {
        let wasPlaying = player.rate != 0
        player.pause()
        isPlaying = false
        return wasPlaying
    }

    func resume() {
        guard isReady else { return }
        player.play()
        isPlaying = true
    }

    func showBoundaryFrame(at seconds: Double) {
        guard isReady else { return }
        isShowingTemporaryFrame = true
        let value = clamped(seconds)
        player.seek(
            to: CMTime(seconds: value, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = value
    }

    func restorePreview(to seconds: Double, resumePlayback: Bool) {
        guard isReady else {
            isShowingTemporaryFrame = false
            return
        }
        let value = clamped(seconds)
        player.seek(
            to: CMTime(seconds: value, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = value
        isShowingTemporaryFrame = false
        if resumePlayback { resume() }
    }

    private func clamped(_ seconds: Double) -> Double {
        min(max(0, seconds), duration > 0 ? duration : max(0, seconds))
    }

    private func seekInitialPosition(to target: Double, id: UUID, attemptsRemaining: Int) {
        guard id == initialSeekID, isSeekingInitialPosition else { return }
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor in
                guard let self, id == self.initialSeekID, self.isSeekingInitialPosition else { return }
                if finished {
                    self.isSeekingInitialPosition = false
                    self.currentTime = target
                    self.timeUpdateHandler?(target)
                } else if attemptsRemaining > 0 {
                    try? await Task.sleep(for: .milliseconds(100))
                    self.seekInitialPosition(
                        to: target,
                        id: id,
                        attemptsRemaining: attemptsRemaining - 1
                    )
                } else {
                    self.isSeekingInitialPosition = false
                    self.currentTime = max(0, self.player.currentTime().seconds)
                    self.timeUpdateHandler?(self.currentTime)
                }
            }
        }
    }
}

struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.showsFrameSteppingButtons = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}
