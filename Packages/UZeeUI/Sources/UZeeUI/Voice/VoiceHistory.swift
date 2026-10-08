import Foundation

/// The log of Ask UZee conversations, kept on this iPhone so closing the helper never loses a chat.
/// Reopening within a few hours carries on the same chat; after that a new one starts and the old one
/// stays under Past chats. Erase everything clears it.
struct VoiceHistory: Codable, Equatable {
    struct Line: Codable, Equatable, Identifiable {
        enum Speaker: String, Codable { case me, uzee }
        var id = UUID()
        let speaker: Speaker
        let text: String
        var at = Date()
    }

    struct Chat: Codable, Equatable, Identifiable {
        var id = UUID()
        var started = Date()
        var lines: [Line] = []

        /// The first thing the user said, for the Past chats list.
        var title: String {
            lines.first { $0.speaker == .me }?.text ?? lines.first?.text ?? "Chat"
        }

        var lastActivity: Date { lines.last?.at ?? started }
    }

    static let key = "uzee.voice.history"
    /// After this long away, opening Ask UZee starts a new chat.
    static let carryOn: TimeInterval = 6 * 60 * 60
    static let keptChats = 50
    static let keptLines = 300

    var chats: [Chat] = []

    /// Saved chats; empty in UI tests, which use a throwaway database.
    static func load(_ defaults: UserDefaults = .standard) -> VoiceHistory {
        guard !isTesting, let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(VoiceHistory.self, from: data) else { return VoiceHistory() }
        return history
    }

    func save(_ defaults: UserDefaults = .standard) {
        guard !Self.isTesting else { return }
        var trimmed = self
        trimmed.chats = trimmed.chats.filter { !$0.lines.isEmpty }.suffix(Self.keptChats)
        for index in trimmed.chats.indices where trimmed.chats[index].lines.count > Self.keptLines {
            trimmed.chats[index].lines = Array(trimmed.chats[index].lines.suffix(Self.keptLines))
        }
        if let data = try? JSONEncoder().encode(trimmed) { defaults.set(data, forKey: Self.key) }
    }

    /// The chat to show when Ask UZee opens: the latest one if it was used recently, else none.
    func recentChat(now: Date = Date()) -> Chat? {
        guard let last = chats.last, !last.lines.isEmpty, now.timeIntervalSince(last.lastActivity) < Self.carryOn else { return nil }
        return last
    }

    /// Chats before the current one, newest first.
    func past(excluding id: UUID?) -> [Chat] {
        chats.filter { $0.id != id && !$0.lines.isEmpty }.reversed()
    }

    /// Adds or replaces a chat.
    mutating func store(_ chat: Chat) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index] = chat
        } else {
            chats.append(chat)
        }
    }

    mutating func remove(_ id: UUID) {
        chats.removeAll { $0.id == id }
    }

    private static var isTesting: Bool { ProcessInfo.processInfo.arguments.contains("-uzee-in-memory") }
}
