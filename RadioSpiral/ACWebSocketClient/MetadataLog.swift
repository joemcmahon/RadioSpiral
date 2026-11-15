//
//  MetadataLog.swift
//  ACWebSocketClient
//
//  A record, outside debug builds, of messages from the metadata server that the app could not
//  use (task-44). It goes to the unified log (Console, or a sysdiagnose from a listener's device),
//  not to the screen. A record says what happened and never carries the message itself.
//

import Foundation
import os

enum MetadataLog {

    struct Record: Equatable {
        enum Kind: Equatable {
            /// A message we recognized or could read as JSON, but didn't use.
            case ignored
            /// A message that could not be parsed at all.
            case failure
        }
        let kind: Kind
        let detail: String
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RadioSpiral", category: "metadata")

    /// Where records go. Tests replace it so nothing reaches the real log.
    static var sink: (Record) -> Void = defaultSink

    static let defaultSink: (Record) -> Void = { record in
        switch record.kind {
        case .ignored: logger.notice("Metadata message ignored: \(record.detail, privacy: .public)")
        case .failure: logger.error("Metadata message failed to parse: \(record.detail, privacy: .public)")
        }
    }

    static func ignored(_ detail: String) { sink(Record(kind: .ignored, detail: detail)) }
    static func failure(_ detail: String) { sink(Record(kind: .failure, detail: detail)) }
}
