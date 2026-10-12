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

    /// Rebuilds a page's text row by row from where each character sits, so a table row reads as one line
    /// ("05 Oct 2026   IBFT SENDING …   15,850.00Dr   35.48") whatever order the PDF stores its text in.
    /// NayaPay, for one, stores a row's description after its amounts (statement check, 2026-10-13).
    /// Wide gaps between columns become three spaces, and indentation becomes leading spaces.
    static func layoutLines(_ page: PDFPage) -> [String] {
        guard let string = page.string, !string.isEmpty else { return [] }
        let text = string as NSString
        // Word by word: PDFKit's per-character bounds can be off on some PDFs (NayaPay), a word's own range isn't.
        struct Glyph {
            var box: CGRect
            var character: String
        }
        var glyphs: [Glyph] = []
        let words = try? NSRegularExpression(pattern: #"\S+"#)
        for match in words?.matches(in: string, range: NSRange(location: 0, length: text.length)) ?? [] {
            guard let selection = page.selection(for: match.range) else { continue }
            let box = selection.bounds(for: page)
            guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { continue }
            glyphs.append(Glyph(box: box, character: text.substring(with: match.range)))
        }
        guard !glyphs.isEmpty else { return [] }
        let widths = glyphs.map { $0.box.width / CGFloat(max($0.character.count, 1)) }.sorted()
        let charWidth = max(widths[widths.count / 2], 1)
        let left = glyphs.map(\.box.minX).min() ?? 0

        // PDF space runs bottom-up: top rows first, then left to right.
        glyphs.sort { $0.box.midY > $1.box.midY }
        var rows: [[Glyph]] = []
        var current: [Glyph] = []
        var rowY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for glyph in glyphs {
            if !current.isEmpty, abs(glyph.box.midY - rowY) <= min(rowHeight, glyph.box.height) * 0.45 {
                current.append(glyph)
            } else {
                if !current.isEmpty { rows.append(current) }
                current = [glyph]
                rowY = glyph.box.midY
                rowHeight = glyph.box.height
            }
        }
        if !current.isEmpty { rows.append(current) }

        return rows.map { row in
            let sorted = row.sorted { $0.box.minX < $1.box.minX }
            var line = String(repeating: " ", count: min(max(Int(((sorted[0].box.minX - left) / charWidth).rounded()), 0), 80))
            var previousMaxX: CGFloat?
            for glyph in sorted {
                if let previousMaxX {
                    let gap = glyph.box.minX - previousMaxX
                    line += gap > charWidth * 1.8 ? "   " : gap > charWidth * 0.2 ? " " : ""
                }
                line += glyph.character
                previousMaxX = max(previousMaxX ?? glyph.box.maxX, glyph.box.maxX)
            }
            return line
        }
    }
}
