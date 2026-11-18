//
//  LaunchWordmark.swift
//  RadioSpiral
//
//  The RadioSpiral wordmark on the startup screen. It is a vector asset (`wordmark`, "Preserve
//  Vector Data"), sized as a share of the screen's width with a cap, so it is neither tiny on an
//  iPad nor huge on a small phone. `LaunchScreen.storyboard` carries the same numbers (65% of the
//  width, at most 520 pt, aspect fit, centered); change them in both places, or the loader
//  jumps when it takes over from the launch screen.
//

import UIKit

enum LaunchWordmark {

    static let imageName = "wordmark"
    static let widthFraction: CGFloat = 0.65
    static let maximumWidth: CGFloat = 520

    static func makeImageView() -> UIImageView {
        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.accessibilityLabel = "RadioSpiral"
        imageView.isAccessibilityElement = true
        return imageView
    }

    /// Centers the wordmark in `view`. The width is a share of the view's width (priority 999, so
    /// the image's own large size can't win) and never above `maximumWidth`; the height follows
    /// from the artwork's shape.
    static func constraints(for imageView: UIImageView, in view: UIView) -> [NSLayoutConstraint] {
        let size = imageView.image?.size ?? CGSize(width: 5112, height: 768)
        let proportional = imageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: widthFraction)
        proportional.priority = UILayoutPriority(999)
        return [
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            proportional,
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth),
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: size.width / size.height)
        ]
    }
}
