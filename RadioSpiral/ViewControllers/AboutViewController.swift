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

    // Adaptive layout container — rebuilt on orientation change
    private var bodyContainer: UIView?

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
        view.addSubview(okButton)

        // Prepare both leading constraints (only one active at a time)
        okLeadingToSafeArea = okButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        okLeadingToMidpoint = okButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 16)

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
        bodyContainer?.removeFromSuperview()
        bodyContainer = nil
        // Detach buttons from old parent so they can be re-added
        websiteButton.removeFromSuperview()
        emailButton.removeFromSuperview()
        buildBody()
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

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(scrollView, belowSubview: okButton)
        bodyContainer = scrollView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: okButton.topAnchor, constant: -8),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        stack.addArrangedSubview(makeDescription())
        stack.addArrangedSubview(makeCreditsColumns())
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

        // Left side: scrolling credits
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.centerXAnchor),
        ])

        let creditsStack = UIStackView()
        creditsStack.axis = .vertical
        creditsStack.spacing = 8
        creditsStack.alignment = .fill
        creditsStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(creditsStack)

        NSLayoutConstraint.activate([
            creditsStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            creditsStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            creditsStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            creditsStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -8),
            creditsStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -24),
        ])

        creditsStack.addArrangedSubview(makeDescription())
        creditsStack.addArrangedSubview(makeCreditsColumns())
        creditsStack.addArrangedSubview(makeAttribution())

        // Right side: buttons stacked vertically, centered
        let buttonStack = UIStackView(arrangedSubviews: [websiteButton, emailButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        buttonStack.alignment = .center
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            buttonStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: container.centerXAnchor, constant: 16),
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

    // MARK: - Shared UI builders


    private func makeCreditsColumns() -> UIStackView {
        let left = makeCreditsTextView(text: "Curator:\n • Mike Metlay\n\nSecond Life:\n • Diana Smethurst\n\nKeeping the lights on:\n • Paul Harriman\n\nBots & iOS:\n • Joe McMahon")
        let right = makeCreditsTextView(text: "Bullhorn:\n • Rebekkah Hilgraves\n\nDowntime DJ and attitude:\n • Spud\n\nGeneral nuisance & Linux:\n • José Carlos Cuevas")

        let stack = UIStackView(arrangedSubviews: [left, right])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.alignment = .top
        return stack
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

    private func makeCreditsTextView(text: String) -> UITextView {
        let textView = UITextView()
        textView.text = text
        textView.font = UIFont.preferredFont(forTextStyle: .caption1)
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        return textView
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
