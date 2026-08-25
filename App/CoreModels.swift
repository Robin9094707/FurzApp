import Foundation
import SwiftData

public enum FartLoudness: String, CaseIterable, Identifiable, Codable {
    case whisper = "Leise"
    case medium = "Mittel"
    case loud = "Laut"
    case nuclear = "Nuklear"

    public var id: String { rawValue }

    var symbol: String {
        switch self {
        case .whisper: "speaker.wave.1"
        case .medium: "speaker.wave.2"
        case .loud: "speaker.wave.3"
        case .nuclear: "burst.fill"
        }
    }

    var score: Int {
        switch self {
        case .whisper: 1
        case .medium: 2
        case .loud: 3
        case .nuclear: 4
        }
    }
}

public enum FartSource: String, CaseIterable, Codable {
    case recorded = "Aufgenommen"
    case imported = "Importiert"
    case manual = "Ohne Audio"
}

public enum FartSort: String, CaseIterable, Identifiable {
    case newest = "Neueste zuerst"
    case oldest = "Älteste zuerst"
    case rating = "Beste Bewertung"
    case loudness = "Lauteste zuerst"
    case duration = "Längste zuerst"

    public var id: String { rawValue }
}

@Model
final class FartEntry {
    @Attribute(.unique) var id: UUID
    var title: String
    var eventDate: Date
    var createdAt: Date
    var updatedAt: Date
    var loudnessRaw: String
    var smellRating: Int
    var personalRating: Int
    var duration: Double
    var audioFilename: String?
    var sourceRaw: String
    var locationText: String
    var contextText: String
    var notes: String
    var tagsText: String
    var folderID: UUID?
    var isFavorite: Bool
    var isTrimmed: Bool

    init(id: UUID = UUID(), title: String, eventDate: Date = .now, loudness: FartLoudness = .medium, smellRating: Int = 3, personalRating: Int = 3, duration: Double = 0, audioFilename: String? = nil, source: FartSource = .manual, locationText: String = "", contextText: String = "", notes: String = "", tags: [String] = [], folderID: UUID? = nil, isFavorite: Bool = false, isTrimmed: Bool = false) {
        self.id = id
        self.title = title
        self.eventDate = eventDate
        self.createdAt = .now
        self.updatedAt = .now
        self.loudnessRaw = loudness.rawValue
        self.smellRating = min(max(smellRating, 1), 5)
        self.personalRating = min(max(personalRating, 1), 5)
        self.duration = max(duration, 0)
        self.audioFilename = audioFilename
        self.sourceRaw = source.rawValue
        self.locationText = locationText
        self.contextText = contextText
        self.notes = notes
        self.tagsText = tags.joined(separator: ",")
        self.folderID = folderID
        self.isFavorite = isFavorite
        self.isTrimmed = isTrimmed
    }
}

extension FartEntry {
    var loudness: FartLoudness {
        get { FartLoudness(rawValue: loudnessRaw) ?? .medium }
        set { loudnessRaw = newValue.rawValue }
    }

    var source: FartSource {
        get { FartSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var tags: [String] {
        get {
            tagsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set { tagsText = newValue.joined(separator: ",") }
    }
}

@Model
final class FartFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbol: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, symbol: String = "folder.fill") {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.createdAt = .now
    }
}

@Model
final class FartReminder {
    @Attribute(.unique) var id: UUID
    var title: String
    var hour: Int
    var minute: Int
    var weekdaysMask: Int
    var isEnabled: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String = "Furzwecker 💨", hour: Int = 18, minute: Int = 0, weekdaysMask: Int = 0, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.hour = hour
        self.minute = minute
        self.weekdaysMask = weekdaysMask
        self.isEnabled = isEnabled
        self.createdAt = .now
    }

    func includes(weekday: Int) -> Bool {
        guard (1...7).contains(weekday) else { return false }
        return (weekdaysMask & (1 << weekday)) != 0
    }

    func set(weekday: Int, enabled: Bool) {
        guard (1...7).contains(weekday) else { return }
        if enabled { weekdaysMask |= (1 << weekday) }
        else { weekdaysMask &= ~(1 << weekday) }
    }
}
