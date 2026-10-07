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
            guard let text = document.page(at: index)?.string else { continue }
            lines += text.components(separatedBy: .newlines)
        }
        let readable = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !readable.isEmpty else { throw StatementFileProblem.noText }
        return .lines(readable)
    }
}
