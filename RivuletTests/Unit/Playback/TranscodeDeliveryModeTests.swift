// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import Rivulet

/// Details on the hls route reports what the server's transcode decision does with each stream,
/// so a quality below Original reads Transcode, as Plex's dashboard does.
@MainActor
final class TranscodeDeliveryModeTests: XCTestCase {

    private func decision(video: String, audio: String) -> PlexTranscodeDecision? {
        let json = #"""
        {"MediaContainer":{"generalDecisionCode":1001,"transcodeDecisionCode":1001,
         "Metadata":[{"Media":[{"videoResolution":"4k","Part":[{"Stream":[
           {"streamType":1,"codec":"hevc","decision":"\#(video)"},
           {"streamType":2,"codec":"aac","decision":"\#(audio)"},
           {"streamType":3,"codec":"srt","decision":"transcode"}]}]}]}]}}
        """#
        return PlexNetworkManager.transcodeDecision(in: Data(json.utf8))
    }

    func test_decisionReadsEachStreamsVerdict() throws {
        let reencoded = try XCTUnwrap(decision(video: "transcode", audio: "copy"))
        XCTAssertEqual(reencoded.video, "transcode")
        XCTAssertEqual(reencoded.audio, "copy")
        XCTAssertTrue(reencoded.verdict.contains("[video transcode hevc 4k, audio copy aac]"))
    }

    func test_aDecisionWithoutStreams_leavesTheGuessInCharge() throws {
        let bare = try XCTUnwrap(PlexNetworkManager.transcodeDecision(
            in: Data(#"{"MediaContainer":{"generalDecisionCode":1001}}"#.utf8)))
        XCTAssertNil(bare.video)
        XCTAssertNil(UniversalPlayerViewModel.deliveryMode(bare.video))
    }

    private func master(_ attributes: String) -> String {
        "#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,\(attributes)\nsession/s/base/index.m3u8\n"
    }

    func test_streamBandwidth_readsTheVariant_notItsAverage() {
        XCTAssertEqual(UniversalPlayerViewModel.streamBandwidth(
            masterPlaylist: master("AVERAGE-BANDWIDTH=6000000,BANDWIDTH=7614000,RESOLUTION=1920x1080")), 7_614_000)
        XCTAssertEqual(UniversalPlayerViewModel.streamBandwidth(
            masterPlaylist: master("RESOLUTION=1920x1080,BANDWIDTH=20000000")), 20_000_000)
    }

    func test_streamBandwidth_ignoresAPlaceholderOrNone() {
        XCTAssertNil(UniversalPlayerViewModel.streamBandwidth(masterPlaylist: master("BANDWIDTH=1,RESOLUTION=3840x2160")))
        XCTAssertNil(UniversalPlayerViewModel.streamBandwidth(masterPlaylist: master("RESOLUTION=3840x2160")))
    }

    private var movie: PlexMetadata {
        var movie = PlexMetadata()
        movie.Media = [PlexMedia(
            id: 1, duration: 7_200_000, bitrate: 64_195, width: 3840, height: 2160,
            aspectRatio: 1.78, audioChannels: 6, audioCodec: "dca", videoCodec: "hevc",
            videoResolution: "4k", container: "mkv", videoFrameRate: "24p", Part: nil)]
        return movie
    }

    private func bitrateRows(video: StreamingModeInfo.Mode, transcode: Int?) -> [String: String] {
        let modes = StreamingModeInfo(video: video, audio: .transcode, subtitles: .directPlay)
        let rows = PlayerDetailsPaneView.mediaSections(metadata: movie, modes: modes, transcodeBitrate: transcode)[0].rows
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            row.label.flatMap { $0.contains("Bitrate") ? ($0, row.value) : nil }
        })
    }

    /// A 64 Mbps file transcoded to 20 Mbps shows both, Original first, as Plex's dashboard does.
    func test_aTranscode_showsTheOriginalAndTheTranscodedBitrate() {
        let modes = StreamingModeInfo(video: .transcode, audio: .transcode, subtitles: .directPlay)
        let labels = PlayerDetailsPaneView.mediaSections(metadata: movie, modes: modes, transcodeBitrate: 20_000_000)[0]
            .rows.compactMap(\.label).filter { $0.contains("Bitrate") }
        XCTAssertEqual(labels, ["Original Bitrate", "Transcoded Bitrate"])
        XCTAssertEqual(bitrateRows(video: .transcode, transcode: 20_000_000), [
            "Original Bitrate": PlayerInfoSheetStyle.bitrate(64_195_000),
            "Transcoded Bitrate": PlayerInfoSheetStyle.bitrate(20_000_000)])
    }

    func test_aTranscodeWithNoStreamRate_showsOnlyTheOriginal() {
        XCTAssertEqual(bitrateRows(video: .transcode, transcode: nil),
                       ["Original Bitrate": PlayerInfoSheetStyle.bitrate(64_195_000)])
    }

    func test_noTranscode_showsOnlyTheFilesBitrate_evenIfARateIsGiven() {
        for mode in [StreamingModeInfo.Mode.directPlay, .directStream] {
            XCTAssertEqual(bitrateRows(video: mode, transcode: 20_000_000),
                           ["Bitrate": PlayerInfoSheetStyle.bitrate(64_195_000)], "\(mode)")
        }
    }

    func test_verdictsMapToDetailsModes() {
        XCTAssertEqual(UniversalPlayerViewModel.deliveryMode("transcode"), .transcode)
        XCTAssertEqual(UniversalPlayerViewModel.deliveryMode("copy"), .directStream)
        XCTAssertNil(UniversalPlayerViewModel.deliveryMode("burn"))
        XCTAssertNil(UniversalPlayerViewModel.deliveryMode(nil))
    }
}
