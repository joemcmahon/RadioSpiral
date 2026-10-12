//
//  ShareActivity.swift
//  SwiftRadio
//
//  Created by Fethi El Hassasna on 2019-08-20.
//  Copyright © 2019 matthewfecher.com. All rights reserved.
//

import UIKit
import LinkPresentation

struct ShareActivity {
    
    static func activityController(station: RadioStation, artworkURL: URL?, sourceView: UIView, _ completion: @escaping (UIActivityViewController) -> Void) {
                
        getImage(station: station, artworkURL: artworkURL) { image in
            let cover = image ?? #imageLiteral(resourceName: "albumArt")
            let shareImage = generateImage(from: cover, station: station)
            
            let activityViewController = UIActivityViewController(activityItems: [ShareItem(image: shareImage, preview: cover, title: station.shoutout)], applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceRect = CGRect(x: sourceView.center.x, y: sourceView.center.y, width: 0, height: 0)
            activityViewController.popoverPresentationController?.sourceView = sourceView
            activityViewController.popoverPresentationController?.permittedArrowDirections = UIPopoverArrowDirection(rawValue: 0)
            
            activityViewController.completionWithItemsHandler = {(activityType: UIActivity.ActivityType?, completed: Bool, returnedItems:[Any]?, error: Error?) in
                if completed {
                    // do something on completion if you want
                }
            }
            
            completion(activityViewController)
        }
    }
    
    private static func getImage(station: RadioStation, artworkURL: URL?, _ completion: @escaping (UIImage?) -> Void) {
        if let artworkURL = artworkURL {
            UIImage.image(from: artworkURL) { completion($0) }
        } else {
            station.getImage { completion($0) }
        }
    }
    private static func generateImage(from image: UIImage, station: RadioStation) -> UIImage {
        let logoShareView = LogoShareView.instanceFromNib()
        let metadata = StationMetadataManager.shared.getCurrentMetadata()
        let trackTitle = metadata?.trackName ?? station.name
        let trackArtist = metadata?.artistName ?? station.desc

        logoShareView.shareSetup(albumArt: image, radioShoutout: station.shoutout, trackTitle: trackTitle, trackArtist: trackArtist)

        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: logoShareView.bounds.size, format: format)
        return renderer.image { _ in
            logoShareView.drawHierarchy(in: logoShareView.bounds, afterScreenUpdates: true)
        }
    }
}

/// The composed share image, plus metadata so the share sheet header shows the plain
/// cover as a thumbnail with the shoutout as the title. Both are written as temporary JPEG
/// files: the header draws a thumbnail reliably from a file, not from an in-memory UIImage.
/// The header only uses this metadata when the share has a single item, so the shoutout
/// isn't sent separately (it's printed on the composed image).
private final class ShareItem: NSObject, UIActivityItemSource {
    private let payload: Any
    private let metadata = LPLinkMetadata()

    init(image: UIImage, preview: UIImage, title: String) {
        metadata.title = title
        let shareURL = ShareItem.writeJPEG(image, name: "RadioSpiral.jpg")
        payload = shareURL ?? image
        if let shareURL {
            metadata.originalURL = shareURL
            metadata.url = shareURL
        }
        if let previewURL = ShareItem.writeJPEG(preview, name: "RadioSpiral-cover.jpg") {
            metadata.imageProvider = NSItemProvider(contentsOf: previewURL)
            metadata.iconProvider = NSItemProvider(contentsOf: previewURL)
        } else {
            metadata.imageProvider = NSItemProvider(object: preview)
            metadata.iconProvider = NSItemProvider(object: preview)
        }
    }

    private static func writeJPEG(_ image: UIImage, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = image.jpegData(compressionQuality: 0.9),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        payload
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        payload
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        metadata
    }
}
