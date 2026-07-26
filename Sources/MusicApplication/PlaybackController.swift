import AVFoundation
import Foundation
import MusicDomain
#if canImport(MediaPlayer)
import MediaPlayer
#endif

@MainActor
public final class PlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var queue = PlaybackQueue()
    @Published public private(set) var isPlaying = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var currentTitle = "Nothing playing"
    @Published public private(set) var audioFormatDescription: String?
    @Published public private(set) var volume: Double = 1
    private var player: AVAudioPlayer?
    private var items: [(url: URL, trackID: TrackID, title: String)] = []
    private let defaultsKey = "MusicLibrary.playbackQueue"

    public override init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey), let queue = try? JSONDecoder().decode(PlaybackQueue.self, from: data) { self.queue = queue }
        super.init()
        configureRemoteCommands()
    }
    public func play(items: [(url: URL, trackID: TrackID, title: String)], startingAt index: Int) throws {
        guard items.indices.contains(index) else { throw NSError(domain: "MusicLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "No playable queue item was selected."]) }
        self.items = items; queue.replace(with: items.map(\.trackID), startingAt: index); persist(); try loadCurrentAndPlay()
    }
    public func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            updateNowPlayingInfo()
        } else if player.play() {
            isPlaying = true
            updateNowPlayingInfo()
        } else {
            failPlayback(message: "The current audio file could not resume playing.")
        }
    }
    public func stop() {
        player?.stop()
        isPlaying = false
        audioFormatDescription = nil
        clearNowPlayingInfo()
    }
    public func next() {
        guard queue.next() != nil, let index = queue.currentIndex else { stop(); return }
        persist()
        loadOrReport(index: index)
    }
    public func previous() {
        guard queue.previous() != nil, let index = queue.currentIndex else { return }
        persist()
        loadOrReport(index: index)
    }
    public func seek(to fraction: Double) {
        guard let player, player.duration > 0 else { return }
        player.currentTime = player.duration * min(max(0, fraction), 1)
        updateNowPlayingInfo()
    }
    public func setVolume(_ value: Float) { volume = Double(min(max(0, value), 1)); player?.volume = Float(volume) }
    public func setRepeatMode(_ mode: RepeatMode) { queue.repeatMode = mode; persist() }
    public func shuffle() { var generator = SystemRandomNumberGenerator(); queue.shuffle(using: &generator); persist() }
    public func dismissError() { errorMessage = nil }
    private func persist() { if let data = try? JSONEncoder().encode(queue) { UserDefaults.standard.set(data, forKey: defaultsKey) } }
    private func loadCurrentAndPlay() throws { guard let index = queue.currentIndex else { return }; try load(index: index) }
    private func loadOrReport(index: Int) {
        do {
            try load(index: index)
        } catch {
            failPlayback(message: error.localizedDescription)
        }
    }
    private func failPlayback(message: String) {
        player?.stop()
        player = nil
        isPlaying = false
        currentTitle = "Playback unavailable"
        audioFormatDescription = nil
        errorMessage = message
        clearNowPlayingInfo()
    }
    private func load(index: Int) throws {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let openedPlayer = try AVAudioPlayer(contentsOf: item.url)
        openedPlayer.delegate = self
        openedPlayer.prepareToPlay()
        guard openedPlayer.play() else {
            throw NSError(domain: "MusicLibrary", code: 2, userInfo: [NSLocalizedDescriptionKey: "The audio file could not start playing."])
        }
        player = openedPlayer
        currentTitle = item.title
        audioFormatDescription = Self.formatDescription(for: item.url, format: openedPlayer.format)
        isPlaying = true
        updateNowPlayingInfo()
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { guard flag else { return }; Task { @MainActor [weak self] in self?.next() } }

    private static func formatDescription(for url: URL, format: AVAudioFormat) -> String {
        let container = url.pathExtension.isEmpty ? "Audio" : url.pathExtension.uppercased()
        let kilohertz = format.sampleRate / 1_000
        let rate = String(format: kilohertz.rounded() == kilohertz ? "%.0f kHz" : "%.1f kHz", kilohertz)
        let channels = format.channelCount == 1 ? "mono" : "\(format.channelCount) ch"
        return "\(container) · \(rate) · \(channels)"
    }

    #if canImport(MediaPlayer)
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playFromRemoteCommand() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pauseFromRemoteCommand() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }

    private func playFromRemoteCommand() {
        guard let player, !player.isPlaying else { return }
        if player.play() { isPlaying = true; updateNowPlayingInfo() }
    }

    private func pauseFromRemoteCommand() {
        guard let player, player.isPlaying else { return }
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let player else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0
        ]
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    #else
    private func configureRemoteCommands() {}
    private func updateNowPlayingInfo() {}
    private func clearNowPlayingInfo() {}
    #endif
}
