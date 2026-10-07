import CoreGraphics
import Testing
@testable import UZeeSystem

/// AI-02: words on one printed line are joined left to right, lines run top to bottom.
@Suite("Receipt text rows")
struct ReceiptTextReaderTests {
    @Test("Label and amount on the same line are joined")
    func joinRows() {
        let pieces: [(text: String, box: CGRect)] = [
            ("2,773.00", CGRect(x: 0.7, y: 0.30, width: 0.2, height: 0.04)),
            ("IMTIAZ", CGRect(x: 0.3, y: 0.90, width: 0.4, height: 0.05)),
            ("Grand Total", CGRect(x: 0.1, y: 0.305, width: 0.3, height: 0.04)),
            ("Date: 05/10/2026", CGRect(x: 0.1, y: 0.80, width: 0.5, height: 0.04))
        ]
        #expect(ReceiptTextReader.joinRows(pieces) == ["IMTIAZ", "Date: 05/10/2026", "Grand Total   2,773.00"])
    }
}
