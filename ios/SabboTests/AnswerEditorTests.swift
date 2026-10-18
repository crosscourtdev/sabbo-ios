import UIKit
import XCTest

@testable import Sabbo

@MainActor final class AnswerEditorTests: XCTestCase {
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
