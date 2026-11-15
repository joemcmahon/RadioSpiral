//
//  MetadataLogTests.swift
//  ConfigClientTests
//
//  Task-44: a message the parser can't read, and one it ignores, leave a record that exists in
//  release builds too (the unified log), so a listener's report can be checked against it.
//  The empty heartbeat the server sends every ping interval is normal and records nothing.
//
//  Records go to MetadataLog.sink, which these tests replace, so nothing is written to the real log.
//

import XCTest
@testable import RadioSpiral

final class MetadataLogTests: XCTestCase {

    private var records: [MetadataLog.Record] = []
    private let shortCode = ConnectMessageFixture.shortCode

    override func setUp() {
        super.setUp()
        records = []
        MetadataLog.sink = { [unowned self] record in self.records.append(record) }
    }

    override func tearDown() {
        MetadataLog.sink = MetadataLog.defaultSink
        super.tearDown()
    }

    private func parse(_ data: Data) throws {
        _ = try ParseWebSocketData(data: data, defaultDJ: nil).parse(shortCode: shortCode)
    }

    private func parse(_ object: [String: Any]) throws {
        try parse(JSONSerialization.data(withJSONObject: object))
    }

    // MARK: Recorded

    func testAConnectMessageMissingRequiredFieldsIsRecordedAsIgnored() throws {
        try parse(ConnectMessageFixture.data { np in
            var nowPlaying = np["now_playing"] as? [String: Any] ?? [:]
            nowPlaying["duration"] = nil
            np["now_playing"] = nowPlaying
        })

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .ignored)
        XCTAssertTrue(records.first?.detail.contains("connect") == true, records.first?.detail ?? "")
    }

    func testAChannelMessageMissingRequiredFieldsIsRecordedAsIgnored() throws {
        try parse(["channel": "station:\(shortCode)", "pub": ["data": ["np": [String: Any]()]]])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .ignored)
        XCTAssertTrue(records.first?.detail.contains("channel") == true, records.first?.detail ?? "")
    }

    func testAMessageOfAKindWeDontKnowIsRecordedAsIgnored() throws {
        try parse(["error": ["code": 100, "message": "something the app has never seen"]])

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .ignored)
    }

    func testJSONThatIsNotAnObjectIsRecordedAsIgnored() throws {
        try parse(Data("[1, 2, 3]".utf8))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.kind, .ignored)
    }

    // MARK: Not recorded

    func testAMessageThatParsesRecordsNothing() throws {
        try parse(ConnectMessageFixture.data())

        XCTAssertTrue(records.isEmpty, "\(records)")
    }

    func testTheEmptyHeartbeatRecordsNothing() throws {
        try parse([String: Any]())

        XCTAssertTrue(records.isEmpty, "A heartbeat every ping interval would fill the log")
    }

    // MARK: Privacy

    func testARecordNeverCarriesTheMessageItself() throws {
        try parse(["error": ["message": "SECRET-TRACK-TITLE"]])

        XCTAssertFalse(records.contains { $0.detail.contains("SECRET-TRACK-TITLE") },
                       "The record says what happened, not what the message held")
    }
}
