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
    func didChangeStationServer(_ aboutViewController: AboutViewController)
}

class AboutViewController: UIViewController {

    weak var delegate: AboutViewControllerDelegate?

    // Credits loaded from remote (falls back to hardcoded)
    private var loadedCredits: [CreditPair] = fallbackCredits

    // Adaptive layout container — rebuilt on orientation change
    private var bodyContainer: UIView?

    // Rolling credits state
    private var creditsScrollView: UIScrollView?
    /// First view of the second copy of the credits; where the loop wraps to.
    private weak var secondCopyStart: UIView?
    /// Last view of the first copy (the attribution): where one full copy of the credits ends.
    private weak var firstCopyEnd: UIView?
    /// The spacer and the second copy: only needed for the loop, hidden when the credits fit.
    private var loopOnlyViews: [UIView] = []
    private var displayLink: CADisplayLink?
    private var isScrollPaused = false
    private static let scrollSpeed: CGFloat = 0.3 // points per frame (~18pt/sec at 60fps)
    /// Seconds the credits hold still after they appear, so the first credit can be read.
    static let startDelay: TimeInterval = 2
    /// The credits do not roll before this time (`CACurrentMediaTime`); set whenever they are back at the top.
    private var scrollStartTime: CFTimeInterval = 0

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
        holdCreditsAtTheTop()
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

    // Internal (not private) so tests can rebuild the body without a rotation.
    func rebuildBody() {
        stopDisplayLink()
        creditsScrollView = nil
        bodyContainer?.removeFromSuperview()
        bodyContainer = nil
        // Detach buttons from old parent so they can be re-added
        websiteButton.removeFromSuperview()
        emailButton.removeFromSuperview()
        buildBody()
        holdCreditsAtTheTop()
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

        stack.addArrangedSubview(makeHeader())
        stack.addArrangedSubview(makeRollingCredits())
        stack.addArrangedSubview(websiteButton)
        stack.addArrangedSubview(emailButton)
        if let selector = makeServerSelector() { stack.addArrangedSubview(selector) }
        stack.addArrangedSubview(makeBuildLabel())
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

        // Left side: the wordmark stays put; the credits and attribution roll beneath it
        let header = makeHeader()
        let rollingView = makeRollingCredits()
        container.addSubview(header)
        container.addSubview(rollingView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            header.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.7, constant: -24),
            rollingView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            rollingView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            rollingView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            rollingView.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.7, constant: -24),
        ])

        // Right side: buttons stacked vertically, centered (30% width)
        let buttonStack = UIStackView(arrangedSubviews: [websiteButton, emailButton] + [makeServerSelector()].compactMap { $0 } + [makeBuildLabel()])
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

    // MARK: - Header (the app's wordmark; never station content)

    /// The fixed header: the wordmark alone, as wide as the space allows up to the launch
    /// screen's cap, with the height that follows from the artwork's shape.
    private func makeHeader() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let wordmark = LaunchWordmark.makeImageView()
        wordmark.accessibilityIdentifier = "aboutWordmark"
        container.addSubview(wordmark)

        let size = wordmark.image?.size ?? CGSize(width: 5112, height: 768)
        let fillWidth = wordmark.widthAnchor.constraint(equalTo: container.widthAnchor)
        fillWidth.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            wordmark.topAnchor.constraint(equalTo: container.topAnchor),
            wordmark.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            wordmark.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            fillWidth,
            wordmark.widthAnchor.constraint(lessThanOrEqualToConstant: LaunchWordmark.maximumWidth),
            wordmark.widthAnchor.constraint(equalTo: wordmark.heightAnchor, multiplier: size.width / size.height),
        ])
        // The container has no intrinsic size, so hugging and compression priorities would do
        // nothing here. Its height comes from the wordmark pinned top and bottom: the wordmark's
        // width follows the space (up to the cap) and its height follows from the artwork's shape.
        // The credits take whatever is left.
        return container
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

        // One sequence: the credits, then the attribution
        func addSequence() {
            for credit in loadedCredits {
                stack.addArrangedSubview(makeCreditLabel(credit))
            }
            stack.addArrangedSubview(makeAttribution())
        }

        // First copy
        addSequence()
        firstCopyEnd = stack.arrangedSubviews.last
        // Spacer between copies
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(spacer)
        // Second copy (for seamless loop)
        let secondCopyIndex = stack.arrangedSubviews.count
        addSequence()
        secondCopyStart = stack.arrangedSubviews[secondCopyIndex]
        loopOnlyViews = Array(stack.arrangedSubviews[(secondCopyIndex - 1)...])

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

    private func makeCreditLabel(_ credit: CreditPair) -> UILabel {
        let label = UILabel()
        label.text = "\(credit.role): \(credit.name)"
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
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

    /// Whether one full copy of the credits (through the attribution) fits in the scroll view. Read
    /// from the first copy alone, so hiding the loop's second copy cannot change the answer.
    /// False until the screen has been laid out.
    private func creditsFit(in scrollView: UIScrollView) -> Bool {
        guard let end = firstCopyEnd, scrollView.bounds.height > 0 else { return false }
        return scrollView.convert(end.bounds, from: end).maxY <= scrollView.bounds.height
    }

    /// The loop needs a second copy to wrap without a seam. When everything already fits (a tall
    /// iPad window), a second copy would show the credits twice and there is nothing to scroll, so
    /// hide it and hold the credits at the top.
    private func updateLoopCopy() {
        guard let scrollView = creditsScrollView else { return }
        // The credits' own layout can lag this callback by a pass; measure the settled positions.
        scrollView.layoutIfNeeded()
        let fits = creditsFit(in: scrollView)
        for view in loopOnlyViews where view.isHidden != fits { view.isHidden = fits }
        if fits && scrollView.contentOffset.y != 0 { scrollView.contentOffset.y = 0 }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLoopCopy()
    }

    /// How far the credits scroll before the loop wraps back to the top: the distance to where the
    /// second copy starts, so the jump back is invisible. (Half the content height is not that
    /// distance: the spacer and its two gaps sit between the copies, not inside either.) Zero until
    /// the screen has been laid out. Internal so a test can read it.
    var creditsLoopLength: CGFloat {
        guard let scrollView = creditsScrollView, let start = secondCopyStart else { return 0 }
        return scrollView.convert(start.bounds, from: start).minY
    }

    // Internal (not private) so tests can step the credits without waiting on the display link.
    /// Give the first credit a moment at the top before the credits start to roll.
    private func holdCreditsAtTheTop() {
        scrollStartTime = CACurrentMediaTime() + Self.startDelay
    }

    @objc func scrollCredits() {
        // Re-check the fit every tick, paused or not. The layout-time check can be answered from a
        // layout that then changes without another layout callback; this puts a wrong answer right
        // within a frame instead of leaving blank space after the last credit.
        updateLoopCopy()
        guard !isScrollPaused, CACurrentMediaTime() >= scrollStartTime,
              let scrollView = creditsScrollView, !creditsFit(in: scrollView) else { return }
        let loopLength = creditsLoopLength
        guard loopLength > 0 else { return }

        var offset = scrollView.contentOffset.y + Self.scrollSpeed

        // When we've scrolled past the first copy, jump back seamlessly
        if offset >= loopLength {
            offset -= loopLength
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
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    // MARK: - Build information

    private func makeBuildLabel() -> UILabel {
        let label = UILabel()
        label.text = BuildInfo.aboutText
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "buildInfoLabel"
        return label
    }

    // MARK: - Station server (TestFlight and Xcode builds only)

    private func makeServerSelector() -> UIView? {
        guard InstallEnvironment.current?.allowsTestServer == true else { return nil }

        let label = UILabel()
        label.text = "Station server (testers only)"
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center

        let control = UISegmentedControl(items: StationServer.allCases.map { $0.title })
        control.overrideUserInterfaceStyle = .dark
        control.selectedSegmentIndex = StationServer.allCases.firstIndex(of: StationServer.selected) ?? 0
        control.accessibilityLabel = "Station server"
        control.addTarget(self, action: #selector(serverChanged(_:)), for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    @objc private func serverChanged(_ control: UISegmentedControl) {
        StationServer.selected = StationServer.allCases[control.selectedSegmentIndex]
        delegate?.didChangeStationServer(self)
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
