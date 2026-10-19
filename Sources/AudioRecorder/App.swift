import SwiftUI

@main
struct AudioRecorderApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(recorder: delegate.recorder)
        } label: {
            MenuBarIcon(recorder: delegate.recorder)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let recorder = Recorder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: "showInDock") { NSApp.setActivationPolicy(.regular) }
    }

    // Never lose a recording on quit: finish saving first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.isRecording else { return .terminateNow }
        Task { @MainActor in
            await recorder.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct MenuBarIcon: View {
    @ObservedObject var recorder: Recorder

    var body: some View {
        Image(systemName: recorder.isRecording ? "record.circle.fill" : "waveform")
    }
}

struct MenuView: View {
    @ObservedObject var recorder: Recorder
    @AppStorage("showInDock") private var showInDock = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("App", selection: $recorder.selectedAppID) {
                    Text("None").tag("")
                    ForEach(recorder.apps) { app in
                        Label {
                            Text(app.isPlaying ? "\(app.name)  ♪" : app.name)
                        } icon: {
                            if let icon = app.icon { Image(nsImage: icon) }
                        }
                        .tag(app.id)
                    }
                }
                Button("Refresh", systemImage: "arrow.clockwise", action: recorder.refreshApps)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .disabled(recorder.isRecording)

            Toggle("Include microphone", isOn: $recorder.includeMic)
                .disabled(recorder.isRecording)

            Button {
                Task { recorder.isRecording ? await recorder.stop() : await recorder.start() }
            } label: {
                HStack {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle")
                    if let startedAt = recorder.startedAt {
                        Text("Stop  ") + Text(startedAt, style: .timer).monospacedDigit()
                    } else {
                        Text(recorder.isSaving ? "Saving…" : "Record")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? .red : .accentColor)
            .disabled(recorder.isSaving)
            .keyboardShortcut(.defaultAction)

            if let error = recorder.error {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            if !recorder.recordings.isEmpty {
                Divider()
                Text("Recent").font(.caption).foregroundStyle(.secondary)
                ForEach(recorder.recordings, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.borderless)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }

            Divider()
            Toggle("Show in Dock", isOn: $showInDock)
                .onChange(of: showInDock) { _, show in NSApp.setActivationPolicy(show ? .regular : .accessory) }
            HStack {
                Button("Open Recordings Folder") {
                    try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Recorder.folder)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)

            Text("App audio needs permission under System Settings › Privacy & Security › Screen & System Audio Recording (asked on first recording).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 300)
        .task {
            // Keep the app list fresh while the panel is open (apps start/stop playing audio).
            while !Task.isCancelled {
                if !recorder.isRecording { recorder.refreshApps() }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
