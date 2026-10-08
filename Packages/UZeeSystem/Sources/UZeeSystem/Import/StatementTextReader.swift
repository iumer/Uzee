import Foundation
import PDFKit
import UZeeCore

/// Text from a statement file on the device (IMP-01, IMP-07). PDFs are read with PDFKit; nothing is uploaded.
public enum StatementTextReader {
    public enum Content: Sendable {
        /// The PDF's text read two ways: rebuilt row by row from where the text sits, then in PDFKit's own
        /// order. The parser keeps whichever gives more transactions.
        case pdf([[String]])
        case csv(String)
    }

    /// Reads a PDF (unlocking it with `password` when it has one) or a CSV/text export.
    public static func read(_ url: URL, password: String?) throws -> Content {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        if ext == "csv" || ext == "txt" || ext == "tsv" {
            guard let data = try? Data(contentsOf: url) else { throw StatementFileProblem.unreadable }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw StatementFileProblem.unreadable
            }
            return .csv(ext == "tsv" ? text.replacingOccurrences(of: "\t", with: ",") : text)
        }
        guard let document = PDFDocument(url: url) else { throw StatementFileProblem.unreadable }
        if document.isLocked {
            guard let password, !password.isEmpty else { throw StatementFileProblem.needsPassword }
            guard document.unlock(withPassword: password) else { throw StatementFileProblem.wrongPassword }
        }
        var layout: [String] = []
        var plain: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = page.string ?? ""
            let pageLines = text.components(separatedBy: .newlines)
            plain += pageLines
            // Use the rebuilt rows only when they hold the same characters as the page; otherwise PDFKit's order.
            let rebuilt = layoutLines(page)
            let expected = visibleCount(text)
            if !rebuilt.isEmpty, abs(visibleCount(rebuilt.joined()) - expected) <= max(2, expected / 50) {
                layout += rebuilt
            } else {
                layout += pageLines
            }
        }
        func readable(_ lines: [String]) -> [String] { lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        let versions = [readable(layout), readable(plain)].filter { !$0.isEmpty }
        guard let first = versions.first else { throw StatementFileProblem.noText }
        return .pdf(versions.count > 1 && versions[1] == first ? [first] : versions)
    }

    private static func visibleCount(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (CharacterSet.whitespacesAndNewlines.contains($1) ? 0 : 1) }
    }

    private struct Piece {
        var box: CGRect
        var text: String
    }

    /// Rebuilds a page's text row by row from PDFKit's text lines and where they sit, so a table row reads as
    /// one line ("05 Oct 2026   IBFT SENDING …   15,850.00Dr   35.48") whatever order the PDF stores its text in.
    /// Wide gaps between columns become three spaces, and indentation becomes leading spaces.
    static func layoutLines(_ page: PDFPage) -> [String] {
        guard let all = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
        var pieces: [Piece] = []
        for line in all.selectionsByLine() {
            guard let raw = line.string else { continue }
            let box = line.bounds(for: page)
            guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { continue }
            // A selection line can still hold several rows; share its height between them, top first.
            let parts = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !parts.isEmpty else { continue }
            let height = box.height / CGFloat(parts.count)
            for (offset, part) in parts.enumerated() {
                let text = part.trimmingCharacters(in: .whitespaces)
                let partBox = CGRect(x: box.minX, y: box.maxY - height * CGFloat(offset + 1), width: box.width, height: height)
                pieces.append(Piece(box: partBox, text: text))
            }
        }
        guard !pieces.isEmpty else { return [] }
        let widths = pieces.map { $0.box.width / CGFloat(max($0.text.count, 1)) }.sorted()
        let charWidth = max(widths[widths.count / 2], 1)
        let left = pieces.map(\.box.minX).min() ?? 0

        // PDF space runs bottom-up: top rows first, then left to right.
        pieces.sort { $0.box.midY > $1.box.midY }
        var rows: [[Piece]] = []
        var current: [Piece] = []
        var rowY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for piece in pieces {
            if !current.isEmpty, abs(piece.box.midY - rowY) <= min(rowHeight, piece.box.height) * 0.5 {
                current.append(piece)
            } else {
                if !current.isEmpty { rows.append(current) }
                current = [piece]
                rowY = piece.box.midY
                rowHeight = piece.box.height
            }
        }
        if !current.isEmpty { rows.append(current) }

        return rows.map { row in
            let sorted = row.sorted { $0.box.minX < $1.box.minX }
            var line = String(repeating: " ", count: min(max(Int(((sorted[0].box.minX - left) / charWidth).rounded()), 0), 80))
            var previousMaxX: CGFloat?
            for piece in sorted {
                if let previousMaxX {
                    let gap = piece.box.minX - previousMaxX
                    line += gap > charWidth * 2 ? "   " : gap > charWidth * 0.25 ? " " : ""
                }
                line += piece.text
                previousMaxX = max(previousMaxX ?? piece.box.maxX, piece.box.maxX)
            }
            return line
        }
    }
}
