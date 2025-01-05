//
//  ACEventHandler.swift
//  RadioSpiral
//
//  Created by Joe McMahon on 1/4/25.
//  Copyright © 2025 matthewfecher.com. All rights reserved.
//

import Foundation
import LDSwiftEventSource

/// Type describing a callback to send the current status to a subscriber.
public typealias MetadataCallback<T> = (T) -> Void

class ACEventHandler: EventHandler {
    
    public static let shared = ACEventHandler()
    private var eventSource: EventSource?
    
    // Anyone subscribed to the metadata stream
    private var subscribers: [MetadataCallback<ACStreamStatus>] = []
    
    /// Current status for this client. If this is the singleton client, this status should be the same
    /// for all references to the client.
    public var status = ACStreamStatus()
    
    private var serverName: String = ""
    private var shortCode: String = ""
    public var defaultDJ: String = ""
    
    private var eventSourceURL: URL?
        
    /// Updates the configuration of the `ACSSEClient` and      reconnects.
     public func configurationDidChange(serverName: String, shortCode: String) {
         self.serverName = serverName
         self.shortCode = shortCode
        // self.disconnect()
         self.constructEventSourceURL(serverName: serverName,shortCode: shortCode)
         //self.connect()
     }
    
    func constructEventSourceURL(serverName: String, shortCode: String) {
        let prefix = "https://\(serverName)/api/live/nowplaying/sse?cf_connect="
        //let json = ["sub": ["station:\(shortCode)": ["recover": true] ] ]
        let suffix = "%7B%22subs%22:%7B%22station:\(shortCode)%22:%7B%22recover%22:true%7D%7D%7D"
        self.eventSourceURL = URL(string: prefix + suffix)
    }
    
    func connect() {
        var eventHandler = ACEventHandler.shared
        var config = EventSource.Config(handler: eventHandler, url: self.eventSourceURL!)
        self.eventSource = EventSource(config: config)
        self.eventSource?.start()
    }
    
    func disconnect() {
        self.eventSource?.stop()
    }
    
    /// Adds a subscriber to the metadata returned              asynchronously by the Azuracast now-playing API.
    /// - Parameter callback: Callback function to be called    when a change to the station metadata
    /// is detected.
    public func addSubscriber(callback: @escaping               MetadataCallback<ACStreamStatus>) {
        subscribers.append(callback)
    }
    
    // MARK - Event handling
    func onOpened() {
        print("** onOpened")
    }

    func onClosed() {
        print("** onClosed")
    }

    func onMessage(eventType: String, messageEvent: LDSwiftEventSource.MessageEvent) {
        print("** onMessage received event type \(eventType) and event \(String(describing: messageEvent))")
    }

    func onComment(comment: String) {
        print("** onComment with comment \(comment)")
    }

    func onError(error: any Error) {
        print("** onError with error \(String(describing: error))")
    }
}
