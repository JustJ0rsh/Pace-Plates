import QuickLookThumbnailing
import UniformTypeIdentifiers
import UIKit

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let size = request.maximumSize

        let reply = QLThumbnailReply(contextSize: size) {
            guard let ctx = UIGraphicsGetCurrentContext() else { return false }
            ctx.setFillColor(UIColor.clear.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))

            // Try to load the icon shipped with the extension bundle
            let bundle = Bundle(for: ThumbnailProvider.self)
            var image: UIImage?
            if let url = bundle.url(forResource: "PaceplateDocIcon@3x", withExtension: "png") ??
                         bundle.url(forResource: "PaceplateDocIcon@2x", withExtension: "png") ??
                         bundle.url(forResource: "PaceplateDocIcon", withExtension: "png") ??
                         bundle.url(forResource: "PPWorkoutIcon@3x", withExtension: "png") ??
                         bundle.url(forResource: "PPWorkoutIcon@2x", withExtension: "png") ??
                         bundle.url(forResource: "PPWorkoutIcon", withExtension: "png") {
                if let data = try? Data(contentsOf: url) {
                    image = UIImage(data: data)
                }
            }

            // Fallback to a simple glyph if image cannot be loaded
            if let image = image {
                let drawSide = min(size.width, size.height) * 0.8
                let rect = CGRect(x: (size.width - drawSide) / 2,
                                  y: (size.height - drawSide) / 2,
                                  width: drawSide,
                                  height: drawSide)
                image.draw(in: rect)
            } else {
                let rect = CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.6, height: size.height * 0.6)
                ctx.setFillColor(UIColor.systemGray5.cgColor)
                ctx.fill(rect)
            }
            return true
        }

        handler(reply, nil)
    }
}
