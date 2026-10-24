import SwiftUI
import UIKit

/// Clipboard is available only to the owner; typed input remains unrestricted.
final class OwnWordsTextView: UITextView, UITextPasteDelegate, UITextDropDelegate {
  #if DEBUG
  func trace(_ event: String) {
    if ProcessInfo.processInfo.environment["SABBO_UI_TEST"] == "1",
       ProcessInfo.processInfo.environment["SABBO_INPUT_TRACE"] == "1" {
      let line = "\(event) text=\(text ?? "") selection=\(NSStringFromRange(selectedRange))\n"
      let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("sabbo-input-trace.txt")
      if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
      if let file = try? FileHandle(forWritingTo: url) {
        defer { try? file.close() }
        try? file.seekToEnd(); try? file.write(contentsOf: Data(line.utf8))
      }
    }
  }
  override func insertText(_ text: String) {
    trace("before insert " + text)
    super.insertText(text)
    trace("after insert " + text)
  }
  #endif
  // UIKit can deliver several keystrokes before textViewDidChange. A repeated
  // SwiftUI render of the last acknowledged value must not rewind that input.
  private var lastModelText: String?
  private var pendingUserTexts: Set<String> = []
  private var latestUserText: String?
  private var editGeneration = 0
  func applyModelText(_ value: String) {
    trace("apply value=\(value) last=\(lastModelText ?? "nil")")
    guard markedTextRange == nil else { return }
    if value == latestUserText {
      // The model has caught up. A later intentional draft change may now
      // reuse an earlier value, so do not retain old edits indefinitely.
      lastModelText = value
      latestUserText = nil
      pendingUserTexts.removeAll()
      return
    }
    guard value != lastModelText, !pendingUserTexts.contains(value) else { return }
    lastModelText = value
    latestUserText = nil
    pendingUserTexts.removeAll()
    guard text != value else { return }
    let selection = selectedRange
    let generation = editGeneration
    text = value
    if editGeneration == generation {
      selectedRange = NSRange(location: min(selection.location, (value as NSString).length), length: 0)
    }
    trace("applied")
  }
  func acknowledgeUserText() {
    trace("acknowledge")
    editGeneration += 1
    latestUserText = text
    pendingUserTexts.insert(text ?? "")
  }
  var blocked: (() -> Void)?
  private(set) var allowsClipboard = false
  func setAccount(_ userID: String?) {
    let allowed = userID == ClientProfile.ownerID
    guard allowsClipboard != allowed else { return }
    allowsClipboard = allowed
    pasteDelegate = allowsClipboard ? nil : self
    pasteConfiguration = allowsClipboard ? UIPasteConfiguration(forAccepting: NSString.self) : nil
    accessibilityHint = allowsClipboard ? "Skriv eller lim inn svaret." : "Skriv svaret med egne ord."
  }
  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    let name = NSStringFromSelector(action)
    if [
      "copy:", "cut:", "paste:", "pasteAndMatchStyle:", "pasteAndGo:", "pasteAndSearch:", "captureTextFromCamera:",
      "translate:", "showWritingTools:",
    ].contains(name) {
      if !allowsClipboard || !(name.hasPrefix("paste") || name == "copy:" || name == "cut:") { return false }
    }
    return super.canPerformAction(action, withSender: sender)
  }
  override func paste(_ sender: Any?) {
    if allowsClipboard { super.paste(sender) } else { blocked?() }
  }
  func textPasteConfigurationSupporting(
    _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
    transform item: any UITextPasteItem
  ) {
    item.setNoResult()
    blocked?()
  }
  func textDroppableView(
    _ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: any UITextDropRequest
  ) -> UITextDropProposal {
    blocked?()
    return UITextDropProposal(operation: .cancel)
  }
  func configure() {
    pasteDelegate = self
    textDropDelegate = self
    textDragInteraction?.isEnabled = false
    pasteConfiguration = nil
    if #available(iOS 18.0, *) { writingToolsBehavior = .none }
    autocorrectionType = .yes
    spellCheckingType = .yes
    smartQuotesType = .yes
    font = UIFont.preferredFont(forTextStyle: .body)
    adjustsFontForContentSizeCategory = true
    backgroundColor = .secondarySystemGroupedBackground
    textContainerInset = UIEdgeInsets(top: 18, left: 12, bottom: 18, right: 12)
    layer.cornerRadius = 16
    accessibilityLabel = "Svaret ditt"
    accessibilityHint = "Skriv svaret med egne ord."
    accessibilityIdentifier = "answer-editor"
  }
}
struct AnswerEditor: UIViewRepresentable {
  @EnvironmentObject var model: AppModel
  @Binding var text: String
  var blocked: () -> Void
  func makeUIView(context: Context) -> OwnWordsTextView {
    let view = OwnWordsTextView()
    view.configure()
    #if DEBUG
    if model.testing {
      // Exercise exact input and draft persistence independently of the test
      // machine's keyboard language and learned spelling corrections.
      view.autocorrectionType = .no
      view.spellCheckingType = .no
    }
    #endif
    view.isScrollEnabled = false
    let toolbar = UIToolbar()
    toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace),
      UIBarButtonItem(title: "Ferdig med å skrive", primaryAction: UIAction { [weak view] _ in view?.resignFirstResponder() })]
    toolbar.sizeToFit()
    view.inputAccessoryView = toolbar
    view.setAccount(model.session?.user_id)
    view.delegate = context.coordinator
    view.blocked = blocked
    return view
  }
  func updateUIView(_ view: OwnWordsTextView, context: Context) {
    context.coordinator.parent = self
    view.setAccount(model.session?.user_id)
    view.applyModelText(text)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, uiView: OwnWordsTextView, context: Context) -> CGSize? {
    guard let width = proposal.width else { return nil }
    let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    return CGSize(width: width, height: max(230, size.height))
  }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: AnswerEditor
    init(_ parent: AnswerEditor) { self.parent = parent }
    func textViewDidChangeSelection(_ textView: UITextView) {
      (textView as? OwnWordsTextView)?.trace("selection changed")
    }
    func textViewDidChange(_ textView: UITextView) {
      (textView as? OwnWordsTextView)?.acknowledgeUserText()
      parent.text = textView.text
    }
  }
}
