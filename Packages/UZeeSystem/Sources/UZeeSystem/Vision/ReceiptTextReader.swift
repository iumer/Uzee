import CoreGraphics
import Foundation
import ImageIO
import UZeeCore
import Vision

/// On-device text recognition for receipt photos (AI-02). Nothing leaves the device.
public enum ReceiptTextReader {
    public enum Failure: Error, Sendable {
        case notAnImage
    }

    /// Every piece of text on the receipt with where it sits, so the parser can pair a label ("Amount") with
    /// the value next to it even when a tilted photo puts them on different lines.
    public static func pieces(from imageData: Data) throws -> [ReceiptPiece] {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.notAnImage }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return ReceiptPiece(text: text, x: Double(box.minX), y: Double(box.minY),
                                width: Double(box.width), height: Double(box.height))
        }
    }

    /// The receipt's text as lines, top to bottom.
    public static func lines(from imageData: Data) throws -> [String] {
        ReceiptParser.lines(try pieces(from: imageData))
    }
}
