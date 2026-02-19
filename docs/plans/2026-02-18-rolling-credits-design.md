# Rolling Credits Design

## Summary
Replace two-column static credits on About screen with a single-column, auto-scrolling "movie credits" display that loops infinitely.

## Approach
UIScrollView with duplicated content + CADisplayLink for smooth animation.

## Layout
- Description: static at top
- Rolling credits: fixed-height clipped area in the middle, auto-scrolling
- Attribution + buttons: static below

## Implementation Details
- Credits content duplicated in scroll view for seamless loop
- CADisplayLink advances contentOffset.y ~0.3pt/frame (~18pt/sec)
- When offset reaches midpoint (end of first copy), reset to 0
- Tap gesture toggles pause/resume
- Display link starts in viewDidAppear, invalidates in viewWillDisappear
- Each credit rendered as centered UILabel: "Role: Name"
- Font: .caption1, color: white, spacing: 12pt between entries

## Files Changed
- `RadioSpiral/ViewControllers/AboutViewController.swift` — replace makeCreditsColumns/formatCredits/makeCreditsTextView with makeRollingCredits + display link

## Files Unchanged
- Credits.swift, CreditsClient.swift, all other files
