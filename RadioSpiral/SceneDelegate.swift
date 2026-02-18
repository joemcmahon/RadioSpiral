//
//  SceneDelegate.swift
//  RadioSpiral
//
//  Created on 2025-11-11.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    var coordinator: MainCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        // Create the window
        window = UIWindow(windowScene: windowScene)

        // Create coordinator and navigation controller
        let navigationController = UINavigationController()
        coordinator = MainCoordinator(navigationController: navigationController)

        // Set root view controller
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()

        // Start the coordinator
        coordinator?.start()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Only reconnect if the WebSocket isn't already healthy.
        // Unconditional connect() tears down the existing connection,
        // causing a visible "reconnecting" flash and audio interruption.
        let client = ACWebSocketClient.shared
        if client.status.connection != .connected && client.status.connection != .connecting {
            client.connect()
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // Only disconnect websocket if audio is NOT playing
        if !RadioPlayer.shared.isPlaying {
            ACWebSocketClient.shared.disconnect()
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
    }
}
