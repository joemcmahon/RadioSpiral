//
//  Credits.swift
//  RadioSpiral
//
//  Created by Joe McMahon on 2/17/26.
//  Copyright © 2026 matthewfecher.com. All rights reserved.
//

import Foundation

/// A single staff credit entry
public struct CreditPair: Codable, Equatable {
    public var role: String
    public var name: String
}

/// JSON wrapper for the credits array
struct CreditsWrapper: Codable {
    let credits: [CreditPair]
}

/// Fallback credits used when remote fetch fails: the built-in list for the current time.
var fallbackCredits: [CreditPair] { builtInCredits(on: Date()) }

/// The credits built into the app. Like the bundled stations they follow `ConfigClient.launchDate`:
/// until then there is one downtime robot (Spud); from then on there are four.
func builtInCredits(on date: Date) -> [CreditPair] {
    let robots = date < ConfigClient.launchDate
        ? CreditPair(role: "Downtime DJ & attitude", name: "Spud the Ambient Robot")
        : CreditPair(role: "Downtime DJs",           name: "Spud, Igor, Roshi, and Bop")
    return [
        CreditPair(role: "Curator & founder",           name: "Mike Metlay (Mr. Spiral)"),
        CreditPair(role: "Second Life, cofounder",      name: "Diana Smethurst (Gypsy Witch)"),
        CreditPair(role: "Keeping the lights on",       name: "Paul Harriman (Edison Rex)"),
        CreditPair(role: "Bots & chats & iOS",          name: "Joe McMahon (Equinox Deschanel)"),
        CreditPair(role: "Bullhorn and cat herding",    name: "Rebekkah Hilgraves (ʞu¡0ɹʞS)"),
        CreditPair(role: "Wild enthusiasm and remixes", name: "Kyizl"),
        CreditPair(role: "General nuisance and Linux",  name: "José Carlos Cuevas"),
        CreditPair(role: "Rad artwork and sequencers",  name: "Brad Ross-MacLeod (Synchysis)"),
        CreditPair(role: "Guru meditation",             name: "Tony Gerber"),
        CreditPair(role: "Boots and pants and...",      name: "Allen Goodman (DJ Cylon)"),
        CreditPair(role: "Laminar flow",                name: "Okashii"),
        CreditPair(role: "Shadowy presence",            name: "DK Herpich (Hiraku Stenvaag)"),
        robots,
    ]
}
