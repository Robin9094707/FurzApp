import Foundation
import AVFoundation
import Combine
import UserNotifications

final class DebugLogger {
    static let shared = DebugLogger()
    private let queue = DispatchQueue(label: "eu.rjuhas.furzapp.debuglogger")
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        fileURL = base.appendingPathComponent("RJFurzApp-debug.log")
    }

    func log(_ message: String) {
        queue.async { [fileURL] in
            let formatter = ISO8601DateFormatter()
            let line = "[\(formatter.string(from: .now))] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch { }
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    func text() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "Noch keine Debug-Einträge."
    }

    func clear() {
        queue.async { [fileURL] in try? FileManager.default.removeItem(at: fileURL) }
    }
}


struct ImportedAudio: Identifiable {
    let id = UUID()
    let filename: String
    let duration: Double
    let originalName: String
}

enum AudioFileStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("RJFurzAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func importAudio(from sourceURL: URL) throws -> ImportedAudio {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension.lowercased()
        let filename = "import-\(UUID().uuidString).\(ext)"
        let destination = url(for: filename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        let duration = try audioDuration(at: destination)
        DebugLogger.shared.log("Audio importiert: \(sourceURL.lastPathComponent)")
        return ImportedAudio(filename: filename, duration: duration, originalName: sourceURL.deletingPathExtension().lastPathComponent)
    }

    static func commitRecording(from tempURL: URL) throws -> ImportedAudio {
        let filename = "fart-\(UUID().uuidString).m4a"
        let destination = url(for: filename)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        let duration = try audioDuration(at: destination)
        DebugLogger.shared.log("Aufnahme gespeichert: \(filename)")
        return ImportedAudio(filename: filename, duration: duration, originalName: "Eigene Aufnahme")
    }

    static func replacementURL(fileExtension: String = "m4a") -> (filename: String, url: URL) {
        let filename = "trim-\(UUID().uuidString).\(fileExtension)"
        return (filename, url(for: filename))
    }

    static func delete(filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: url(for: filename))
        DebugLogger.shared.log("Audio gelöscht: \(filename)")
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        _ = directory
    }

    static func audioDuration(at url: URL) throws -> Double {
        let player = try AVAudioPlayer(contentsOf: url)
        return player.duration
    }
}


@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var levels: [CGFloat] = []
    @Published private(set) var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var temporaryURL: URL?

    func requestPermissionAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted {
                    self.start()
                } else {
                    self.errorMessage = "Mikrofonzugriff wurde nicht erlaubt."
                }
            }
        }
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("rj-furz-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 128_000
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            guard recorder.record() else {
                errorMessage = "Die Aufnahme konnte nicht gestartet werden."
                return
            }
            self.recorder = recorder
            self.temporaryURL = url
            self.elapsed = 0
            self.levels = []
            self.isRecording = true
            DebugLogger.shared.log("Audioaufnahme gestartet")
            startMeterTimer()
        } catch {
            errorMessage = error.localizedDescription
            DebugLogger.shared.log("Aufnahmefehler: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRecording else { return }
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        elapsed = recorder?.currentTime ?? elapsed
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DebugLogger.shared.log("Audioaufnahme beendet")
    }

    func cancelAndCleanup() {
        if isRecording { stop() }
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        temporaryURL = nil
    }

    func takeTemporaryURL() -> URL? {
        let url = temporaryURL
        temporaryURL = nil
        return url
    }

    private func startMeterTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder, self.isRecording else { return }
                recorder.updateMeters()
                self.elapsed = recorder.currentTime
                let db = recorder.averagePower(forChannel: 0)
                let normalized = max(0.03, min(1.0, pow(10, db / 35)))
                self.levels.append(CGFloat(normalized))
                if self.levels.count > 90 { self.levels.removeFirst(self.levels.count - 90) }
            }
        }
    }
}


@MainActor
final class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var rate: Float = 1.0 {
        didSet { player?.rate = rate }
    }

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            currentTime = 0
        } catch {
            DebugLogger.shared.log("Player-Fehler: \(error.localizedDescription)")
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        player.rate = rate
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        timer?.invalidate()
        timer = nil
    }

    func seek(to value: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(value, 0), player.duration)
        currentTime = player.currentTime
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }
}


actor WaveformAnalyzer {
    static let shared = WaveformAnalyzer()

    func samples(for url: URL, count: Int = 90) throws -> [CGFloat] {
        let file = try AVAudioFile(forReading: url)
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { return Array(repeating: 0.05, count: count) }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            return Array(repeating: 0.05, count: count)
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return Array(repeating: 0.05, count: count)
        }

        let data = channels[0]
        let length = Int(buffer.frameLength)
        let bucket = max(1, length / max(1, count))
        var result: [CGFloat] = []
        result.reserveCapacity(count)

        var start = 0
        while start < length && result.count < count {
            let end = min(length, start + bucket)
            var peak: Float = 0
            for index in start..<end { peak = max(peak, abs(data[index])) }
            result.append(CGFloat(max(0.04, min(1, sqrt(peak)))))
            start = end
        }
        while result.count < count { result.append(0.04) }
        return result
    }
}


struct TrimResult {
    let filename: String
    let duration: Double
}

enum AudioTrimmer {
    static func trim(filename: String, start: Double, end: Double) async throws -> TrimResult {
        let source = AudioFileStore.url(for: filename)
        let destination = AudioFileStore.replacementURL(fileExtension: "m4a")
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "RJFurzApp", code: 20, userInfo: [NSLocalizedDescriptionKey: "Audio-Export konnte nicht vorbereitet werden."])
        }

        session.outputURL = destination.url
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, start), preferredTimescale: 600),
            duration: CMTime(seconds: max(0.1, end - start), preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: session.error ?? NSError(domain: "RJFurzApp", code: 21, userInfo: [NSLocalizedDescriptionKey: "Audio-Zuschnitt fehlgeschlagen."]))
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: NSError(domain: "RJFurzApp", code: 22, userInfo: [NSLocalizedDescriptionKey: "Audio-Zuschnitt wurde nicht abgeschlossen."]))
                }
            }
        }

        let duration = try AudioFileStore.audioDuration(at: destination.url)
        return TrimResult(filename: destination.filename, duration: duration)
    }
}


actor NotificationManager {
    static let shared = NotificationManager()

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            DebugLogger.shared.log("Notification-Rechte Fehler: \(error.localizedDescription)")
            return false
        }
    }

    func schedule(_ reminder: FartReminder) async throws {
        let center = UNUserNotificationCenter.current()
        await remove(reminderID: reminder.id)
        guard reminder.isEnabled else { return }
        _ = await requestAuthorization()

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "Zeit für dein Furz-Protokoll 💨 Wenn gerade einer kommt: aufnehmen, bewerten, für die Ewigkeit sichern."
        content.sound = .default

        if reminder.weekdaysMask == 0 {
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier(reminder.id, suffix: "daily"), content: content, trigger: trigger)
            try await center.add(request)
        } else {
            for weekday in 1...7 where reminder.includes(weekday: weekday) {
                var components = DateComponents()
                components.weekday = weekday
                components.hour = reminder.hour
                components.minute = reminder.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: identifier(reminder.id, suffix: "w\(weekday)"), content: content, trigger: trigger)
                try await center.add(request)
            }
        }
        DebugLogger.shared.log("Furzwecker geplant: \(reminder.title)")
    }

    func remove(reminderID: UUID) async {
        let ids = [identifier(reminderID, suffix: "daily")] + (1...7).map { identifier(reminderID, suffix: "w\($0)") }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func identifier(_ id: UUID, suffix: String) -> String {
        "eu.rjuhas.furzapp.reminder.\(id.uuidString).\(suffix)"
    }
}


struct ExportFart: Codable {
    let id: UUID
    let title: String
    let eventDate: Date
    let loudness: String
    let smellRating: Int
    let personalRating: Int
    let duration: Double
    let source: String
    let location: String
    let context: String
    let notes: String
    let tags: [String]
    let folderID: UUID?
    let favorite: Bool
    let audioFilename: String?
    let latitude: Double?
    let longitude: Double?
    let resolvedAddress: String
    let geofenceName: String
    let sharedWithFriends: Bool
}

enum ExportService {
    static func makeJSON(entries: [FartEntry]) throws -> URL {
        let payload = entries.map {
            ExportFart(
                id: $0.id,
                title: $0.title,
                eventDate: $0.eventDate,
                loudness: $0.loudnessRaw,
                smellRating: $0.smellRating,
                personalRating: $0.personalRating,
                duration: $0.duration,
                source: $0.sourceRaw,
                location: $0.locationText,
                context: $0.contextText,
                notes: $0.notes,
                tags: $0.tags,
                folderID: $0.folderID,
                favorite: $0.isFavorite,
                audioFilename: $0.audioFilename,
                latitude: $0.latitude,
                longitude: $0.longitude,
                resolvedAddress: $0.resolvedAddress,
                geofenceName: $0.geofenceName,
                sharedWithFriends: $0.isShared
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let stamp = String(ISO8601DateFormatter().string(from: .now).prefix(10))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RJ-Furz-Export-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
