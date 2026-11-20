import AVFoundation
import Carbon
import Foundation
import Speech

/// Why dictation didn't start, with the System Settings pane that fixes it when there is one.
struct DictationError: Equatable {
    let message: String
    var settingsURL: URL?

    init(message: String, settingsURL: URL? = nil) {
        self.message = message
        self.settingsURL = settingsURL
    }

    static func denied(_ permission: String, pane: String) -> DictationError {
        DictationError(
            message: "Mac Island needs \(permission) access to dictate.",
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        )
    }

    /// What to show when the recognizer gives up; nil for endings that need no message (nothing
    /// was said, or dictation was stopped).
    init?(recognitionError error: Error) {
        let error = error as NSError
        switch (error.domain, error.code) {
        // Apple's recognizer only runs with macOS Dictation turned on.
        case ("kLSRErrorDomain", 201), ("kAFAssistantErrorDomain", 1101), ("kAFAssistantErrorDomain", 1700):
            self.init(
                message: "Turn on Dictation in System Settings → Keyboard to dictate.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
            )
        case ("kAFAssistantErrorDomain", 1110), ("kAFAssistantErrorDomain", 216), ("kAFAssistantErrorDomain", 203),
             ("kLSRErrorDomain", 301), (NSCocoaErrorDomain, NSUserCancelledError):
            return nil
        default:
            self.init(message: "Dictation stopped: \(error.localizedDescription)")
        }
    }
}

/// Live speech-to-text for the reply field: microphone audio goes to Apple's speech recognizer and
/// the words so far are written into the draft as they're heard.
@MainActor
final class Dictation {
    private weak var model: IslandModel?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// The draft as it was when dictation started; heard words go after it.
    private var prefix = ""
    /// Bumped on every start and stop, so late results from an older run are dropped.
    private var run = 0

    init(model: IslandModel) {
        self.model = model
    }

    func toggle() {
        if model?.isDictating == true { stop() } else { Task { await start() } }
    }

    func start() async {
        guard let model, !model.isDictating else { return }
        model.dictationError = nil
        run += 1
        let thisRun = run

        guard await Self.speechAuthorized() else {
            model.dictationError = .denied("Speech Recognition", pane: "Privacy_SpeechRecognition")
            return
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            model.dictationError = .denied("Microphone", pane: "Privacy_Microphone")
            return
        }
        // Stopped or restarted while the permission prompts were up.
        guard thisRun == run else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Self.speechLocale()), recognizer.isAvailable else {
            model.dictationError = DictationError(message: "Speech recognition isn't available right now.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On the Mac when it can: private, and without the server's one-minute limit.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            model.dictationError = DictationError(message: "No microphone found.")
            return
        }
        Self.installTap(on: input, format: format, feeding: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            model.dictationError = DictationError(message: "Couldn't start the microphone.")
            return
        }

        let draft = model.replyDraft
        prefix = draft.isEmpty || draft.last?.isWhitespace == true ? draft : draft + " "
        self.engine = engine
        self.request = request
        task = Self.recognize(with: recognizer, request: request) { [weak self] text, error, isFinal in
            guard let self, self.run == thisRun else { return }
            if let text { self.model?.replyDraft = self.prefix + text }
            if let error, let shown = DictationError(recognitionError: error) { self.model?.dictationError = shown }
            if isFinal || error != nil { self.stop() }
        }
        model.isDictating = true
    }

    func stop() {
        run += 1
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
        if model?.isDictating == true { model?.isDictating = false }
    }

    /// The language being typed in: the current keyboard layout's (Russian layout, Russian speech),
    /// else the system's. The system language alone hears Russian as English words.
    private static func speechLocale() -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        var languages: [String] = []
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let list = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String] ?? []
            languages += list.prefix(1)
        }
        languages += Locale.preferredLanguages
        for language in languages {
            let wanted = Locale(identifier: language)
            if supported.contains(wanted) { return wanted }
            guard let code = wanted.language.languageCode else { continue }
            let matches = supported.filter { $0.language.languageCode == code }
            // ru → ru-RU, en → en-US: the language's home region before any other.
            if let home = matches.first(where: { $0.region?.identifier == code.identifier.uppercased() })
                ?? matches.first(where: { $0.identifier.hasSuffix("US") })
                ?? matches.sorted(by: { $0.identifier < $1.identifier }).first {
                return home
            }
        }
        return Locale.current
    }

    // The audio tap and recognizer call back on their own threads. These are nonisolated so the
    // closures don't inherit the main actor (Swift 6 traps when they then run elsewhere).

    private nonisolated static func speechAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        feeding request: SFSpeechAudioBufferRecognitionRequest
    ) {
        nonisolated(unsafe) let request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @MainActor (String?, Error?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in onResult(text, error, isFinal) }
        }
    }
}
