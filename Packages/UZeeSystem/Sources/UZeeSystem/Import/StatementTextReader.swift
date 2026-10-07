import Foundation
import PDFKit
import UZeeCore

/// Text from a statement file on the device (IMP-01, IMP-07). PDFs are read with PDFKit; nothing is uploaded.
public enum StatementTextReader {
    public enum Content: Sendable {
        case lines([String])
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
        var lines: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let rebuilt = layoutLines(page)
            if !rebuilt.isEmpty {
                lines += rebuilt
            } else if let text = page.string {
                lines += text.components(separatedBy: .newlines)
            }
        }
        let readable = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !readable.isEmpty else { throw StatementFileProblem.noText }
        return .lines(readable)
    }

    private struct Glyph {
        var minX: CGFloat
        var maxX: CGFloat
        var midY: CGFloat
        var height: CGFloat
        var unit: unichar
    }

    /// Rebuilds a page's text line by line from where each character sits, so a table row reads as one line
    /// ("05 Oct 2026   IBFT SENDING …   15,850.00Dr   35.48") whatever order the PDF stores its text in.
    /// Wide gaps between columns become three spaces, and indentation becomes leading spaces.
    static func layoutLines(_ page: PDFPage) -> [String] {
        guard let string = page.string else { return [] }
        let text = string as NSString
        let count = min(page.numberOfCharacters, text.length)
        guard count > 0 else { return [] }
        var glyphs: [Glyph] = []
        glyphs.reserveCapacity(count)
        for index in 0..<count {
            let unit = text.character(at: index)
            if unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09 || unit == 0xA0 { continue }
            let box = page.characterBounds(at: index)
            guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { continue }
            glyphs.append(Glyph(minX: box.minX, maxX: box.maxX, midY: box.midY, height: box.height, unit: unit))
        }
        guard !glyphs.isEmpty else { return [] }
        let widths = glyphs.map { $0.maxX - $0.minX }.sorted()
        let charWidth = max(widths[widths.count / 2], 1)
        let left = glyphs.map(\.minX).min() ?? 0

        // PDF space runs bottom-up: top lines first, then left to right.
        glyphs.sort { $0.midY > $1.midY }
        var rows: [[Glyph]] = []
        var current: [Glyph] = []
        var lineY: CGFloat = 0
        var lineHeight: CGFloat = 0
        for glyph in glyphs {
            if !current.isEmpty, abs(glyph.midY - lineY) <= max(lineHeight, glyph.height) * 0.45 {
                current.append(glyph)
                // Keep the line's centre steady as glyphs join.
                lineY = (lineY * CGFloat(current.count - 1) + glyph.midY) / CGFloat(current.count)
                lineHeight = max(lineHeight, glyph.height)
            } else {
                if !current.isEmpty { rows.append(current) }
                current = [glyph]
                lineY = glyph.midY
                lineHeight = glyph.height
            }
        }
        if !current.isEmpty { rows.append(current) }

        return rows.map { row in
            let sorted = row.sorted { $0.minX < $1.minX }
            var units: [unichar] = Array(repeating: 0x20, count: min(Int(((sorted[0].minX - left) / charWidth).rounded()), 80))
            var previousMaxX: CGFloat?
            for glyph in sorted {
                if let previousMaxX {
                    let gap = glyph.minX - previousMaxX
                    if gap > charWidth * 2 {
                        units += [0x20, 0x20, 0x20]
                    } else if gap > charWidth * 0.3 {
                        units.append(0x20)
                    }
                }
                units.append(glyph.unit)
                previousMaxX = max(previousMaxX ?? glyph.maxX, glyph.maxX)
            }
            return String(utf16CodeUnits: units, count: units.count)
        }
    }
}
