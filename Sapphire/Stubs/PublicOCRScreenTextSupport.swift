//
//  PublicOCRScreenTextSupport.swift
//  Sapphire
//
//  Display geometry shared by the public Mirror fullscreen presentation.
//

#if !SAPPHIRE_FULL_BUILD
import CoreGraphics

enum OCRScreenTextSupport {
    static func indexOfScreen(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        let validIndices = frames.indices.filter {
            !frames[$0].isNull && !frames[$0].isInfinite && !frames[$0].isEmpty
        }
        guard point.x.isFinite, point.y.isFinite else { return validIndices.first }
        if let index = validIndices.first(where: { frames[$0].contains(point) }) {
            return index
        }
        // Screen layouts can contain gaps, and a display can disconnect between reading
        // the pointer and the screen list. Keep fullscreen on the closest remaining display.
        return validIndices.min {
            distanceSquared(from: point, to: frames[$0]) < distanceSquared(from: point, to: frames[$1])
        }
    }

    private static func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}
#endif
