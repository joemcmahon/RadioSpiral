//
//  TitleFit.swift
//  RadioSpiral
//
//  Fits a track title into a width and a number of lines by shrinking its font.
//

import UIKit

enum TitleFit {

    /// Number of lines `text` takes in `font` at `width`, wrapping at words as a UILabel does.
    static func lineCount(of text: String, font: UIFont, width: CGFloat) -> Int {
        guard !text.isEmpty else { return 1 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil)
        return max(1, Int((bounds.height / font.lineHeight).rounded()))
    }

    /// The largest scale (at most 1) at which `text` fits in `maxLines` lines of `width`.
    /// Never returns a scale that would put the font under `minPoints` (11 pt is the iOS
    /// minimum in the Human Interface Guidelines): a title that can't fit even then settles at
    /// that floor, and the label truncates it. A binary search, so about seven measurements.
    static func scale(for text: String, font: UIFont, width: CGFloat, maxLines: Int,
                      minPoints: CGFloat = 11) -> CGFloat {
        let floor = min(1, minPoints / font.pointSize)
        func fits(_ scale: CGFloat) -> Bool {
            lineCount(of: text, font: font.withSize(font.pointSize * scale), width: width) <= maxLines
        }

        if text.isEmpty || fits(1) { return 1 }
        if !fits(floor) { return floor }

        var fitting = floor   // fits
        var tooBig: CGFloat = 1   // doesn't
        while tooBig - fitting > 0.01 {
            let middle = (fitting + tooBig) / 2
            if fits(middle) { fitting = middle } else { tooBig = middle }
        }
        return fitting
    }
}
