import SwiftUI
import UIKit
import UZeeCore

/// Brand logos chosen in Settings › Brand logos (owner, 2026-10-15). One logo per brand ("foodpanda"), so it shows on every
/// transaction and bill from that source, past and future: "Foodpanda Karachi" and "FOODPANDA" are the same brand.
/// Stored on this iPhone: a PNG per brand plus a small index.
@MainActor @Observable
final class LogoStore {
    static let shared = LogoStore()

    struct Entry: Codable, Hashable {
        var domain: String
        var file: String
    }

    private(set) var entries: [String: Entry] = [:]
    /// Brands looked up and not found, or turned down, so a search doesn't offer them again.
    private(set) var skipped: Set<String> = []
    private var cache: [String: UIImage] = [:]

    private let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("UZee/Logos", isDirectory: true)
    }()
    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    private struct Index: Codable {
        var entries: [String: Entry]
        var skipped: [String]
    }

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL), let index = try? JSONDecoder().decode(Index.self, from: data) {
            entries = index.entries
            skipped = Set(index.skipped)
        }
    }

    /// "Foodpanda Karachi PK" → "foodpanda"; "K-Electric" → "k electric"; "Lama Retail" → "lama retail".
    nonisolated static func brand(_ name: String?) -> String? {
        guard var name else { return nil }
        // Bills are named "Internet · Nayatel", "Gas bill · SNGPL": the company is after the dot.
        if let dot = name.range(of: "·") { name = String(name[dot.upperBound...]) }
        // "Paid to FOODPANDA", "Online Paid to APPLE.COM/BILL": what follows "paid to".
        if let to = name.range(of: "paid to ", options: .caseInsensitive) { name = String(name[to.upperBound...]) }
        let noise: Set<String> = ["pk", "pak", "pakistan", "karachi", "lahore", "islamabad", "rawalpindi", "lhr", "khi", "isb",
                                  "pvt", "ltd", "limited", "private", "the", "online", "store", "co", "inc", "llc"]
        let words = NameKey.make(name).split(separator: " ").map(String.init)
            .filter { !noise.contains($0) && !$0.allSatisfy(\.isNumber) && $0.count > 1 }
        guard let first = words.first, !genericWords.contains(first) else { return nil }
        if first.count >= 5 || words.count == 1 { return first }
        return words.prefix(2).joined(separator: " ")
    }

    /// Everyday words that aren't a brand ("Salary", "Rent", "Office rent").
    nonisolated static let genericWords: Set<String> = [
        "salary", "rent", "office", "internet", "electricity", "gas", "water", "fuel", "petrol", "bill", "bills", "fee", "fees",
        "transfer", "funds", "fund", "cash", "atm", "payment", "refund", "reimbursement", "bonus", "income", "groceries", "grocery",
        "lunch", "dinner", "breakfast", "food", "home", "house", "car", "bike", "mobile", "phone", "school", "tuition", "doctor",
        "medicine", "charges", "tax", "zakat", "sadaqah", "donation", "gift", "money", "balance", "adjustment", "kameti", "committee",
        "raast", "ibft", "pos", "debit", "credit", "card", "visa", "mastercard", "online", "received", "sent", "incoming", "outgoing",
        "moved", "currency", "conversion", "converted", "staff", "maid", "driver", "plumber", "electrician", "tea", "snacks"
    ]

    func image(for name: String?) -> UIImage? {
        guard let brand = Self.brand(name), let entry = entries[brand] else { return nil }
        if let cached = cache[brand] { return cached }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(entry.file)), let image = UIImage(data: data) else { return nil }
        cache[brand] = image
        return image
    }

    func hasLogo(_ brand: String) -> Bool { entries[brand] != nil }
    func isSkipped(_ brand: String) -> Bool { skipped.contains(brand) }

    func save(_ brand: String, domain: String, png: Data) {
        let file = brand.replacingOccurrences(of: " ", with: "-") + ".png"
        try? png.write(to: folder.appendingPathComponent(file), options: .atomic)
        entries[brand] = Entry(domain: domain, file: file)
        cache[brand] = UIImage(data: png)
        skipped.remove(brand)
        persist()
    }

    func skip(_ brands: [String]) {
        skipped.formUnion(brands)
        persist()
    }

    func remove(_ brand: String) {
        if let entry = entries[brand] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(entry.file)) }
        entries[brand] = nil
        cache[brand] = nil
        persist()
    }

    private func persist() {
        let index = Index(entries: entries, skipped: Array(skipped))
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexURL, options: .atomic) }
    }
}

/// Looks a brand up online: its website from Clearbit's free company search, then that site's icon from Google's (or
/// DuckDuckGo's) icon service. Only the brand name is sent, never amounts or anything else.
enum LogoFinder {
    struct Found: Identifiable, Hashable {
        var brand: String
        var shownName: String
        var domain: String
        var png: Data
        var id: String { brand }
    }

    static func find(_ brand: String, shownName: String) async -> Found? {
        guard let domain = await domain(for: brand), let png = await icon(for: domain) else { return nil }
        return Found(brand: brand, shownName: shownName, domain: domain, png: png)
    }

    private struct Suggestion: Decodable {
        let name: String
        let domain: String
    }

    /// Sites for names Clearbit doesn't know or gets wrong.
    static let knownDomains: [String: String] = [
        "chatgpt": "chatgpt.com", "openai": "openai.com", "anthropic": "anthropic.com", "claude": "claude.ai", "cursor": "cursor.com",
        "github": "github.com", "godaddy": "godaddy.com", "apple": "apple.com", "icloud": "icloud.com", "netflix": "netflix.com",
        "spotify": "spotify.com", "youtube": "youtube.com", "google": "google.com", "amazon": "amazon.com", "dlocal": "dlocal.com",
        "foodpanda": "foodpanda.pk", "careem": "careem.com", "uber": "uber.com", "indrive": "indrive.com", "bykea": "bykea.com",
        "daraz": "daraz.pk", "nayatel": "nayatel.com", "ptcl": "ptcl.com.pk", "sngpl": "sngpl.com.pk", "ssgc": "ssgc.com.pk",
        "k electric": "ke.com.pk", "kelectric": "ke.com.pk", "lesco": "lesco.gov.pk", "jazz": "jazz.com.pk", "zong": "zong.com.pk",
        "ufone": "ufone.com", "telenor": "telenor.com.pk", "hbl": "hbl.com", "meezan": "meezanbank.com", "mcb": "mcb.com.pk",
        "ubl": "ubldigital.com", "easypaisa": "easypaisa.com.pk", "jazzcash": "jazzcash.com.pk", "sadapay": "sadapay.pk",
        "nayapay": "nayapay.com", "imtiaz": "imtiaz.com.pk", "shell": "shell.com", "pso": "psopk.com", "kfc": "kfc.com.pk",
        "mcdonalds": "mcdonalds.com.pk", "starbucks": "starbucks.com", "khaadi": "khaadi.com", "outfitters": "outfitters.com.pk",
        "sapphire": "pk.sapphireonline.pk", "lama retail": "lamaretail.com", "payoneer": "payoneer.com", "fiverr": "fiverr.com",
        "upwork": "upwork.com", "airbnb": "airbnb.com", "booking": "booking.com", "pia": "piac.com.pk", "airblue": "airblue.com"
    ]

    static func domain(for brand: String) async -> String? {
        if let known = knownDomains[brand] ?? knownDomains[brand.replacingOccurrences(of: " ", with: "")] { return known }
        var parts = URLComponents(string: "https://autocomplete.clearbit.com/v1/companies/suggest")!
        parts.queryItems = [URLQueryItem(name: "query", value: brand)]
        guard let url = parts.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode([Suggestion].self, from: data) else { return nil }
        let key = NameKey.make(brand).replacingOccurrences(of: " ", with: "")
        // The name has to match; a Pakistani site wins when there are several ("foodpanda.pk", "ke.com.pk").
        let matching = list.filter {
            let name = NameKey.make($0.name).replacingOccurrences(of: " ", with: "")
            return name == key || name.hasPrefix(key) || key.hasPrefix(name)
        }
        // The site has to carry the name too ("imtiaz.com.pk" for Imtiaz), not just any company called something similar.
        let named = matching.filter { suggestion in
            let site = suggestion.domain.lowercased().filter(\.isLetter)
            return site.contains(key) || key.contains(site.prefix(max(4, site.count - 5)))
        }
        return (named.first { $0.domain.hasSuffix(".pk") } ?? named.first)?.domain
    }

    static func icon(for domain: String) async -> Data? {
        let sources = ["https://www.google.com/s2/favicons?domain=\(domain)&sz=128", "https://icons.duckduckgo.com/ip3/\(domain).ico"]
        for source in sources {
            guard let url = URL(string: source), let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data),
                  image.size.width * image.scale >= 32, let png = image.pngData() else { continue }
            return png
        }
        return nil
    }
}

/// A brand's logo when one was saved, else `fallback` (the category tile or bill monogram).
struct BrandIcon<Fallback: View>: View {
    let name: String?
    var size: CGFloat = 36
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        if let image = LogoStore.shared.image(for: name) {
            Image(uiImage: image)
                .resizable().interpolation(.high).scaledToFit()
                .padding(size * 0.12)
                .frame(width: size, height: size)
                .background(Color.white, in: .rect(cornerRadius: size * 0.28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).stroke(UZColor.label3.opacity(0.25), lineWidth: 0.5))
                .accessibilityHidden(true)
        } else {
            fallback()
        }
    }
}
