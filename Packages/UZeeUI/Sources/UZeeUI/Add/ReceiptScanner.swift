import SwiftUI
import UIKit
import VisionKit

/// The iPhone's own document scanner: hold it over a receipt and it finds the edges, straightens the paper
/// and captures by itself (AI-02). A long receipt scanned in parts comes back as one tall image.
struct ReceiptScanner: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let parent: ReceiptScanner

        init(_ parent: ReceiptScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<min(scan.pageCount, 4)).map { scan.imageOfPage(at: $0) }
            parent.dismiss()
            parent.completion(UIImage.stacked(pages))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
            parent.completion(nil)
        }
    }
}

extension UIImage {
    /// Pages one under the other, top to bottom, on white; nil when there are none.
    static func stacked(_ pages: [UIImage]) -> UIImage? {
        guard let first = pages.first else { return nil }
        guard pages.count > 1 else { return first }
        let width = pages.map(\.size.width).max() ?? first.size.width
        let heights = pages.map { $0.size.height * width / max($0.size.width, 1) }
        let size = CGSize(width: width, height: heights.reduce(0, +))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            var y: CGFloat = 0
            for (page, height) in zip(pages, heights) {
                page.draw(in: CGRect(x: 0, y: y, width: width, height: height))
                y += height
            }
        }
    }
}

extension UIImage {
    /// Small enough to read quickly, big enough to keep small print: a long receipt keeps its width
    /// instead of shrinking to fit a square limit.
    func resizedForReading() -> UIImage {
        let ratio = size.height / max(size.width, 1)
        let maxSide = ratio > 2 ? min(7_200, 1_800 * ratio) : 2_400
        return resizedForReceipt(maxSide: maxSide)
    }
}
