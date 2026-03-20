import Foundation

struct TranscriptEntry: Codable {
    let text: String
    let timestamp: String
    let original: String?  // non-nil if paraphrased

    var isParaphrased: Bool { original != nil }
}

class HistoryManager {
    static let shared = HistoryManager()

    private let maxEntries = 200
    private let historyURL: URL
    private(set) var entries: [TranscriptEntry] = []

    private init() {
        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()
        historyURL = appDir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: historyURL.path),
              let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func add(text: String, original: String? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let entry = TranscriptEntry(
            text: text,
            timestamp: formatter.string(from: Date()),
            original: original
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func delete(at index: Int) {
        guard index >= 0 && index < entries.count else { return }
        entries.remove(at: index)
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: historyURL)
        }
    }
}
