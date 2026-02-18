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

/// Fallback credits used when remote fetch fails
let fallbackCredits: [CreditPair] = [
    CreditPair(role: "Curator & founder",           name: "Mike Metlay (Mr. Spiral)"),
    CreditPair(role: "Second Life, cofounder",      name: "Diana Smethurst (Gypsy Witch)"),
    CreditPair(role: "Keeping the lights on",       name: "Paul Harriman (Edison Rex)"),
    CreditPair(role: "Bots & chats & iOS",          name: "Joe McMahon (Equinox Deschanel)"),
    CreditPair(role: "Bullhorn",                    name: "Rebekkah Hilgraves (ʞu¡0ɹʞS)"),
    CreditPair(role: "Wild enthusiasm and remixes", name: "Kyzil"),
    CreditPair(role: "General nuisance and Linux",  name: "José Carlos Cuevas"),
    CreditPair(role: "Rad artwork and sequencers",   name: "Brad Ross-MacLeod (Synchysis)"),
    CreditPair(role: "Downtime DJ & attitude",      name: "Spud the Ambient Robot"),
]
