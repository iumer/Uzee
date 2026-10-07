import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device text recognition for receipt photos (AI-02). Nothing leaves the device.
public enum ReceiptTextReader {
    public enum Failure: Error, Sendable {
        case notAnImage
    }

    /// The receipt's text as lines, top to bottom. Words on the same printed line (a label on the left and
    /// its amount on the right) are joined, so "Grand Total" and "2,773.00" stay together.
    public static func lines(from imageData: Data) throws -> [String] {
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
        let pieces: [(text: String, box: CGRect)] = (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return (text, observation.boundingBox)
        }
        return joinRows(pieces)
    }

    /// Groups pieces whose vertical centres are close into one line, left to right. Vision's boxes are
    /// normalised with the origin at the bottom left.
    static func joinRows(_ pieces: [(text: String, box: CGRect)]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var rows: [[(text: String, box: CGRect)]] = []
        for piece in sorted {
            if let last = rows.last?.first, abs(last.box.midY - piece.box.midY) < max(last.box.height, piece.box.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "   ") }
    }
}
