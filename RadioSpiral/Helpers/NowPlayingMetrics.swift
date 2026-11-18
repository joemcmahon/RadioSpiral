//
//  NowPlayingMetrics.swift
//  RadioSpiral
//
//  The numbers Now Playing's layout uses, chosen from the screen's size classes instead of the
//  device idiom. Each value follows the axis whose room it needs:
//
//  - the 1.4x scale needs room on both axes, so both classes must be regular;
//  - the portrait album height and the landscape art width and side margin follow the width;
//  - the landscape art box (centered square or pinned) and the label fit follow the height.
//
//  A class that is `.unspecified` counts as neither regular nor compact. The Duo's inner display
//  is regular-width but keeps its own tuned fold layouts, so `isFoldInner` always gets the phone
//  values (the check itself is `isFoldInnerDisplay` in the view controller).
//

import UIKit

struct NowPlayingMetrics: Equatable {
    /// 1.4 or 1.0: multiplies fonts, controls and the toolbar.
    let uiScale: CGFloat
    /// 0.55 or 0.40: the album's height as a fraction of the view, in portrait.
    let portraitAlbumHeightFraction: CGFloat
    /// True: the landscape art box is a centered square. False: it is pinned to the top.
    let landscapeArtBoxCentered: Bool
    /// 0.35 or 0.40: the album's width as a fraction of the view, in landscape.
    let landscapeArtWidthFraction: CGFloat
    /// 40 or 12: the landscape side margin before the safe area is added.
    let landscapeSideMarginBase: CGFloat
    /// True: in landscape the labels are fitted to the right-hand panel's height.
    let fitsLabelsToPanel: Bool

    /// What every phone, and the Duo's inner display, uses.
    static let phone = NowPlayingMetrics(
        uiScale: 1.0,
        portraitAlbumHeightFraction: 0.40,
        landscapeArtBoxCentered: false,
        landscapeArtWidthFraction: 0.40,
        landscapeSideMarginBase: 12,
        fitsLabelsToPanel: true
    )

    private init(
        uiScale: CGFloat,
        portraitAlbumHeightFraction: CGFloat,
        landscapeArtBoxCentered: Bool,
        landscapeArtWidthFraction: CGFloat,
        landscapeSideMarginBase: CGFloat,
        fitsLabelsToPanel: Bool
    ) {
        self.uiScale = uiScale
        self.portraitAlbumHeightFraction = portraitAlbumHeightFraction
        self.landscapeArtBoxCentered = landscapeArtBoxCentered
        self.landscapeArtWidthFraction = landscapeArtWidthFraction
        self.landscapeSideMarginBase = landscapeSideMarginBase
        self.fitsLabelsToPanel = fitsLabelsToPanel
    }

    init(horizontal: UIUserInterfaceSizeClass, vertical: UIUserInterfaceSizeClass, isFoldInner: Bool) {
        if isFoldInner {
            self = .phone
            return
        }
        let wide = horizontal == .regular
        let tall = vertical == .regular
        self.init(
            uiScale: wide && tall ? 1.4 : 1.0,
            portraitAlbumHeightFraction: wide ? 0.55 : 0.40,
            landscapeArtBoxCentered: tall,
            landscapeArtWidthFraction: wide ? 0.35 : 0.40,
            landscapeSideMarginBase: wide ? 40 : 12,
            fitsLabelsToPanel: vertical == .compact
        )
    }
}
