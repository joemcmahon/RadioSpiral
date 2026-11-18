//
//  ScaledValuesTests.swift
//  ConfigClientTests
//
//  Scaling constraints and fonts from a captured base: applying a scale many times, in any order,
//  gives base * scale each time and never compounds, so a window that changes size class can go
//  from the iPad scale back to 1.0 and return to the exact original values.
//

import XCTest
@testable import RadioSpiral

final class ScaledValuesTests: XCTestCase {

    func testConstraintsRoundTripExactly() {
        let view = UIView()
        let width = view.widthAnchor.constraint(equalToConstant: 44)
        let height = view.heightAnchor.constraint(equalToConstant: 60)
        let scaled = ScaledConstraints([width, height])

        scaled.apply(scale: 1.4)
        XCTAssertEqual(width.constant, 61.6, accuracy: 0.0001)
        XCTAssertEqual(height.constant, 84, accuracy: 0.0001)

        scaled.apply(scale: 1.0)
        XCTAssertEqual(width.constant, 44)
        XCTAssertEqual(height.constant, 60)

        scaled.apply(scale: 1.4)
        XCTAssertEqual(width.constant, 61.6, accuracy: 0.0001)
        XCTAssertEqual(height.constant, 84, accuracy: 0.0001)
    }

    func testFontsRoundTripExactly() {
        let label = UILabel()
        label.font = UIFont(name: "Courier", size: 17)
        let baseName = label.font.fontName
        let scaled = ScaledFonts([label])

        scaled.apply(scale: 1.4)
        XCTAssertEqual(label.font.pointSize, 23.8, accuracy: 0.0001)
        XCTAssertEqual(label.font.fontName, baseName)

        scaled.apply(scale: 1.0)
        XCTAssertEqual(label.font.pointSize, 17)
        XCTAssertEqual(label.font.fontName, baseName)

        scaled.apply(scale: 1.4)
        XCTAssertEqual(label.font.pointSize, 23.8, accuracy: 0.0001)
        XCTAssertEqual(label.font.fontName, baseName)
    }
}
