import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Runs away from the UI thread; bounds decoding before allocating an image.
enum ScreenshotClipboardImage {
    static func png(from url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 128 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 80_000_000,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
        if CGImageSourceGetType(source) as String? == UTType.png.identifier {
            return try? Data(contentsOf: url)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
