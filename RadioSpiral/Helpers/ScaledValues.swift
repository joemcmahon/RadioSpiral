//
//  ScaledValues.swift
//  RadioSpiral
//
//  Scale constraint constants and label fonts from a base captured once, so applying a scale
//  again (a window that changes size class) never compounds: each apply sets base * scale.
//

import UIKit

/// Holds each constraint's constant as it was when captured; `apply(scale:)` sets base * scale.
final class ScaledConstraints {
    private let entries: [(constraint: NSLayoutConstraint, base: CGFloat)]

    init(_ constraints: [NSLayoutConstraint]) {
        entries = constraints.map { ($0, $0.constant) }
    }

    func apply(scale: CGFloat) {
        for entry in entries { entry.constraint.constant = entry.base * scale }
    }
}

/// Holds each label's font as it was when captured; `apply(scale:)` sets the base font's size
/// times the scale (same face, new size).
final class ScaledFonts {
    private let entries: [(label: UILabel, base: UIFont)]

    init(_ labels: [UILabel]) {
        entries = labels.map { ($0, $0.font) }
    }

    /// The font each label had when captured, for code that sizes from the unscaled base.
    var baseFonts: [UIFont] { entries.map(\.base) }

    func apply(scale: CGFloat) {
        for entry in entries { entry.label.font = entry.base.withSize(entry.base.pointSize * scale) }
    }
}
