import SwiftUI
import MusicDomain
import MusicApplication

struct NowPlayingLyricsView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var playback: PlaybackController
    @StateObject private var model = NowPlayingLyricsModel()
    @State private var selectedEntryID: UUID?
    @State private var trackForEditor: Track?
    @State private var retry = 0

    private struct Request: Hashable {
        let trackID: TrackID?
        let revision: Int64
        let retry: Int
    }
    private var request: Request { .init(trackID: playback.currentTrackID, revision: library.catalogueRevision, retry: retry) }
    private var snapshot: NowPlayingLyrics? {
        guard model.revision == library.catalogueRevision,
              model.snapshot?.track.id == playback.currentTrackID else { return nil }
        return model.snapshot
    }
    private var entry: LyricsEntry? {
        snapshot?.entries.first { $0.id == selectedEntryID } ?? snapshot?.entries.first
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Lyrics", systemImage: "quote.bubble").font(.headline)
                    Spacer()
                    if let snapshot {
                        Button(snapshot.entries.isEmpty ? "Add Lyrics" : "Manage Lyrics") { trackForEditor = snapshot.track }
                    }
                }
                if playback.currentTrackID == nil {
                    Text("Select a track to view lyrics.").foregroundStyle(.secondary)
                } else if model.isLoading || model.revision != library.catalogueRevision || model.trackID != playback.currentTrackID {
                    ProgressView("Loading saved lyrics…")
                } else if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Retry") { retry += 1 }
                } else if let snapshot {
                    if snapshot.entries.isEmpty {
                        Text(snapshot.track.isInstrumental == true ? "Instrumental track" : "No lyrics saved")
                            .font(.headline)
                        Text(snapshot.track.isInstrumental == true ? "Lyrics are optional for this track." : "Add lyrics you type or paste on this Mac.")
                            .foregroundStyle(.secondary)
                    } else {
                        if snapshot.entries.count > 1 {
                            Picker("Version", selection: Binding(get: { entry?.id }, set: { selectedEntryID = $0 })) {
                                ForEach(Array(snapshot.entries.enumerated()), id: \.element.id) { index, value in
                                    Text("\(value.language ?? "Unspecified language") · \(value.kind == .plain ? "Plain" : "LRC") · \(index + 1)").tag(Optional(value.id))
                                }
                            }
                        }
                        if let entry {
                            SavedLyricsContent(entry: entry, timeline: model.timelines[entry.id], time: playback.lyricsTime)
                                .id(entry.id)
                        }
                    }
                } else {
                    Text("Track details unavailable.").foregroundStyle(.secondary)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: request) {
            let key = request
            await model.load(trackID: key.trackID, revision: key.revision) { try await library.nowPlayingLyrics(trackID: $0) }
        }
        .onChange(of: playback.currentTrackID) { _, _ in selectedEntryID = nil }
        .sheet(item: $trackForEditor) { track in LyricsEditor(library: library, track: track) }
    }
}

private struct SavedLyricsContent: View {
    let entry: LyricsEntry
    let timeline: SynchronizedLyrics?
    let time: TimeInterval?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showOriginal = false
    @State private var follow = true
    private var activeIndex: Int? { timeline?.activeCueIndex(at: time) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let timeline {
                HStack {
                    if !showOriginal {
                        Toggle("Follow playback", isOn: $follow).toggleStyle(.switch).controlSize(.small)
                    }
                    Spacer()
                    Button(showOriginal ? "Timed Lyrics" : "Original LRC") { showOriginal.toggle() }
                }
                if showOriginal {
                    rawText
                } else {
                    Text("Line timing · relative to this track · no word-level timing")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(timeline.cues) { cue in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold()).frame(width: 10)
                                            .opacity(activeIndex == cue.id ? 1 : 0)
                                            .accessibilityHidden(true)
                                        Text(cue.time.formatted(.number.precision(.fractionLength(1))) + "s")
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                            .frame(width: 58, alignment: .trailing)
                                        Text(cue.text.isEmpty ? "…" : cue.text)
                                            .fontWeight(activeIndex == cue.id ? .semibold : .regular)
                                            .foregroundStyle(activeIndex == cue.id ? Color.accentColor : Color.primary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(8)
                                    .background(activeIndex == cue.id ? Color.accentColor.opacity(0.12) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityValue(activeIndex == cue.id ? "Current lyric" : "")
                                    .accessibilityElement(children: .combine)
                                    .id(cue.id)
                                }
                            }.padding(8)
                        }
                        .onAppear { scroll(proxy) }
                        .onChange(of: activeIndex) { _, _ in scroll(proxy) }
                        .onChange(of: follow) { _, _ in scroll(proxy) }
                    }.frame(minHeight: 100, maxHeight: 260)
                }
            } else {
                if entry.kind == .synchronized {
                    Text("Showing original LRC: timing is missing, malformed or unsupported.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                rawText
            }
        }
    }

    private var rawText: some View {
        ScrollView {
            Text(entry.text).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }.frame(minHeight: 100, maxHeight: 260)
    }
    private func scroll(_ proxy: ScrollViewProxy) {
        guard follow, let activeIndex else { return }
        if reduceMotion { proxy.scrollTo(activeIndex, anchor: .center) }
        else { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(activeIndex, anchor: .center) } }
    }
}
