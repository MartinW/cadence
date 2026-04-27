import AVFoundation
import Foundation
import Observation

/// Tiny wrapper around AVAudioPlayer that:
/// - Configures the audio session for playback (so it ducks other audio
///   politely and continues if the screen locks).
/// - Holds onto the player instance for the lifetime of playback (otherwise
///   ARC kills it mid-track).
/// - Exposes an `isPlaying` flag for the UI to observe.
@MainActor
@Observable
final class AudioPlayer: NSObject {
    private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var sessionConfigured = false

    func play(data: Data) throws {
        try ensureSession()
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        player.play()
        self.player = player
        isPlaying = true
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func ensureSession() throws {
        guard !sessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
        sessionConfigured = true
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        // AVAudioPlayer callbacks fire off the main actor; bounce back so we
        // can flip the @Observable state safely.
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}
