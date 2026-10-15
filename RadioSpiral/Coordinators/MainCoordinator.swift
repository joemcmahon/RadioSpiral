//
//  MainCoordinator.swift
//  SwiftRadio
//
//  Created by Fethi El Hassasna on 2022-11-23.
//  Copyright © 2022 matthewfecher.com. All rights reserved.
//

import UIKit
import MessageUI

class MainCoordinator: Coordinator {
    let navigationController: UINavigationController
    
    func start() {
        let loaderVC = LoaderController()
        loaderVC.delegate = self
        navigationController.setViewControllers([loaderVC], animated: false)
    }
    
    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }
    
    // MARK: - Shared
    
    func openWebsite() {
        guard let url = URL(string: Config.website) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    func openEmail(in viewController: UIViewController & MFMailComposeViewControllerDelegate) {
        let receipients = [Config.email]
        let subject = Config.emailSubject
        
        var version = "unavailable"
        var build = "unavailable"
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            version = v
        }
        if let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            build = b
        }
        let messageBody = "App version \(version), build \(build)\n"
        
        let configuredMailComposeViewController = viewController.configureMailComposeViewController(recepients: receipients, subject: subject, messageBody: messageBody)
        
        if viewController.canSendMail {
            viewController.present(configuredMailComposeViewController, animated: true, completion: nil)
        } else {
            if !bruteForceSendMail(recepients: receipients, subject: subject, messageBody: messageBody) {
                // force presentation of the failure dialog
                viewController.showSendMailErrorAlert()
            }
        }
    }
    
    func bruteForceSendMail(recepients: [String], subject: String, messageBody: String) -> Bool {
        var email = "mailto:\(recepients[0])?subject=\(subject)&body=\(messageBody)"
        email = email.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""
        var worked = false
        print("Brute force email: \(subject)")
        UIApplication.shared.open(URL(string: email)!, options: [:]) { success in
            worked = success
        }
        return worked
    }
    
    func openAbout(in viewController: UIViewController, station: RadioStation? = nil) {
        let aboutController = AboutViewController()
        aboutController.currentStation = station
        aboutController.delegate = self
        viewController.present(aboutController, animated: true)
    }
}

// MARK: - LoaderControllerDelegate

extension MainCoordinator: LoaderControllerDelegate {
    func didFinishLoading(_ controller: LoaderController, stations: [RadioStation]) {
        let stationsVC = StationsViewController()
        stationsVC.delegate = self
        navigationController.setViewControllers([stationsVC], animated: false)
    }
}

// MARK: - StationsViewControllerDelegate

extension MainCoordinator: StationsViewControllerDelegate {
    
    func pushNowPlayingController(_ stationsViewController: StationsViewController, newStation: Bool) {
        let nowPlayingController = Storyboard.viewController as NowPlayingViewController
        nowPlayingController.delegate = self
        nowPlayingController.isNewStation = newStation
        navigationController.pushViewController(nowPlayingController, animated: true)
    }
    
    func didTapInfoButton(_ stationsViewController: StationsViewController) {
        openAbout(in: stationsViewController, station: StationsManager.shared.currentStation)
    }
}

// MARK: - NowPlayingViewControllerDelegate

extension MainCoordinator: NowPlayingViewControllerDelegate {
    
    func didTapInfoButton(_ nowPlayingViewController: NowPlayingViewController, station: RadioStation?) {
        openAbout(in: nowPlayingViewController, station: station)
    }

    func didTapShareButton(_ nowPlayingViewController: NowPlayingViewController, station: RadioStation, artworkURL: URL?) {
        ShareActivity.activityController(station: station, artworkURL: artworkURL, sourceView: nowPlayingViewController.view) { [weak nowPlayingViewController] controller in
            nowPlayingViewController?.present(controller, animated: true, completion: nil)
        }
    }
}

// MARK: - PopUpMenuViewControllerDelegate

extension MainCoordinator: PopUpMenuViewControllerDelegate {
    
    func didTapWebsiteButton(_ popUpMenuViewController: PopUpMenuViewController) {
        openWebsite()
    }
    
    func didTapAboutButton(_ popUpMenuViewController: PopUpMenuViewController) {
        openAbout(in: popUpMenuViewController)
    }
}

// MARK: - PopUpMenuViewControllerDelegate

extension MainCoordinator: AboutViewControllerDelegate {
    func didTapEmailButton(_ aboutViewController: AboutViewController) {
        openEmail(in: aboutViewController)
    }
    
    func didTapWebsiteButton(_ aboutViewController: AboutViewController) {
        openWebsite()
    }

    /// Reload stations from the newly chosen server and start over from the stations list.
    func didChangeStationServer(_ aboutViewController: AboutViewController) {
        navigationController.dismiss(animated: true)
        StationsManager.shared.fetch { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self,
                      let stationsVC = self.navigationController.viewControllers.first as? StationsViewController else { return }
                if self.navigationController.topViewController === stationsVC {
                    // About was opened from the list. Dismissing a sheet doesn't re-run the
                    // list's viewWillAppear, so apply its single-station rule here.
                    stationsVC.showNowPlayingIfOnlyStation()
                } else {
                    // Popping back to the list runs viewWillAppear, which applies the rule.
                    self.navigationController.popToRootViewController(animated: true)
                }
            }
        }
    }
}
