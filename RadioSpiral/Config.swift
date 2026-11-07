//
//  SwiftRadio-Settings.swift
//  Swift Radio
//
//  Created by Matthew Fecher on 7/2/15.
//  Copyright (c) 2015 MatthewFecher.com. All rights reserved.
//

import UIKit

struct Config {

    static let debugLog = true

    // Station loading configuration
    // Priority: useConfigClient → stationsURL
    static let useConfigClient = true  // Use dynamic ConfigClient for stations
    static let stationsURL = "https://raw.githubusercontent.com/joemcmahon/radiospiral-config/master/stations.json"

    // Set this to "true" to enable the search bar
    static let searchable = false

    // Contact info
    static let website = "https://radiospiral.net"
    static let email = "radio@pemungkah.com"
    static let emailSubject = "\(Bundle.main.appName) App Question"
}

