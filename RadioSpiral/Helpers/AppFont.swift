//
//  AppFont.swift
//  RadioSpiral
//
//  The app's display font, Zen Dots (SIL Open Font License; the license is in `Fonts/OFL.txt`).
//  It is for big, short, high-impact text only: the song title, the artist line and channel
//  names. It has one weight, is wide, and is hard to read small, and it has no monospaced
//  digits, so body text, captions, the connection banner and the time bubble stay in the system
//  font. CarPlay, the lock screen and system alerts always use the system font.
//

import UIKit

enum AppFont {

    /// PostScript name of the bundled font file (`Fonts/ZenDots-Regular.ttf`, listed under
    /// `UIAppFonts` in `Info.plist`).
    static let displayFontName = "ZenDots-Regular"

    /// The display font for a text style. It starts at the size the system uses for that style
    /// at the default content size, then scales with Dynamic Type like the system font does.
    /// If the font can't be loaded it returns the system font for the style, so text still shows.
    static func display(_ style: UIFont.TextStyle,
                        fontName: String = displayFontName,
                        compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let defaultSize = UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
        guard let font = UIFont(name: fontName, size: defaultSize) else {
            return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font, compatibleWith: traits)
    }

    /// The display font for a large nav-bar title, sized so `text` fits on one line in `width`.
    /// A large title can't wrap or shrink by itself, so a fixed size would end in an ellipsis on
    /// a narrow screen. Uses `TitleFit`, so it never goes below the 11 pt floor.
    static func largeTitle(_ text: String,
                           fitting width: CGFloat,
                           compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let font = display(.largeTitle, compatibleWith: traits)
        let scale = TitleFit.scale(for: text, font: font, width: width, maxLines: 1)
        return font.withSize(font.pointSize * scale)
    }

    /// A nav-bar title in the display font, for one screen's `navigationItem.titleView` (the
    /// nav bar's own title font is shared by every screen). White, like the bar's tint; it
    /// shrinks rather than collide with the bar buttons next to it.
    static func titleLabel(_ text: String?) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = display(.subheadline)
        label.textColor = .white
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.accessibilityTraits = .header
        return label
    }
}
