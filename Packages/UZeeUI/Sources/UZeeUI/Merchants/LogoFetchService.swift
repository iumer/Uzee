import Foundation

/// Fetches a brand logo PNG for a guessed domain. Tries Clearbit Logo first, then DDG favicon.
/// Both services are free, require no API key, and receive only domain names (no user data).
actor LogoFetchService {
    static let shared = LogoFetchService()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    /// Returns PNG data for the payee name, or nil if nothing was found.
    func fetch(payeeName: String) async -> (data: Data, sourceURL: String)? {
        for domain in Self.guessDomains(payeeName) {
            if let result = await tryDomain(domain) { return result }
        }
        return nil
    }

    private func tryDomain(_ domain: String) async -> (data: Data, sourceURL: String)? {
        // Clearbit Logo API: returns a proper SVG or PNG brand mark.
        if let result = await fetch(url: "https://logo.clearbit.com/\(domain)") { return (result, "clearbit:\(domain)") }
        // DDG favicon as fallback.
        if let result = await fetch(url: "https://icons.duckduckgo.com/ip3/\(domain).ico") { return (result, "ddg:\(domain)") }
        return nil
    }

    private func fetch(url string: String) async -> Data? {
        guard let url = URL(string: string) else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              data.count > 100,            // ignore tiny "not found" placeholders
              data.count < 64 * 1024 else { return nil }
        return data
    }

    /// Guess 2–3 domain names from a raw payee string (e.g. "NETFLIX INTERNATIONAL" → ["netflix.com"]).
    static func guessDomains(_ payee: String) -> [String] {
        var clean = payee.lowercased()
        // Strip noise words and characters banks add.
        for noise in ["pvt", "ltd", "llc", "inc", "corp", "store", "shop", "retail", "online",
                      "pakistan", "karachi", "lahore", "islamabad", "international", "pk",
                      "pos purchase", "pos ", "fcpk", "lmra"] {
            clean = clean.replacingOccurrences(of: "\\b\(noise)\\b", with: "", options: .regularExpression)
        }
        clean = clean.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
        let slug = clean.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: "-")
        guard !slug.isEmpty else { return [] }
        return ["\(slug).com", "\(slug).com.pk", "\(slug).pk"]
    }
}

/// A candidate brand found in the user's transactions, ready for logo lookup.
struct LogoCandidate: Identifiable, Sendable {
    let payeeName: String
    var id: String { payeeName }
    var transactionCount: Int
    var logoData: Data?
    var sourceURL: String?
    var isFetching = false
    var skipped = false
}
