#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Expected source block not found in {path}")
    if text.count(old) != 1:
        raise SystemExit(f"Expected exactly one source block in {path}, found {text.count(old)}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")

# 1) Preserve the real recorder duration BEFORE AVAudioRecorder.stop() can reset currentTime,
# then verify against the resulting M4A file for a second source of truth.
replace_once(
    "App/CoreServices.swift",
    '''    func requestPermissionAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
''',
    '''    func requestPermissionAndStart() {
        guard !isRecording, temporaryURL == nil else { return }
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
'''
)
replace_once(
    "App/CoreServices.swift",
    '''    func stop() {
        guard isRecording else { return }
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        elapsed = recorder?.currentTime ?? elapsed
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DebugLogger.shared.log("Audioaufnahme beendet")
    }
''',
    '''    func stop() {
        guard isRecording else { return }
        let measuredDuration = max(recorder?.currentTime ?? 0, elapsed)
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false

        // AVAudioRecorder.currentTime may fall back to ~0 immediately after stop().
        // Keep the pre-stop value and verify it against the finished audio container.
        if let url = temporaryURL,
           let verifiedDuration = try? AudioFileStore.audioDuration(at: url),
           verifiedDuration > 0 {
            elapsed = max(measuredDuration, verifiedDuration)
        } else {
            elapsed = measuredDuration
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DebugLogger.shared.log("Audioaufnahme beendet · Dauer \\(String(format: "%.2f", elapsed)) s")
    }
'''
)

# 2) Let the app notice a pending quick-record request without consuming it.
# The recorder itself consumes it only when its UI is actually on screen.
replace_once(
    "Shared/RJFurzShared.swift",
    '''    public static func markRequested() {
        RJFurzShared.defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    public static func consumeIfRecent(maxAge: TimeInterval = 30) -> Bool {
''',
    '''    public static func markRequested() {
        RJFurzShared.defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    public static func hasRecent(maxAge: TimeInterval = 120) -> Bool {
        let value = RJFurzShared.defaults.double(forKey: key)
        guard value > 0 else { return false }
        return Date().timeIntervalSince1970 - value <= maxAge
    }

    public static func consumeIfRecent(maxAge: TimeInterval = 120) -> Bool {
'''
)

# 3) Every instant-record entry point writes the durable App Group request.
replace_once(
    "App/MainViews.swift",
    '''            DashboardView(showRecorder: $showRecorder, showImporter: $showImporter) {
                autoStartRecorder = true
                showRecorder = true
                Haptics.impact(.heavy)
            }
''',
    '''            DashboardView(showRecorder: $showRecorder, showImporter: $showImporter) {
                QuickRecordRequest.markRequested()
                autoStartRecorder = true
                showRecorder = true
                Haptics.impact(.heavy)
            }
'''
)
replace_once(
    "App/MainViews.swift",
    '''        .onOpenURL { url in
            guard url.scheme?.lowercased() == "rjfurz", url.host?.lowercased() == "record" else { return }
            autoStartRecorder = true
            showRecorder = true
            Haptics.impact(.heavy)
        }
''',
    '''        .onOpenURL { url in
            guard url.scheme?.lowercased() == "rjfurz", url.host?.lowercased() == "record" else { return }
            QuickRecordRequest.markRequested()
            autoStartRecorder = true
            showRecorder = true
            Haptics.impact(.heavy)
        }
'''
)
replace_once(
    "App/MainViews.swift",
    '''        if QuickRecordRequest.consumeIfRecent() {
            autoStartRecorder = true
            showRecorder = true
        }
''',
    '''        // Do not consume here: on a cold launch the sheet and its content can be
        // created in different SwiftUI transactions. The RecorderView consumes the
        // request only when it is actually visible, which makes cold widget launches reliable.
        if QuickRecordRequest.hasRecent() {
            autoStartRecorder = true
            showRecorder = true
        }
'''
)

# 4) Recorder consumes the request itself. Also derive preview trim bounds from the actual file.
replace_once(
    "App/EditorRecorderViews.swift",
    '''            .onAppear {
                guard autoStart, !didAutoStart else { return }
                didAutoStart = true
                recorder.requestPermissionAndStart()
                Haptics.impact(.heavy)
            }
''',
    '''            .onAppear {
                let requestedByWidgetOrControl = QuickRecordRequest.consumeIfRecent()
                guard (autoStart || requestedByWidgetOrControl), !didAutoStart else { return }
                didAutoStart = true
                recorder.requestPermissionAndStart()
                Haptics.impact(.heavy)
            }
'''
)
replace_once(
    "App/EditorRecorderViews.swift",
    '''    private func prepareRecordingPreview() {
        guard let url = recorder.temporaryURL else { return }
        trimStart = 0
        trimEnd = max(recorder.elapsed, 0.1)
        previewPlayer.load(url: url)
        Task {
''',
    '''    private func prepareRecordingPreview() {
        guard let url = recorder.temporaryURL else { return }
        previewPlayer.load(url: url)
        trimStart = 0
        // Use the finished M4A duration as the primary trim boundary. This prevents
        // an accidental ~0.1 s auto-trim even if a recorder timing callback is late.
        trimEnd = max(previewPlayer.duration, recorder.elapsed, 0.1)
        Task {
'''
)
replace_once(
    "App/EditorRecorderViews.swift",
    '''                            trimEnd = max(recorder.elapsed, 0.1)
''',
    '''                            trimEnd = max(previewPlayer.duration, recorder.elapsed, 0.1)
'''
)

# 5) Patch release number only; no model/schema/backend change.
replace_once("project.yml", 'MARKETING_VERSION: "2.2"', 'MARKETING_VERSION: "2.2.1"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "4"', 'CURRENT_PROJECT_VERSION: "5"')

print("RJ Furz-App 2.2.1 recorder hotfix applied")
