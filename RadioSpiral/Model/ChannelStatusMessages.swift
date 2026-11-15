//
//  ChannelStatusMessages.swift
//  RadioSpiral
//
//  What the listener is told when a channel is offline or can't be described (task-44).
//  The phone shows it in the Now Playing banner; the lock screen and CarPlay show it as the
//  title. "Channel" is the word the station's management uses for a stream.
//
//  Audio outranks metadata, so a frozen stream ("Connection lost") comes before a message about
//  the channel's information. Only an offline channel, which makes the audio stop too, comes
//  before it.
//

import Foundation

enum ChannelStatusMessages {

    /// The text for the banner on the Now Playing screen, or nil when there is nothing to say.
    static func phoneBanner(connection: MetadataConnectionState, isStalled: Bool) -> String? {
        if connection == .offline { return "This channel is offline" }
        if isStalled { return "Connection lost — reconnecting…" }
        if connection == .failed { return "Can't load this channel's information" }
        return nil
    }

    /// True when there is no track to time, so the time bubble shows its placeholder instead of
    /// counting up from zero.
    static func showsNoTime(connection: MetadataConnectionState) -> Bool {
        connection == .offline
    }

    /// The title for the lock screen and CarPlay, or nil to leave the track's title alone.
    static func nowPlayingTitle(connection: MetadataConnectionState) -> String? {
        switch connection {
        case .offline: return "Channel offline"
        case .failed: return "Channel unavailable"
        case .connected, .connecting, .disconnected, .reconnecting: return nil
        }
    }
}
