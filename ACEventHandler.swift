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
    
    /// Singleton instance of the event handler so we can always pick up current status.
    public static let shared = ACEventHandler()
    private var eventSource: EventSource?
    
    // Anyone subscribed to the metadata stream
    private var subscribers: [MetadataCallback<ACStreamStatus>] = []
    
    /// Current status for this client. If this is the singleton client, this status should be the same
    /// for all references to the client.
    public var status = ACStreamStatus()
    
    private var serverName: String = ""
    private var shortCode: String = ""
   
    /// The name that we'll use if no streamer is connected.
    public var defaultDJ: String = ""
    
    private var eventSourceURL: URL?
        
    /// Updates the configuration of the `ACSSEClient` and disconnects/ reconnects.
     public func configurationDidChange(serverName: String, shortCode: String) {
         self.serverName = serverName
         self.shortCode = shortCode
        // self.disconnect()
         self.constructEventSourceURL(serverName: serverName,shortCode: shortCode)
         //self.connect()
     }
    
    // Builds out the correct SSE URL.
    private func constructEventSourceURL(serverName: String, shortCode: String) {
        let prefix = "https://\(serverName)/api/live/nowplaying/sse?cf_connect="
        //let json = ["sub": ["station:\(shortCode)": ["recover": true] ] ]
        let suffix = "%7B%22subs%22:%7B%22station:\(shortCode)%22:%7B%22recover%22:true%7D%7D%7D"
        self.eventSourceURL = URL(string: prefix + suffix)
    }
    
    // Notify subscribers of update.
    func notifySubscribers(status: ACStreamStatus) {
        for callback in subscribers { callback(status) }
    }
    
    /// Connect the SSE client.
    public func connect() {
        let eventHandler = ACEventHandler.shared
        let config = EventSource.Config(handler: eventHandler, url: self.eventSourceURL!)
        self.eventSource = EventSource(config: config)
        self.eventSource?.start()
    }
    
    /// Disconnect the SSE client.
    public func disconnect() {
        self.eventSource?.stop()
    }
    
    /// Adds a subscriber to the metadata returned  asynchronously by the Azuracast now-playing API.
    /// - Parameter callback:Callback function to be called when a change to the station metadata
    /// is detected.
    public func addSubscriber(callback: @escaping MetadataCallback<ACStreamStatus>) {
        subscribers.append(callback)
    }
    
    // MARK - Event handling
    
    // Take an action when the connection is opened. We are dependent on the data
    // from the endpoint, so we have nothing to do here.
    func onOpened() {}

    // Called when the connection closes, either because of an error, or because
    // we deliberately did so. No action for our implementation.
    func onClosed() {}

    // Called when a message is delivered. We parse the incoming metadata, and
    // update the shared status.
    func onMessage(eventType: String, messageEvent: LDSwiftEventSource.MessageEvent) {
        let data = Data(messageEvent.data.utf8)
        let parser = ParseWebSocketData(data: data, defaultDJ: defaultDJ)
        do {
            let result = try parser.parse(shortCode: shortCode)
            DispatchQueue.main.async {
                if result.changed {
                    self.status = result
                    self.notifySubscribers(status: self.status)
                }
            }
        } catch {
            print("** couldn't parse data: \(error)")
        }
    }

    // Our API doesn't send comments, so we do nothing here.
    func onComment(comment: String) {}

    // Action taken when an error occurs. We have no remedial actions to take
    // other than reconnecting, and the base library handles that with backoff.
    func onError(error: any Error) {
        print("** onError with error \(String(describing: error))")
    }
}
