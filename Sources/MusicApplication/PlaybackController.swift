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
    @Published public private(set) var currentTrackID: TrackID?
    @Published public private(set) var audioFormatDescription: String?
    @Published public private(set) var volume: Double = 1
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var isLoading = false
    @Published public private(set) var loadingTitle: String?
    private var player: AVAudioPlayer?
    private var items: [(url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?)] = []
    private var originalItems: [(url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?)] = []
    private let preloader = PlaybackPreloader()
    private let loader = PlaybackLoader()
    private var preparedNext: (trackID: TrackID, player: AVAudioPlayer)?
    private var preloadGeneration = 0
    private var loadGeneration = 0
    private var cueEndTimer: Timer?
    private var progressTimer: Timer?
    private let defaultsKey = "MusicLibrary.playbackQueue"

    public override init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey), let queue = try? JSONDecoder().decode(PlaybackQueue.self, from: data) { self.queue = queue }
        super.init()
        configureRemoteCommands()
    }
    public func play(items: [(url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?)], startingAt index: Int) throws {
        guard items.indices.contains(index) else { throw NSError(domain: "MusicLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "No playable queue item was selected."]) }
        self.items = items
        originalItems = items
        queue.replace(with: items.map(\.trackID), startingAt: index)
        persist()
        beginLoading(index: index)
    }
    public func toggle() {
        guard !isLoading else { return }
        guard let player else {
            guard let index = queue.currentIndex else { return }
            beginLoading(index: index)
            return
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            updateProgress()
            updateNowPlayingInfo()
        } else if player.play() {
            isPlaying = true
            updateNowPlayingInfo()
        } else {
            failPlayback(message: "The current audio file could not resume playing.")
        }
    }
    public func stop() {
        loadGeneration += 1
        invalidatePreparedNext()
        cueEndTimer?.invalidate(); cueEndTimer = nil
        progressTimer?.invalidate(); progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        isLoading = false
        loadingTitle = nil
        audioFormatDescription = nil
        currentTime = 0
        duration = 0
        clearNowPlayingInfo()
    }
    public func next() {
        guard queue.skipForward() != nil, let index = queue.currentIndex else { stop(); return }
        persist()
        beginLoading(index: index)
    }
    public func previous() {
        guard queue.previous() != nil, let index = queue.currentIndex else { return }
        persist()
        beginLoading(index: index)
    }
    public func seek(to fraction: Double) {
        guard let player, player.duration > 0 else { return }
        player.currentTime = player.duration * min(max(0, fraction), 1)
        updateProgress()
        updateNowPlayingInfo()
    }
    public func setVolume(_ value: Float) { volume = Double(min(max(0, value), 1)); player?.volume = Float(volume) }
    public func setRepeatMode(_ mode: RepeatMode) { queue.repeatMode = mode; persist() }
    public func toggleShuffle() {
        guard !items.isEmpty else { return }
        let currentID = queue.currentTrackID
        if queue.isShuffled {
            items = originalItems
            queue.trackIDs = items.map(\.trackID)
            queue.currentIndex = currentID.flatMap { id in items.firstIndex(where: { $0.trackID == id }) } ?? 0
            queue.isShuffled = false
        } else {
            let current = currentID.flatMap { id in items.first(where: { $0.trackID == id }) } ?? items[0]
            var remaining = items.filter { $0.trackID != current.trackID }
            remaining.shuffle()
            items = [current] + remaining
            queue.trackIDs = items.map(\.trackID)
            queue.currentIndex = 0
            queue.isShuffled = true
        }
        persist()
        schedulePreload()
    }

    public func restore(items restoredItems: [(url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?)]) {
        guard !queue.trackIDs.isEmpty else { return }
        let itemsByID = Dictionary(uniqueKeysWithValues: restoredItems.map { ($0.trackID, $0) })
        items = queue.trackIDs.compactMap { itemsByID[$0] }
        guard !items.isEmpty else {
            queue.currentIndex = nil
            persist()
            return
        }
        originalItems = items
        queue.trackIDs = items.map(\.trackID)
        queue.currentIndex = min(max(0, queue.currentIndex ?? 0), items.count - 1)
        currentTitle = items[queue.currentIndex ?? 0].title
        currentTrackID = items[queue.currentIndex ?? 0].trackID
        schedulePreload()
    }
    public func dismissError() { errorMessage = nil }
    private func persist() { if let data = try? JSONEncoder().encode(queue) { UserDefaults.standard.set(data, forKey: defaultsKey) } }
    private func failPlayback(message: String) {
        loadGeneration += 1
        invalidatePreparedNext()
        player?.stop()
        player = nil
        isPlaying = false
        isLoading = false
        loadingTitle = nil
        currentTitle = "Playback unavailable"
        currentTrackID = nil
        audioFormatDescription = nil
        currentTime = 0
        duration = 0
        errorMessage = message
        clearNowPlayingInfo()
    }
    private func beginLoading(index: Int) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let preparedPlayer: AVAudioPlayer?
        if let preparedNext, preparedNext.trackID == item.trackID {
            preparedPlayer = preparedNext.player
            self.preparedNext = nil
        } else {
            preparedPlayer = nil
        }
        invalidatePreparedNext()
        loadGeneration += 1
        let generation = loadGeneration

        cueEndTimer?.invalidate(); cueEndTimer = nil
        progressTimer?.invalidate(); progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        isLoading = true
        loadingTitle = item.title
        currentTitle = item.title
        currentTrackID = item.trackID
        audioFormatDescription = nil
        currentTime = 0
        duration = 0
        errorMessage = nil
        clearNowPlayingInfo()

        if let preparedPlayer {
            finishLoading(.success(PreparedAudioPlayer(preparedPlayer)), item: item, generation: generation, retryPreparedFailure: true)
        } else {
            prepare(item: item, generation: generation)
        }
    }

    private func prepare(
        item: (url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?),
        generation: Int
    ) {
        loader.prepare(url: item.url) { [weak self] result in
            Task { @MainActor [weak self] in
                self?.finishLoading(result, item: item, generation: generation, retryPreparedFailure: false)
            }
        }
    }

    private func finishLoading(
        _ result: PreparedAudioResult,
        item: (url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?),
        generation: Int,
        retryPreparedFailure: Bool
    ) {
        guard loadGeneration == generation, queue.currentTrackID == item.trackID else { return }
        switch result {
        case .failure(let message):
            failPlayback(message: message)
        case .success(let prepared):
            let openedPlayer = prepared.player
            if let cueStartMilliseconds = item.cueStartMilliseconds {
                openedPlayer.currentTime = Double(cueStartMilliseconds) / 1_000
            }
            if start(openedPlayer) {
                adopt(openedPlayer, item: item)
            } else if retryPreparedFailure {
                prepare(item: item, generation: generation)
            } else {
                failPlayback(message: "The audio file could not start playing.")
            }
        }
    }

    private func start(_ player: AVAudioPlayer) -> Bool {
        player.delegate = self
        player.volume = Float(volume)
        return player.play()
    }

    private func adopt(_ openedPlayer: AVAudioPlayer, item: (url: URL, trackID: TrackID, title: String, cueStartMilliseconds: Int?, cueEndMilliseconds: Int?)) {
        player?.stop()
        cueEndTimer?.invalidate()
        player = openedPlayer
        currentTitle = item.title
        currentTrackID = item.trackID
        audioFormatDescription = Self.formatDescription(for: item.url, format: openedPlayer.format)
        isPlaying = true
        isLoading = false
        loadingTitle = nil
        duration = openedPlayer.duration
        currentTime = openedPlayer.currentTime
        startProgressUpdates()
        updateNowPlayingInfo()
        scheduleCueEnd(trackID: item.trackID, endMilliseconds: item.cueEndMilliseconds)
        schedulePreload()
    }

    private func scheduleCueEnd(trackID: TrackID, endMilliseconds: Int?) {
        guard let endMilliseconds else { return }
        let remaining = Double(endMilliseconds) / 1_000 - (player?.currentTime ?? 0)
        guard remaining > 0 else { return }
        cueEndTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.queue.currentTrackID == trackID else { return }
                self.player?.stop()
                self.isPlaying = false
                self.next()
            }
        }
    }

    private func startProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateProgress() }
        }
    }

    private func updateProgress() {
        guard let player else {
            currentTime = 0
            duration = 0
            return
        }
        currentTime = player.currentTime
        duration = player.duration
    }

    private func schedulePreload() {
        invalidatePreparedNext()
        guard let currentIndex = queue.currentIndex, let nextIndex = nextIndex(after: currentIndex), items.indices.contains(nextIndex) else { return }
        let currentTrackID = queue.currentTrackID
        let item = items[nextIndex]
        let generation = preloadGeneration
        guard item.url.pathExtension.caseInsensitiveCompare("dsf") != .orderedSame else { return }
        preloader.prepare(url: item.url) { [weak self] prepared in
            guard let prepared else { return }
            Task { @MainActor [weak self] in
                guard let self, self.preloadGeneration == generation, self.queue.currentTrackID == currentTrackID else { return }
                self.preparedNext = (item.trackID, prepared.player)
            }
        }
    }

    private func nextIndex(after index: Int) -> Int? {
        guard !items.isEmpty, queue.repeatMode != .one else { return nil }
        if index + 1 < items.count { return index + 1 }
        return queue.repeatMode == .all ? 0 : nil
    }

    private func invalidatePreparedNext() {
        preloadGeneration += 1
        preparedNext = nil
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { return }
        Task { @MainActor [weak self] in self?.advanceAfterTrackFinished() }
    }

    private func advanceAfterTrackFinished() {
        guard queue.next() != nil, let index = queue.currentIndex else { stop(); return }
        persist()
        beginLoading(index: index)
    }

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

private final class PreparedAudioPlayer: @unchecked Sendable {
    let player: AVAudioPlayer
    init(_ player: AVAudioPlayer) { self.player = player }
}

private enum PreparedAudioResult: @unchecked Sendable {
    case success(PreparedAudioPlayer)
    case failure(String)
}

private final class PlaybackLoader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MusicLibrary.playback-loader", qos: .userInitiated)

    func prepare(url: URL, completion: @escaping @Sendable (PreparedAudioResult) -> Void) {
        queue.async {
            do {
                let playableURL = try DSFPCMTranscoder().playableURL(for: url)
                let player = try AVAudioPlayer(contentsOf: playableURL)
                player.prepareToPlay()
                completion(.success(PreparedAudioPlayer(player)))
            } catch {
                completion(.failure(error.localizedDescription))
            }
        }
    }
}

private final class PlaybackPreloader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MusicLibrary.playback-preload", qos: .userInitiated)

    func prepare(url: URL, completion: @escaping @Sendable (PreparedAudioPlayer?) -> Void) {
        queue.async {
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                completion(nil)
                return
            }
            player.prepareToPlay()
            completion(PreparedAudioPlayer(player))
        }
    }
}
