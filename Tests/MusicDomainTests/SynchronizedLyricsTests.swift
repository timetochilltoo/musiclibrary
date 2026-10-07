import Foundation
import Testing
@testable import MusicDomain

@Suite("Line-timed lyrics")
struct SynchronizedLyricsTests {
    @Test("Basic timestamps, fractions, metadata and repeated stamps preserve all lines")
    func parsing() throws {
        let value = try #require(SynchronizedLyrics(text: "\u{FEFF}[ti:Fixture]\r\n[00:03.123]Third\n[00:01][00:02.50]Repeated\n[00:01.0]Translation\n[00:04.12]\n[00:05.1]End"))
        #expect(value.cues.map(\.milliseconds) == [1_000, 2_500, 3_123, 4_120, 5_100])
        #expect(value.cues.map(\.text) == ["Repeated\nTranslation", "Repeated", "Third", "", "End"])
        #expect(value.cues.map(\.id) == [0, 1, 2, 3, 4])
    }

    @Test("Signed global offsets advance/delay safely, including zero clamping")
    func offsets() throws {
        let advance = try #require(SynchronizedLyrics(text: "[00:00.25]Opening\n[00:01.50]Next\n[offset:+500]"))
        #expect(advance.cues.map(\.milliseconds) == [0, 1_000])
        let delay = try #require(SynchronizedLyrics(text: "[offset:-500]\n[00:01]Line"))
        #expect(delay.cues[0].milliseconds == 1_500)
        #expect(SynchronizedLyrics(text: "[offset:\(Int.min)]\n[00:01]Overflow") == nil)
    }

    @Test("Malformed, mixed, unknown and enhanced documents fall back as a whole")
    func rawFallback() {
        let invalid = ["", "Plain lyrics", "[ti:Only metadata]", "[00:60]Bad seconds", "[0:1]Bad seconds width",
                       "[00:01.]Bad fraction", "[00:01.1234]Too precise", "[00:01:02]Hours unsupported",
                       "[00:01]Valid\nUntimed line", "[00:01]Valid\n[bad]Bad", "[00:01]<00:01.1>Words",
                       "[offset:abc]\n[00:01]Line", "[offset:1]\n[offset:2]\n[00:01]Line",
                       "[offset:1]Trailing text\n[00:01]Line", "[unknown:value]\n[00:01]Line",
                       "[999999999999999999999999:00]Overflow", "[\(Int.max):00]Overflow",
                       "[٠٠:٠١]Non-ASCII digits"]
        for text in invalid { #expect(SynchronizedLyrics(text: text) == nil, "\(text)") }
        // Brackets within the lyric body are literal text, not a reason to drop a valid document.
        #expect(SynchronizedLyrics(text: "[00:01]Literal [chorus] text") != nil)
    }

    @Test("Active lookup follows forward/backward seek and clears before first cue or invalid clock")
    func seek() throws {
        let value = try #require(SynchronizedLyrics(text: "[00:01]First\n[00:02]\n[00:03]Last"))
        #expect(value.activeCueIndex(at: 0) == nil)
        #expect(value.activeCueIndex(at: 1) == 0)
        #expect(value.activeCueIndex(at: 2) == 1) // Blank cue clears the previous words.
        #expect(value.activeCueIndex(at: 50) == 2)
        #expect(value.activeCueIndex(at: 1.5) == 0) // Seek backward, not an incremental cursor.
        #expect(value.activeCueIndex(at: 0.5) == nil)
        for time: Double? in [nil, -.infinity, .infinity, .nan, -1] { #expect(value.activeCueIndex(at: time) == nil) }
    }

    @Test("CUE lyrics use track-relative time and stop highlighting outside segment bounds")
    func cueClock() throws {
        let value = try #require(SynchronizedLyrics(text: "[00:01]First\n[00:05]Next"))
        let position = LyricsPlaybackClock.time(sourceTime: 200, cueStartMilliseconds: 195_000, cueEndMilliseconds: 210_000)
        #expect(position == 5 && value.activeCueIndex(at: position) == 1)
        let backward = LyricsPlaybackClock.time(sourceTime: 196, cueStartMilliseconds: 195_000, cueEndMilliseconds: 210_000)
        #expect(backward == 1 && value.activeCueIndex(at: backward) == 0)
        #expect(LyricsPlaybackClock.time(sourceTime: 195, cueStartMilliseconds: 195_000, cueEndMilliseconds: nil) == 0)
        #expect(LyricsPlaybackClock.time(sourceTime: 194, cueStartMilliseconds: 195_000, cueEndMilliseconds: 210_000) == nil)
        #expect(LyricsPlaybackClock.time(sourceTime: 210, cueStartMilliseconds: 195_000, cueEndMilliseconds: 210_000) == nil)
        #expect(LyricsPlaybackClock.time(sourceTime: 1, cueStartMilliseconds: nil, cueEndMilliseconds: nil) == 1)
        #expect(LyricsPlaybackClock.time(sourceTime: 200, cueStartMilliseconds: 195_000, cueEndMilliseconds: 100_000) == nil)
        #expect(LyricsPlaybackClock.time(sourceTime: .nan, cueStartMilliseconds: nil, cueEndMilliseconds: nil) == nil)
    }
}
