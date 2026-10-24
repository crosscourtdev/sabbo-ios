import UIKit
import XCTest

@testable import Sabbo

@MainActor final class AnswerEditorTests: XCTestCase {
  func testRepeatedModelRenderPreservesInputBeforeDelegateNotification() {
    let editor = OwnWordsTextView()
    editor.configure()
    editor.applyModelText("J")
    editor.selectedRange = NSRange(location: 1, length: 0)
    // Reproduce the observed UIKit ordering: two insertions arrive before the
    // delegate publishes a new model value, while SwiftUI still renders "J".
    editor.insertText("e")
    editor.insertText("g")
    editor.applyModelText("J")
    XCTAssertEqual(editor.text, "Jeg")
    XCTAssertEqual(editor.selectedRange, NSRange(location: 3, length: 0))
    editor.acknowledgeUserText()
    editor.applyModelText("Jeg")
    XCTAssertEqual(editor.text, "Jeg")
    // An intentional model change back to an earlier draft must still apply.
    editor.applyModelText("J")
    XCTAssertEqual(editor.text, "J")
    XCTAssertEqual(editor.selectedRange, NSRange(location: 1, length: 0))
  }

  func testExternalDraftUpdatePreservesValidUTF16Cursor() {
    let editor = OwnWordsTextView()
    editor.configure()
    editor.applyModelText("Lang kladd med æ, ø og å")
    editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
    editor.applyModelText("Hei 👋")
    XCTAssertEqual(editor.text, "Hei 👋")
    XCTAssertEqual(editor.selectedRange, NSRange(location: ("Hei 👋" as NSString).length, length: 0))
  }

  func testPasteDoesNotInsertWhileTypingAndDraftRestoreWork() {
    let editor = OwnWordsTextView()
    editor.configure()
    editor.text = "Mitt eget svar."
    var blocked = 0
    editor.blocked = { blocked += 1 }
    editor.paste(nil)
    XCTAssertEqual(editor.text, "Mitt eget svar.")
    XCTAssertEqual(blocked, 1)
    XCTAssertFalse(
      editor.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
    editor.insertText(" Ærlig øving: Å, ø, æ og flere tegn.")
    XCTAssertTrue(editor.text.contains("Ærlig øving"))
    editor.deleteBackward()
    XCTAssertFalse(editor.text.hasSuffix("."))
    editor.text = "Min egen gjenopprettede kladd: æ ø å"
    XCTAssertEqual(editor.text, "Min egen gjenopprettede kladd: æ ø å")
    XCTAssertEqual(editor.writingToolsBehavior, .none)
    XCTAssertEqual(editor.autocorrectionType, .yes)
    XCTAssertNil(editor.pasteConfiguration)
  }
}

@MainActor final class OwnerClipboardTests: XCTestCase {
  func testClipboardAccessIsRevokedWhenAccountChanges() {
    let editor = OwnWordsTextView()
    editor.configure()
    editor.setAccount(ClientProfile.ownerID)
    XCTAssertTrue(editor.allowsClipboard)
    XCTAssertNil(editor.pasteDelegate)
    XCTAssertNotNil(editor.pasteConfiguration)
    for identity in [ClientProfile.learnerID, "reviewer", "unknown", nil] as [String?] {
      editor.setAccount(identity)
      XCTAssertFalse(editor.allowsClipboard)
      XCTAssertNotNil(editor.pasteDelegate)
      XCTAssertNil(editor.pasteConfiguration)
      XCTAssertFalse(editor.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
    }
  }
}
