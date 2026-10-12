//
//  LogoShareView.swift
//  SwiftRadio
//
//  Created by Cameron Mcleod on 2019-07-12.
//  Copyright © 2019 matthewfecher.com. All rights reserved.
//

import UIKit

class LogoShareView: UIView {
    
    @IBOutlet weak var albumArtImageView: UIImageView!
    @IBOutlet weak var radioShoutoutLabel: UILabel!
    @IBOutlet weak var trackTitleLabel: UILabel!
    @IBOutlet weak var trackArtistLabel: UILabel!
    @IBOutlet weak var logoImageView: UIImageView!
    
    class func instanceFromNib() -> LogoShareView {
        return UINib(nibName: "LogoShareView", bundle: nil).instantiate(withOwner: nil, options: nil)[0] as! LogoShareView
    }
    
    func shareSetup(albumArt : UIImage, radioShoutout: String, trackTitle: String, trackArtist: String) {
        // ShareActivity has already downloaded the art; set it synchronously so it's
        // present when the view is rendered to an image.
        self.albumArtImageView.image = albumArt
        let metadataManager = StationMetadataManager.shared
        if let metadata = metadataManager.getCurrentMetadata() {
            self.radioShoutoutLabel.text = radioShoutout
            self.trackTitleLabel.text = metadata.trackName
            self.trackArtistLabel.text = metadata.artistName
        } else {
            // Fallback to passed parameters
            self.radioShoutoutLabel.text = radioShoutout
            self.trackTitleLabel.text = trackTitle
            self.trackArtistLabel.text = trackArtist
        }
        self.logoImageView.image = UIImage(named: "logo")
    }
}
