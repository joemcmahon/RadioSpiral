//
//  BuiltInCreditsTests.swift
//  ConfigClientTests
//
//  The credits built into the app, shown when the credits file can't be fetched. Like the bundled
//  stations, they follow the launch date: one downtime robot (Spud) until then, all four after.
//
//  Credits.swift is compiled into the tests too, so these go through `RadioSpiral.` (the app's copy)
//  and compare as "role: name" text, because the two copies' CreditPair types are different types.
//

import XCTest
@testable import RadioSpiral

final class BuiltInCreditsTests: XCTestCase {

    private let launch = ConfigClient.launchDate

    private func lines(on date: Date) -> [String] {
        RadioSpiral.builtInCredits(on: date).map { "\($0.role): \($0.name)" }
    }

    func testBeforeTheLaunchTheBuiltInCreditsNameSpudAlone() {
        let credits = lines(on: launch.addingTimeInterval(-1))

        XCTAssertEqual(credits.last, "Downtime DJ & attitude: Spud the Ambient Robot")
        XCTAssertFalse(credits.contains { $0.contains("Igor") }, "the new robots stay unnamed until the launch")
    }

    func testFromTheLaunchTheBuiltInCreditsNameAllFourRobots() {
        XCTAssertEqual(lines(on: launch).last, "Downtime DJs: Spud, Igor, Roshi, and Bop")
    }

    func testTheOtherCreditsDoNotDependOnTheDate() {
        XCTAssertEqual(lines(on: launch.addingTimeInterval(-1)).dropLast(), lines(on: launch).dropLast())
    }

    func testTheBuiltInCreditsMatchTheLiveFile() {
        let credits = lines(on: launch.addingTimeInterval(-1))

        XCTAssertEqual(credits.count, 13)
        XCTAssertEqual(credits[4], "Bullhorn and cat herding: Rebekkah Hilgraves (ʞu¡0ɹʞS)")
        XCTAssertEqual(credits[5], "Wild enthusiasm and remixes: Kyizl")
    }

    func testTheFallbackFollowsTheClock() {
        // Whichever side of the launch the real clock is on, it is one of the two lists.
        let now = RadioSpiral.fallbackCredits.map { "\($0.role): \($0.name)" }
        XCTAssertTrue(now == lines(on: launch.addingTimeInterval(-1)) || now == lines(on: launch))
    }
}
