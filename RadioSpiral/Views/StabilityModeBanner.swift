// RadioSpiral/Views/StabilityModeBanner.swift
import UIKit

/// First-run banner: shown when hearing aids are connected and no preference has been chosen.
/// Forces a choice, which is saved to AudioStabilityPreference (shared with the ear button).
final class StabilityModeBanner: UIView {

    private let messageLabel = UILabel()
    private let keepStabilityButton = UIButton()
    private let keepFidelityButton = UIButton()
    private let keepAsIsButton = UIButton()

    /// At most one banner on screen app-wide; several NowPlaying instances may each try to show one.
    private static weak var visibleBanner: StabilityModeBanner?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = UIColor.black.withAlphaComponent(0.85)
        layer.cornerRadius = 12
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        let fontSize = 18

        messageLabel.text = "Hearing aids connected in stable pitch mode to prevent audio pitch wobble. Tap a preference below to continue:"
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: CGFloat(fontSize), weight: .medium)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        keepStabilityButton.setTitle("Always ensure stable pitch", for: .normal)
        keepStabilityButton.setTitleColor(.systemBlue, for: .normal)
        keepStabilityButton.titleLabel?.font = .systemFont(ofSize: CGFloat(fontSize), weight: .semibold)
        keepStabilityButton.addTarget(self, action: #selector(tappedKeepStability), for: .touchUpInside)
        keepStabilityButton.translatesAutoresizingMaskIntoConstraints = false

        keepFidelityButton.setTitle("Always ensure continuous audio", for: .normal)
        keepFidelityButton.setTitleColor(.systemOrange, for: .normal)
        keepFidelityButton.titleLabel?.font = .systemFont(ofSize: CGFloat(fontSize), weight: .semibold)
        keepFidelityButton.addTarget(self, action: #selector(tappedKeepFidelity), for: .touchUpInside)
        keepFidelityButton.translatesAutoresizingMaskIntoConstraints = false

        
        keepAsIsButton.setTitle("Use best choice for current output", for: .normal)
        keepAsIsButton.setTitleColor(.systemGray, for: .normal)
        keepAsIsButton.titleLabel?.font = .systemFont(ofSize: CGFloat(fontSize), weight: .semibold)
        keepAsIsButton.contentHorizontalAlignment = .left
        keepAsIsButton.addTarget(self, action: #selector(tappedKeepAsIs), for: .touchUpInside)
        keepAsIsButton.translatesAutoresizingMaskIntoConstraints = false

        for button in [keepStabilityButton, keepFidelityButton, keepAsIsButton] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.contentHorizontalAlignment = .center
        }

        let buttonStack = UIStackView(arrangedSubviews: [keepStabilityButton, keepFidelityButton, keepAsIsButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [messageLabel, buttonStack])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    // Each choice saves the same preference as the matching ear-menu item, then applies it.
    // applyStabilitySettings posts stabilityModeDidChange, which refreshes the ear button.

    @objc private func tappedKeepStability() {
        RadioPlayer.shared.choosePreference(.alwaysStability)
        dismiss()
    }

    @objc private func tappedKeepFidelity() {
        RadioPlayer.shared.choosePreference(.neverStability)
        dismiss()
    }

    @objc private func tappedKeepAsIs() {
        RadioPlayer.shared.choosePreference(.ask)
        dismiss()
    }

    private func dismiss() {
        UIView.animate(withDuration: 0.3, animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
        }
    }

    // MARK: - Public

    /// Add to the given window (the caller's own, so it never lands in the CarPlay scene).
    /// Stays visible until the user taps a choice. No-op if a banner is already showing.
    func show(in window: UIWindow) {
        guard StabilityModeBanner.visibleBanner == nil else { return }

        window.addSubview(self)
        StabilityModeBanner.visibleBanner = self
        alpha = 0

        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
            leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 16),
            trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -16),
        ])

        UIView.animate(withDuration: 0.3) { self.alpha = 1 }
    }
}
