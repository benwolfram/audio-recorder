import AVFoundation
import CoreAudio

/// Records the mixed output of specific processes via a Core Audio process tap (macOS 14.2+).
final class ProcessTapRecorder {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var bufferList: UnsafeMutableAudioBufferListPointer?
    private let queue = DispatchQueue(label: "ProcessTapRecorder.io", qos: .userInitiated)

    func start(processes: [AudioObjectID], to url: URL) throws {
        do {
            let tap = CATapDescription(stereoMixdownOfProcesses: processes)
            tap.uuid = UUID()
            tap.muteBehavior = .unmuted
            tap.isPrivate = true
            try check(AudioHardwareCreateProcessTap(tap, &tapID), "Create process tap")

            var asbd = try readValue(tapID, kAudioTapPropertyFormat, AudioStreamBasicDescription())
            guard let format = AVAudioFormat(streamDescription: &asbd) else {
                throw CoreAudioError(action: "Read tap format", status: kAudioHardwareUnsupportedOperationError)
            }

            // The default output device drives the clock; the tap rides along as an input.
            let output = try readValue(AudioObjectID(kAudioObjectSystemObject),
                                       kAudioHardwarePropertyDefaultSystemOutputDevice, AudioDeviceID(kAudioObjectUnknown))
            let outputUID = try readString(output, kAudioDevicePropertyDeviceUID)
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Audio Recorder Tap",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                                   kAudioSubTapUIDKey: tap.uuid.uuidString]],
            ]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID), "Create aggregate device")

            let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
            self.file = file

            // Tap streams come after any input streams of the output device (e.g. a headset mic), so take the last ones.
            let tapBufferCount = format.isInterleaved ? 1 : Int(format.channelCount)
            let list = AudioBufferList.allocate(maximumBuffers: tapBufferCount)
            bufferList = list

            try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inputData, _, _, _ in
                let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
                guard input.count >= tapBufferCount else { return }
                for i in 0..<tapBufferCount { list[i] = input[input.count - tapBufferCount + i] }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer) else { return }
                try? file.write(from: buffer)
            }, "Create IO proc")
            try check(AudioDeviceStart(aggregateID, procID), "Start recording")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        queue.sync {} // drain any in-flight write before closing the file
        file?.close()
        if let bufferList { free(bufferList.unsafeMutablePointer) }
        (aggregateID, tapID, procID, file, bufferList) = (kAudioObjectUnknown, kAudioObjectUnknown, nil, nil, nil)
    }
}

/// Records the default input device.
final class MicRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    func start(to url: URL) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw CoreAudioError(action: "Find a microphone", status: kAudioHardwareBadDeviceError)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        self.file = file
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in try? file.write(from: buffer) }
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file?.close()
        file = nil
    }
}
