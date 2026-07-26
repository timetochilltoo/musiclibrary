import AVFoundation
import Foundation
import MusicReadOnlyClient

@MainActor
public final class CompanionPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var currentTrackID: String?
    @Published public private(set) var currentTitle = "Nothing playing"
    @Published public private(set) var isPlaying = false
    @Published public private(set) var errorMessage: String?

    private var player: AVAudioPlayer?

    public var currentPosition: TimeInterval? { player?.currentTime }

    @discardableResult
    public func play(_ track: ReadOnlyTrack, mappings: [SMBRootMapping], resumingAt position: TimeInterval? = nil) -> Bool {
        guard let url = track.playableURL(using: mappings) else {
            errorMessage = "This track is not available through a mapped SMB root."
            return false
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The mapped audio file is not currently reachable."
            return false
        }
        do {
            let openedPlayer = try AVAudioPlayer(contentsOf: url)
            openedPlayer.delegate = self
            openedPlayer.prepareToPlay()
            if let position, position > 0, position < openedPlayer.duration - 3 { openedPlayer.currentTime = position }
            guard openedPlayer.play() else {
                errorMessage = "The mapped audio file could not start playing."
                return false
            }
            player = openedPlayer
            currentTrackID = track.id
            currentTitle = track.title
            isPlaying = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not play this mapped audio file: \(error.localizedDescription)"
            return false
        }
    }

    public func togglePause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        currentTrackID = nil
        currentTitle = "Nothing playing"
        isPlaying = false
    }

    public func dismissError() { errorMessage = nil }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.stop() }
    }
}
