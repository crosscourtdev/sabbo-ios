import AVFoundation
import Speech
import SwiftUI

@MainActor
final class OralPractice: NSObject, ObservableObject, AVAudioRecorderDelegate {
  enum Phase { case idle, recording, transcribing }

  @Published private(set) var phase = Phase.idle
  @Published private(set) var takes: [String] = []
  @Published var selected = 0 { didSet { persist() } }
  @Published var notice: String?
  @Published private(set) var pendingFile: String?
  private var appendIndex: Int?
  private var folderID = UUID()
  private var prepared = false
  private var key: String?

  private static func folder(_ id: UUID) -> URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("oral-" + id.uuidString, isDirectory: true)
  }

  func microphoneLevel() -> Double {
    guard phase == .recording, let recorder else { return 0 }
    recorder.updateMeters()
    return min(1, max(0, (Double(recorder.averagePower(forChannel: 0)) + 55) / 55))
  }
  private var cardID: String?
  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "nb-NO"))
  private var dictationLocale: Locale?
  private var recorder: AVAudioRecorder?
  private var playbackConfiguration: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
  private var transcription: Task<Void, Never>?
  private var job: SFSpeechRecognitionTask?

  static var isPhone: Bool {
    UIDevice.current.userInterfaceIdiom == .phone && !ProcessInfo.processInfo.isiOSAppOnMac
  }

  func prepare() async -> Bool {
    notice = nil
    guard Self.isPhone else {
      notice = "Muntlig øving krever norsk talegjenkjenning på iPhone."
      return false
    }
    if prepared, SFSpeechRecognizer.authorizationStatus() == .authorized,
       AVAudioApplication.shared.recordPermission == .granted,
       dictationLocale != nil || recognizer?.isAvailable == true { return true }
    prepared = false
    let speech = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard speech == .authorized, await AVAudioApplication.requestRecordPermission() else {
      notice = "Gi Sabbo tilgang til mikrofon og talegjenkjenning i Innstillinger."
      return false
    }
    #if compiler(>=6.2)
    if #available(iOS 26, macCatalyst 26, *),
       let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "nb-NO")) {
      let module = DictationTranscriber(locale: locale, preset: .longDictation)
      do {
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
          try await install.downloadAndInstall()
        }
        prepared = true
        dictationLocale = locale
        return true
      } catch {
        // Older devices can also expose an installed Norwegian recognizer through SFSpeechRecognizer.
      }
    }
    #endif
    dictationLocale = nil
    guard recognizer?.supportsOnDeviceRecognition == true, recognizer?.isAvailable == true else {
      notice = "Norsk talegjenkjenning er utilgjengelig. Sjekk norsk diktering i Innstillinger og prøv igjen."
      return false
    }
    prepared = true
    return true
  }

  func bind(user: String, card: String?) {
    let userKey = "oral-takes-\(user)"
    guard userKey != key || card != cardID else { return }
    discardCapture()
    key = userKey
    cardID = card
    let saved = UserDefaults.standard.dictionary(forKey: userKey)
    let savedFolder = (saved?["folder"] as? String).flatMap(UUID.init(uuidString:))
    pendingFile = nil
    appendIndex = nil
    if let card, saved?["card"] as? String == card {
      folderID = savedFolder ?? UUID()
      takes = saved?["takes"] as? [String] ?? []
      if let name = saved?["pending"] as? String, UUID(uuidString: name) != nil,
         FileManager.default.fileExists(atPath: recordingURL(name).path) {
        pendingFile = name
        appendIndex = saved?["appendIndex"] as? Int
      }
    } else {
      if let savedFolder { try? FileManager.default.removeItem(at: Self.folder(savedFolder)) }
      folderID = UUID()
      takes = []
      UserDefaults.standard.removeObject(forKey: userKey)
    }
    let index = saved?["selected"] as? Int ?? 0
    selected = takes.indices.contains(index) ? index : 0
    notice = nil
  }

  private func recordingURL(_ name: String) -> URL {
    Self.folder(folderID).appendingPathComponent(name).appendingPathExtension("caf")
  }

  private func persist() {
    guard let key, let cardID, !takes.isEmpty || pendingFile != nil else { return }
    var state: [String: Any] = ["card": cardID, "takes": takes, "selected": selected,
                                "folder": folderID.uuidString]
    state["pending"] = pendingFile
    state["appendIndex"] = appendIndex
    UserDefaults.standard.set(state, forKey: key)
  }

  func record(until deadline: Date, continuing: Bool = false) {
    guard phase == .idle, cardID != nil, deadline > Date(), Self.isPhone else { return }
    guard dictationLocale != nil || (recognizer?.isAvailable == true && recognizer?.supportsOnDeviceRecognition == true) else {
      notice = "Norsk talegjenkjenning er utilgjengelig på denne iPhonen."
      return
    }
    notice = nil
    let session = AVAudioSession.sharedInstance()
    do {
      playbackConfiguration = (session.category, session.mode, session.categoryOptions)
      try session.setCategory(.record, mode: .measurement)
      try session.setActive(true)
      let name = UUID().uuidString
      try FileManager.default.createDirectory(at: Self.folder(folderID), withIntermediateDirectories: true)
      let url = recordingURL(name)
      let capture = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16
      ])
      recorder = capture
      capture.delegate = self
      capture.isMeteringEnabled = true
      let remaining = deadline.timeIntervalSinceNow
      guard remaining > 0, capture.record(forDuration: remaining) else { throw CaptureError.unavailable }
      pendingFile = name
      appendIndex = continuing && takes.indices.contains(selected) ? selected : nil
      persist()
      phase = .recording
    } catch {
      discardCapture()
      notice = "Kunne ikke starte mikrofonen. Prøv igjen."
    }
  }

  func stop() {
    guard phase == .recording, let capture = recorder else { return }
    capture.stop()
    finish()
  }

  nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    Task { @MainActor in
      guard recorder === self.recorder, self.phase == .recording else { return }
      if flag { self.finish() } else { self.stop() }
    }
  }

  private func finish() {
    guard phase == .recording else { return }
    recorder = nil
    restorePlayback()
    phase = .idle
    retryTranscription()
  }

  func retryTranscription() {
    guard phase == .idle, let pendingFile else { return }
    phase = .transcribing
    notice = nil
    let url = recordingURL(pendingFile)
    transcription = Task {
      do {
        let file = try AVAudioFile(forReading: url)
        let text = try await transcribe(file)
        try Task.checkCancellation()
        try acceptTranscript(text)
      } catch {
        guard !Task.isCancelled else { return }
        if error as? CaptureError == .tooLong {
          notice = "Svaret er for langt. Velg et tidligere svar eller ta et kortere opptak."
        } else {
          notice = "Opptaket er lagret. Prøv å gjøre det om til tekst igjen."
        }
      }
      phase = .idle
      transcription = nil
    }
  }

  func acceptTranscript(_ text: String) throws {
    guard !text.isEmpty else { throw CaptureError.empty }
    let target = appendIndex.flatMap { takes.indices.contains($0) ? $0 : nil }
    let answer = target.map { takes[$0] + " " + text } ?? text
    guard answer.unicodeScalars.count <= 6000 else { throw CaptureError.tooLong }
    pendingFile = nil
    appendIndex = nil
    if let target {
      takes[target] = answer
      selected = target
    } else {
      takes.append(answer)
      selected = takes.count - 1
    }
  }

  private enum CaptureError: Error { case empty, unavailable, tooLong }

  private func transcribe(_ file: AVAudioFile) async throws -> String {
    #if compiler(>=6.2)
    if #available(iOS 26, macCatalyst 26, *), let dictationLocale {
      return try await Self.dictate(file, locale: dictationLocale)
    }
    #endif
    return try await recognizeSegments(file)
  }

  #if compiler(>=6.2)
  @available(iOS 26, macCatalyst 26, *)
  private static func dictate(_ file: AVAudioFile, locale: Locale) async throws -> String {
    let module = DictationTranscriber(locale: locale, preset: .longDictation)
    let analyzer = SpeechAnalyzer(modules: [module])
    return try await withTaskCancellationHandler {
      try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
      var phrases: [String] = []
      for try await result in module.results {
        let phrase = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if !phrase.isEmpty { phrases.append(phrase) }
      }
      return phrases.joined(separator: " ")
    } onCancel: {
      Task { await analyzer.cancelAndFinishNow() }
    }
  }

  #endif

  private func recognizeSegments(_ file: AVAudioFile) async throws -> String {
    var segments: [String] = []
    // Short recognition requests also support a full five-minute response on older iPhones.
    while file.framePosition < file.length {
      try Task.checkCancellation()
      let part = try Self.segment(from: file)
      defer { try? FileManager.default.removeItem(at: part) }
      let words = try await recognize(part)
      if !words.isEmpty { segments.append(words) }
    }
    try Task.checkCancellation()
    return segments.joined(separator: " ")
  }

  private static func segment(from file: AVAudioFile) throws -> URL {
    let rate = file.processingFormat.sampleRate
    let start = file.framePosition
    let count = AVAudioFrameCount(min(file.length - start, Int64(rate * 45)))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else {
      throw CaptureError.unavailable
    }
    try file.read(into: buffer, frameCount: count)
    // Split long takes at a quiet interval to keep the surrounding words together.
    if file.framePosition < file.length, let channel = buffer.floatChannelData?[0] {
      let window = Int(rate / 50)
      let end = Int(buffer.frameLength)
      var quietest = Float.infinity
      var split = end
      for offset in stride(from: max(0, end - Int(rate * 4)), through: end - window, by: window) {
        var energy: Float = 0
        for i in offset..<(offset + window) { energy += channel[i] * channel[i] }
        if energy <= quietest { quietest = energy; split = offset + window / 2 }
      }
      buffer.frameLength = AVAudioFrameCount(split)
      file.framePosition = start + Int64(split)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("oving-\(UUID()).caf")
    do {
      let output = try AVAudioFile(forWriting: url, settings: file.processingFormat.settings)
      try output.write(from: buffer)
      return url
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw error
    }
  }

  private func recognize(_ url: URL) async throws -> String {
    guard let recognizer, recognizer.supportsOnDeviceRecognition, recognizer.isAvailable else {
      throw CaptureError.unavailable
    }
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    // A stream finishes once even if Apple reports both a final result and a cancellation.
    let responses = AsyncThrowingStream<String, Error> { continuation in
      job = recognizer.recognitionTask(with: request) { result, error in
        if let result, result.isFinal {
          continuation.yield(result.bestTranscription.formattedString)
          continuation.finish()
        } else if let error = error as NSError? {
          if error.domain == "kAFAssistantErrorDomain" && error.code == 1110 {
            continuation.finish() // Silent segment.
          } else { continuation.finish(throwing: error) }
        }
      }
    }
    var text = ""
    for try await value in responses { text = value }
    try Task.checkCancellation()
    job = nil
    return text
  }

  private func restorePlayback() {
    guard let (category, mode, options) = playbackConfiguration else { return }
    playbackConfiguration = nil
    let session = AVAudioSession.sharedInstance()
    try? session.setActive(false, options: .notifyOthersOnDeactivation)
    try? session.setCategory(category, mode: mode, options: options)
  }

  private func discardCapture() {
    transcription?.cancel()
    job?.cancel()
    job = nil
    if let recorder {
      recorder.stop()
      if phase != .recording { recorder.deleteRecording() }
    }
    restorePlayback()
    recorder = nil
    phase = .idle
  }
}
