import AVFoundation
import AppKit

@MainActor
final class Recorder: ObservableObject {
    static let folder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
        .appending(path: "Audio Recorder", directoryHint: .isDirectory)

    @Published private(set) var apps: [AudioApp] = []
    @Published var selectedAppID = UserDefaults.standard.string(forKey: "selectedAppID") ?? "" {
        didSet { UserDefaults.standard.set(selectedAppID, forKey: "selectedAppID") }
    }
    @Published var includeMic = UserDefaults.standard.object(forKey: "includeMic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(includeMic, forKey: "includeMic") }
    }
    @Published private(set) var startedAt: Date?
    @Published private(set) var isSaving = false
    @Published private(set) var recordings: [URL] = []
    @Published var error: String?

    var isRecording: Bool { startedAt != nil }

    private var tap: ProcessTapRecorder?
    private var mic: MicRecorder?
    private var session: (tempDir: URL, name: String)?

    init() {
        refreshApps()
        loadRecordings()
    }

    func refreshApps() { apps = AudioApp.all() }

    func start() async {
        error = nil
        let app = apps.first { $0.id == selectedAppID }
        guard app != nil || includeMic else { error = "Choose an app or turn on the microphone."; return }
        if includeMic, !(await AVCaptureDevice.requestAccess(for: .audio)) {
            error = "Microphone access is off. Enable it in System Settings › Privacy & Security › Microphone."
            return
        }

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            if let app {
                let tap = ProcessTapRecorder()
                try tap.start(processes: app.processObjectIDs, to: tempDir.appending(path: "app.caf"))
                self.tap = tap
            }
            if includeMic {
                let mic = MicRecorder()
                try mic.start(to: tempDir.appending(path: "mic.caf"))
                self.mic = mic
            }
            session = (tempDir, app.map { includeMic ? "\($0.name) + Mic" : $0.name } ?? "Microphone")
            startedAt = .now
        } catch {
            stopCapture()
            try? FileManager.default.removeItem(at: tempDir)
            self.error = error.localizedDescription
        }
    }

    func stop() async {
        stopCapture()
        guard let session else { return }
        self.session = nil
        startedAt = nil
        isSaving = true
        defer { isSaving = false }

        let stamp = Date.now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)", timeZone: .current, calendar: .current))
        let output = Self.folder.appending(path: "\(session.name) \(stamp).m4a")
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let inputs = try FileManager.default.contentsOfDirectory(at: session.tempDir, includingPropertiesForKeys: nil)
            try await Self.mix(inputs, to: output)
            try? FileManager.default.removeItem(at: session.tempDir)
            loadRecordings()
        } catch {
            // Keep the raw files so nothing is lost.
            self.error = "Couldn't save recording (\(error.localizedDescription)). Raw audio kept in \(session.tempDir.path)"
            NSWorkspace.shared.activateFileViewerSelecting([session.tempDir])
        }
    }

    private func stopCapture() {
        tap?.stop()
        mic?.stop()
        tap = nil
        mic = nil
    }

    /// Mixes the app and mic tracks into a single AAC file (the export session sums all audio tracks).
    private static func mix(_ inputs: [URL], to output: URL) async throws {
        let composition = AVMutableComposition()
        for url in inputs {
            let asset = AVURLAsset(url: url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: try await asset.load(.duration)), of: source, at: .zero)
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await export.export(to: output, as: .m4a)
    }

    private func loadRecordings() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        recordings = urls
            .filter { $0.pathExtension == "m4a" }
            .map { ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map(\.0)
    }
}
