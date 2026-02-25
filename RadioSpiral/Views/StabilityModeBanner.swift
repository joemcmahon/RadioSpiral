// RadioSpiral/Views/StabilityModeBanner.swift
import UIKit

/// One-time banner shown when hearing aids connect and preference is .ask.
/// Appears at top of key window. Has two action buttons and a "Don't ask again" toggle.
final class StabilityModeBanner: UIView {

    private let messageLabel = UILabel()
    private let dontAskButton = UIButton(type: .system)
    private let keepStabilityButton = UIButton(type: .system)
    private let keepFidelityButton = UIButton(type: .system)
    private var dontAskChecked = false
    private var dismissTimer: Timer?

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

        messageLabel.text = "Hearing aids connected — switched to Stability Mode to prevent audio pitch wobble."
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 14, weight: .medium)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        dontAskButton.setTitle("○  Don't ask again", for: .normal)
        dontAskButton.setTitleColor(.white, for: .normal)
        dontAskButton.titleLabel?.font = .systemFont(ofSize: 13)
        dontAskButton.contentHorizontalAlignment = .left
        dontAskButton.addTarget(self, action: #selector(toggleDontAsk), for: .touchUpInside)
        dontAskButton.translatesAutoresizingMaskIntoConstraints = false

        keepStabilityButton.setTitle("Keep Stability", for: .normal)
        keepStabilityButton.setTitleColor(.systemBlue, for: .normal)
        keepStabilityButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        keepStabilityButton.addTarget(self, action: #selector(tappedKeepStability), for: .touchUpInside)
        keepStabilityButton.translatesAutoresizingMaskIntoConstraints = false

        keepFidelityButton.setTitle("Keep Hi-Fi", for: .normal)
        keepFidelityButton.setTitleColor(.systemOrange, for: .normal)
        keepFidelityButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        keepFidelityButton.addTarget(self, action: #selector(tappedKeepFidelity), for: .touchUpInside)
        keepFidelityButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = UIStackView(arrangedSubviews: [keepStabilityButton, keepFidelityButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 16
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [messageLabel, dontAskButton, buttonRow])
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

    @objc private func toggleDontAsk() {
        dontAskChecked.toggle()
        dontAskButton.setTitle(dontAskChecked ? "●  Don't ask again" : "○  Don't ask again",
                               for: .normal)
    }

    @objc private func tappedKeepStability() {
        if dontAskChecked { AudioStabilityPreference.current = .alwaysStability }
        dismiss()
    }

    @objc private func tappedKeepFidelity() {
        if dontAskChecked { AudioStabilityPreference.current = .neverStability }
        // Switching back to fidelity: tell RadioPlayer
        RadioPlayer.shared.applyStabilitySettings(mode: .fidelity)
        dismiss()
    }

    private func dismiss() {
        dismissTimer?.invalidate()
        UIView.animate(withDuration: 0.3, animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
        }
    }

    // MARK: - Public

    /// Add to key window and auto-dismiss after 10 seconds.
    func show() {
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows
                .first(where: { $0.isKeyWindow }) else { return }

        window.addSubview(self)
        alpha = 0

        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
            leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 16),
            trailingAnchor.constraint(equalTo: window.trailingAnchor, constant: -16),
        ])

        UIView.animate(withDuration: 0.3) { self.alpha = 1 }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }
}
