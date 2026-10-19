# Audio Recorder

Menu bar app that records one app's audio (Zoom, Chrome/Google Meet, …) and/or your microphone into a single `.m4a` in `~/Music/Audio Recorder/`, ready for transcription.

Uses Core Audio process taps (macOS 14.2+), so it only needs the "System Audio Recording" permission, not screen recording.

```sh
./build.sh --open   # builds and launches build/Audio Recorder.app
```

- Pick an app (♪ = currently playing), toggle the mic, hit Record.
- For calls, keep "Include microphone" on: the app's audio has the other people, the mic has you.
- "Show in Dock" toggles the Dock icon; it's hidden by default.
- Start the call/tab audio before recording: the tap covers the app's audio processes that exist when you hit Record.
