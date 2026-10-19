import AppKit
import CoreAudio

struct CoreAudioError: LocalizedError {
    let action: String
    let status: OSStatus
    var errorDescription: String? { "\(action) failed (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else { throw CoreAudioError(action: action, status: status) }
}

private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

func readValue<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) throws -> T {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<T>.size)
    var value = initial
    try withUnsafeMutablePointer(to: &value) {
        try check(AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0), "Read property \(selector)")
    }
    return value
}

func readString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    var addr = address(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    try check(AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value), "Read property \(selector)")
    return value?.takeRetainedValue() as String? ?? ""
}

func readObjectIDs(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
    var addr = address(selector)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size), "Read property size \(selector)")
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    try check(AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ids), "Read property \(selector)")
    return ids
}

/// A running app plus every Core Audio process object it owns (e.g. Chrome's audio helper).
struct AudioApp: Identifiable {
    let id: String // bundle ID
    let name: String
    let icon: NSImage?
    let processObjectIDs: [AudioObjectID]
    let isPlaying: Bool

    static func all() -> [AudioApp] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        var groups: [String: (app: NSRunningApplication, ids: [AudioObjectID], playing: Bool)] = [:]

        for objectID in (try? readObjectIDs(system, kAudioHardwarePropertyProcessObjectList)) ?? [] {
            let pid = (try? readValue(objectID, kAudioProcessPropertyPID, pid_t(0))) ?? 0
            let bundleID = (try? readString(objectID, kAudioProcessPropertyBundleID)) ?? ""
            guard let owner = running.first(where: { $0.processIdentifier == pid })
                    ?? running.first(where: { owns($0.bundleIdentifier!, bundleID) }) else { continue }
            let playing = (try? readValue(objectID, kAudioProcessPropertyIsRunningOutput, UInt32(0))) == 1
            let key = owner.bundleIdentifier!
            var group = groups[key] ?? (owner, [], false)
            group.ids.append(objectID)
            group.playing = group.playing || playing
            groups[key] = group
        }

        return groups.map { id, group in
            let icon = group.app.icon?.copy() as? NSImage
            icon?.size = NSSize(width: 16, height: 16)
            return AudioApp(id: id, name: group.app.localizedName ?? id, icon: icon,
                            processObjectIDs: group.ids, isPlaying: group.playing)
        }
        .sorted { ($0.isPlaying ? 0 : 1, $0.name) < ($1.isPlaying ? 0 : 1, $1.name) }
    }

    /// Browsers play audio from helper processes ("com.google.Chrome.helper"); Safari uses shared WebKit processes.
    private static func owns(_ appID: String, _ processBundleID: String) -> Bool {
        processBundleID.hasPrefix(appID + ".")
            || (appID == "com.apple.Safari" && processBundleID.hasPrefix("com.apple.WebKit."))
    }
}
