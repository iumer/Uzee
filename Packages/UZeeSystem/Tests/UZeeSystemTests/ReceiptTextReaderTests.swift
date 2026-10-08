import Testing
import UZeeCore
@testable import UZeeSystem

/// AI-02: words on one printed line are joined left to right, lines run top to bottom.
@Suite("Receipt text rows")
struct ReceiptTextReaderTests {
    @Test("Label and amount on the same line are joined")
    func joinRows() {
        let pieces = [
            ReceiptPiece(text: "2,773.00", x: 0.7, y: 0.30, width: 0.2, height: 0.04),
            ReceiptPiece(text: "IMTIAZ", x: 0.3, y: 0.90, width: 0.4, height: 0.05),
            ReceiptPiece(text: "Grand Total", x: 0.1, y: 0.305, width: 0.3, height: 0.04),
            ReceiptPiece(text: "Date: 05/10/2026", x: 0.1, y: 0.80, width: 0.5, height: 0.04)
        ]
        #expect(ReceiptParser.lines(pieces) == ["IMTIAZ", "Date: 05/10/2026", "Grand Total   2,773.00"])
    }
}
