//
//  InfoDetailViewController.swift
//  Swift Radio
//
//  Created by Matthew Fecher on 7/9/15.
//  Copyright (c) 2015 MatthewFecher.com. All rights reserved.
//

import UIKit

class InfoDetailViewController: UIViewController {
    
    @IBOutlet weak var stationImageView: UIImageView!
    @IBOutlet weak var stationNameLabel: UILabel!
    @IBOutlet weak var stationLongDescTextView: UITextView!
    @IBOutlet weak var okayButton: UIButton!
    
    var currentStation: RadioStation!

    // MARK: - ViewDidLoad
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupStationText()
        setupStationLogo()
    }
    
    // MARK: - UI Helpers
    
    func setupStationText() {
        
        // Display Station Name & Short Desc
        stationNameLabel.text = currentStation.name
        
        // Display Station Long Desc
        if currentStation.longDesc == "" {
            loadDefaultText()
        } else {
            stationLongDescTextView.text = currentStation.longDesc
        }
    }
    
    func loadDefaultText() {
        // Add your own default ext
        stationLongDescTextView.text = "RadioSpiral's 24/7 captivating electronica: some of the best in the genres of electronic and ambient music, featuring live DJs and live performances."
    }
    
    func setupStationLogo() {
        
        // Display Station Image/Logo
        currentStation.getImage { [weak self] image in
            self?.stationImageView.image = image
        }
        
        // Apply shadow to Station Image
        stationImageView.applyShadow()
    }
    
    // MARK: - IBActions
    
    @IBAction func okayButtonPressed(_ sender: UIButton) {
        _ = navigationController?.popViewController(animated: true)
    }
    
    override func setValue(_ value: Any?, forUndefinedKey key: String
    ) {
    }
}
