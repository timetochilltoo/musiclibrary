import AVFoundation
import Foundation
import MusicDomain

@MainActor
public final class PlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var queue = PlaybackQueue()
    @Published public private(set) var isPlaying = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var currentTitle = "Nothing playing"
    @Published public private(set) var volume: Double = 1
    private var player: AVAudioPlayer?
    private var items: [(url: URL, trackID: TrackID, title: String)] = []
    private let defaultsKey = "MusicLibrary.playbackQueue"

    public override init() { if let data = UserDefaults.standard.data(forKey: defaultsKey), let queue = try? JSONDecoder().decode(PlaybackQueue.self, from: data) { self.queue = queue }; super.init() }
    public func play(items: [(url: URL, trackID: TrackID, title: String)], startingAt index: Int) throws {
        guard items.indices.contains(index) else { throw NSError(domain: "MusicLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "No playable queue item was selected."]) }
        self.items = items; queue.replace(with: items.map(\.trackID), startingAt: index); persist(); try loadCurrentAndPlay()
    }
    public func toggle() { guard let player else { return }; if player.isPlaying { player.pause(); isPlaying = false } else { player.play(); isPlaying = true } }
    public func stop() { player?.stop(); isPlaying = false }
    public func next() { guard queue.next() != nil, let index = queue.currentIndex else { stop(); return }; persist(); try? load(index: index) }
    public func previous() { guard queue.previous() != nil, let index = queue.currentIndex else { return }; persist(); try? load(index: index) }
    public func seek(to fraction: Double) { guard let player, player.duration > 0 else { return }; player.currentTime = player.duration * min(max(0, fraction), 1) }
    public func setVolume(_ value: Float) { volume = Double(min(max(0, value), 1)); player?.volume = Float(volume) }
    public func setRepeatMode(_ mode: RepeatMode) { queue.repeatMode = mode; persist() }
    public func shuffle() { var generator = SystemRandomNumberGenerator(); queue.shuffle(using: &generator); persist() }
    public func dismissError() { errorMessage = nil }
    private func persist() { if let data = try? JSONEncoder().encode(queue) { UserDefaults.standard.set(data, forKey: defaultsKey) } }
    private func loadCurrentAndPlay() throws { guard let index = queue.currentIndex else { return }; try load(index: index) }
    private func load(index: Int) throws { guard items.indices.contains(index) else { return }; let item = items[index]; player = try AVAudioPlayer(contentsOf: item.url); player?.delegate = self; player?.prepareToPlay(); player?.play(); currentTitle = item.title; isPlaying = true }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { guard flag else { return }; Task { @MainActor [weak self] in self?.next() } }
}
