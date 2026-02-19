//
//  AboutViewController.swift
//  Swift Radio
//
//  Created by Matthew Fecher on 7/9/15.
//  Copyright (c) 2015 MatthewFecher.com. All rights reserved.
//

import UIKit
import MessageUI

protocol AboutViewControllerDelegate: AnyObject {
    func didTapEmailButton(_ aboutViewController: AboutViewController)
    func didTapWebsiteButton(_ aboutViewController: AboutViewController)
}

class AboutViewController: UIViewController {

    weak var delegate: AboutViewControllerDelegate?

    /// When set, a station info row (image + name + description) appears above credits.
    /// Nil when opened from the popup menu (no station context).
    var currentStation: RadioStation?

    // Credits loaded from remote (falls back to hardcoded)
    private var loadedCredits: [CreditPair] = fallbackCredits

    // Adaptive layout container — rebuilt on orientation change
    private var bodyContainer: UIView?

    // Rolling credits state
    private var creditsScrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    private var isScrollPaused = false
    private static let scrollSpeed: CGFloat = 0.3 // points per frame (~18pt/sec at 60fps)

    // Constraints that change between portrait/landscape
    private var okLeadingToSafeArea: NSLayoutConstraint!
    private var okLeadingToMidpoint: NSLayoutConstraint!

    private let okButton = UIButton(type: .system)
    private let websiteButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Visit our website"
        config.baseForegroundColor = .white
        return UIButton(configuration: config)
    }()
    private let emailButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Email us"
        config.baseForegroundColor = .white
        return UIButton(configuration: config)
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupChrome()
        buildBody()

        CreditsClient.shared.fetchCredits { [weak self] credits in
            guard let self = self else { return }
            guard credits != self.loadedCredits else { return }
            self.loadedCredits = credits
            DispatchQueue.main.async {
                self.rebuildBody()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isScrollPaused = ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT")
        startDisplayLink()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDisplayLink()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.rebuildBody()
        })
    }

    // MARK: - Chrome (background + OK button — never change)

    private func setupChrome() {
        // Background image (edge-to-edge)
        let bg = UIImageView(image: UIImage(named: "background"))
        bg.contentMode = .scaleToFill
        bg.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bg)
        NSLayoutConstraint.activate([
            bg.topAnchor.constraint(equalTo: view.topAnchor),
            bg.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // OK button — always pinned to bottom-right area
        okButton.setTitle("OK", for: .normal)
        okButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        okButton.setTitleColor(.white, for: .normal)
        okButton.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        okButton.layer.cornerRadius = 8
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.addTarget(self, action: #selector(okButtonTapped), for: .touchUpInside)
        okButton.accessibilityIdentifier = "okButton"
        view.addSubview(okButton)

        // Prepare both leading constraints (only one active at a time)
        okLeadingToSafeArea = okButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        // In landscape, OK button aligns with the 30% button column on the right
        // Use a layout guide at the 70% mark
        let splitGuide = UILayoutGuide()
        view.addLayoutGuide(splitGuide)
        splitGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        splitGuide.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7).isActive = true
        okLeadingToMidpoint = okButton.leadingAnchor.constraint(equalTo: splitGuide.trailingAnchor, constant: 16)

        NSLayoutConstraint.activate([
            okButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            okButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            okButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        websiteButton.addTarget(self, action: #selector(websiteButtonTapped), for: .touchUpInside)
        emailButton.addTarget(self, action: #selector(emailButtonTapped), for: .touchUpInside)
    }

    // MARK: - Adaptive Body

    private var isLandscape: Bool {
        traitCollection.verticalSizeClass == .compact
    }

    private func rebuildBody() {
        stopDisplayLink()
        creditsScrollView = nil
        bodyContainer?.removeFromSuperview()
        bodyContainer = nil
        // Detach buttons from old parent so they can be re-added
        websiteButton.removeFromSuperview()
        emailButton.removeFromSuperview()
        buildBody()
        if view.window != nil { startDisplayLink() }
    }

    private func buildBody() {
        if isLandscape {
            buildLandscapeBody()
        } else {
            buildPortraitBody()
        }
    }

    // MARK: Portrait layout: vertical scroll with everything

    private func buildPortraitBody() {
        okLeadingToMidpoint.isActive = false
        okLeadingToSafeArea.isActive = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(stack, belowSubview: okButton)
        bodyContainer = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: okButton.topAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])

        stack.addArrangedSubview(makeDescription())
        stack.addArrangedSubview(makeRollingCredits())
        stack.addArrangedSubview(makeAttribution())
        stack.addArrangedSubview(websiteButton)
        stack.addArrangedSubview(emailButton)
    }

    // MARK: Landscape layout: scrolling credits left, buttons right

    private func buildLandscapeBody() {
        okLeadingToSafeArea.isActive = false
        okLeadingToMidpoint.isActive = true

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(container, belowSubview: okButton)
        bodyContainer = container

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: okButton.topAnchor, constant: -8),
            container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        // Left side: everything rolls together in landscape
        let rollingView = makeRollingAll()
        container.addSubview(rollingView)

        NSLayoutConstraint.activate([
            rollingView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            rollingView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            rollingView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            rollingView.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.7, constant: -24),
        ])

        // Right side: buttons stacked vertically, centered (30% width)
        let buttonStack = UIStackView(arrangedSubviews: [websiteButton, emailButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        buttonStack.alignment = .center
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            buttonStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: rollingView.trailingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
    }

    // MARK: - Description (station-specific when available, generic blurb otherwise)

    private static let defaultDescription = "RadioSpiral: 24/7 captivating electronica, with some of the best of the genre in electronic and ambient music. Featuring live DJs and live performances."

    private func makeDescription() -> UIView {
        let descText: String
        if let station = currentStation, !station.longDesc.isEmpty {
            descText = station.longDesc
        } else {
            descText = Self.defaultDescription
        }

        let descLabel = UILabel()
        descLabel.text = descText
        descLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        descLabel.textColor = .white
        descLabel.numberOfLines = 0

        // When we have a station, show image + name alongside description
        if let station = currentStation {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.applyShadow()
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 80),
                imageView.heightAnchor.constraint(equalToConstant: 80),
            ])
            station.getImage { image in
                imageView.image = image
            }

            let nameLabel = UILabel()
            nameLabel.text = station.name
            nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
            nameLabel.textColor = .white

            let textStack = UIStackView(arrangedSubviews: [nameLabel, descLabel])
            textStack.axis = .vertical
            textStack.spacing = 4

            let row = UIStackView(arrangedSubviews: [imageView, textStack])
            row.axis = .horizontal
            row.spacing = 12
            row.alignment = .center
            return row
        }

        return descLabel
    }

    // MARK: - Rolling Credits

    private func makeRollingCredits() -> UIView {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isUserInteractionEnabled = true
        scrollView.clipsToBounds = true

        // Build a stack with credits duplicated for seamless looping
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        // First copy
        for credit in loadedCredits {
            stack.addArrangedSubview(makeCreditLabel(credit))
        }
        // Spacer between copies
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(spacer)
        // Second copy (for seamless loop)
        for credit in loadedCredits {
            stack.addArrangedSubview(makeCreditLabel(credit))
        }

        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        // Tap to pause/resume
        let tap = UITapGestureRecognizer(target: self, action: #selector(creditsTapped))
        scrollView.addGestureRecognizer(tap)

        creditsScrollView = scrollView
        return scrollView
    }

    /// Landscape variant: description + credits + attribution all roll together
    private func makeRollingAll() -> UIView {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isUserInteractionEnabled = true
        scrollView.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Helper to add one full sequence
        func addSequence() {
            stack.addArrangedSubview(makeDescription())
            for credit in loadedCredits {
                stack.addArrangedSubview(makeCreditLabel(credit))
            }
            stack.addArrangedSubview(makeAttribution())
        }

        // First copy
        addSequence()
        // Spacer between copies
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(spacer)
        // Second copy (for seamless loop)
        addSequence()

        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(creditsTapped))
        scrollView.addGestureRecognizer(tap)

        creditsScrollView = scrollView
        return scrollView
    }

    private func makeCreditLabel(_ credit: CreditPair) -> UILabel {
        let label = UILabel()
        label.text = "\(credit.role): \(credit.name)"
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(scrollCredits))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func scrollCredits() {
        guard !isScrollPaused, let scrollView = creditsScrollView else { return }
        let contentHeight = scrollView.contentSize.height
        guard contentHeight > 0 else { return }

        // Midpoint is where the second copy starts (half of total content)
        let midpoint = contentHeight / 2.0
        var offset = scrollView.contentOffset.y + Self.scrollSpeed

        // When we've scrolled past the first copy, jump back seamlessly
        if offset >= midpoint {
            offset -= midpoint
        }

        scrollView.contentOffset.y = offset
    }

    @objc private func creditsTapped() {
        isScrollPaused.toggle()
    }

    private func makeAttribution() -> UILabel {
        let label = UILabel()
        label.text = "Based on Swift Radio Pro\nby Matthew Fecher & Fethi El Hassasna"
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    // MARK: - Actions

    @objc private func websiteButtonTapped() {
        delegate?.didTapWebsiteButton(self)
    }

    @objc private func emailButtonTapped() {
        delegate?.didTapEmailButton(self)
    }

    @objc private func okButtonTapped() {
        dismiss(animated: true)
    }
}

// MARK: - MFMailComposeViewController Delegate

extension AboutViewController: MFMailComposeViewControllerDelegate {

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil)
    }
}
