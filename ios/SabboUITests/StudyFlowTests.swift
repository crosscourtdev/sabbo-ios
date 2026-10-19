import XCTest

final class StudyFlowTests: XCTestCase {
  func testWriteReviewAndLocalCompletion() {
    let app = XCUIApplication()
    app.launchEnvironment["SABBO_UI_TEST"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["start-question"].waitForExistence(timeout: 10))
    app.buttons["start-question"].tap()
    let editor = app.textViews["answer-editor"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    editor.tap()
    editor.typeText("En undersøkelse må vurderes ut fra utvalg og metode.")
    app.buttons["submit-answer"].tap()
    XCTAssertTrue(app.buttons["Ditt svar"].waitForExistence(timeout: 5))
    app.swipeUp()
    app.buttons["Dette forsto jeg"].tap()
    XCTAssertTrue(
      app.staticTexts["Dagens seier!"].waitForExistence(timeout: 5))
  }
  func testGuidanceDoesNotCompleteDayAndBlankCannotSubmit() {
    let app = XCUIApplication()
    app.launchEnvironment["SABBO_UI_TEST"] = "1"
    app.launch()
    app.buttons["start-question"].tap()
    XCTAssertFalse(app.buttons["submit-answer"].isEnabled)
    app.buttons["Jeg vet ikke ennå"].tap()
    XCTAssertTrue(app.buttons["Et mulig svar"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["submit-answer"].isEnabled)
  }
}


final class ResultFlowTests: XCTestCase {
  private func open(_ state: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["SABBO_UI_TEST"] = "1"
    app.launchEnvironment["SABBO_RESULT_FIXTURE"] = state
    app.launch()
    app.buttons["start-question"].tap()
    XCTAssertTrue(app.buttons["result-done"].waitForExistence(timeout: 5))
    return app
  }
  func testResultDetailsAreOptionalAndDoneDoesNotOpenRewards() {
    let app = open("graded")
    XCTAssertTrue(app.staticTexts["Veiledende karakter 5 av 6"].exists)
    XCTAssertFalse(app.staticTexts["Jeg undersøker utvalget og metoden."].exists)
    app.buttons["result-done"].tap()
    XCTAssertTrue(app.buttons["start-question"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["close-streak-reward"].exists)
  }
  func testPendingAndOfflineCanBothBeClosed() {
    for state in ["waiting", "offline"] {
      let app = open(state)
      XCTAssertFalse(app.staticTexts["Veiledende karakter 5 av 6"].exists)
      XCTAssertTrue(app.staticTexts[state == "waiting" ? "Mottatt · Vurderer …" : "Åpne appen på nett for å levere."].exists)
      app.buttons["result-done"].tap()
      XCTAssertTrue(app.buttons["start-question"].waitForExistence(timeout: 5))
      app.terminate()
    }
  }
}


extension ResultFlowTests {
  func testLateResultKeepsGradeAndExplainsMissingRewards() {
    let app = open("late")
    XCTAssertTrue(app.staticTexts["Levert for sent"].exists)
    XCTAssertTrue(app.staticTexts["Veiledende karakter 5 av 6"].exists)
    XCTAssertFalse(app.staticTexts["+5 stjerner"].exists)
  }
  func testApprovedExceptionDoesNotClaimRewardsAreMissing() {
    let app = open("exception")
    XCTAssertTrue(app.staticTexts["Levert for sent · Belønning godkjent"].exists)
    XCTAssertTrue(app.staticTexts["Veiledende karakter 5 av 6"].exists)
    XCTAssertFalse(app.staticTexts["Levert for sent"].exists)
  }
}


final class BonusFlowTests: XCTestCase {
  private func open(_ state: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["SABBO_UI_TEST"] = "1"
    app.launchEnvironment["SABBO_BONUS_FIXTURE"] = state
    app.launch()
    XCTAssertTrue(app.buttons["start-question"].waitForExistence(timeout: 8))
    let home = XCTAttachment(screenshot: app.screenshot())
    home.name = "Home bonus " + state; home.lifetime = .keepAlways; add(home)
    return app
  }
  func testLateDeliveryExplainsMissingBonus() {
    let app = open("too_late")
    XCTAssertTrue(app.staticTexts["Ingen bonusrunde i dag"].exists)
    XCTAssertFalse(app.buttons["start-bonus"].exists)
  }
  func testHomeCountersAndAchievements() {
    let app = open("waiting")
    XCTAssertTrue(app.buttons["home-counter-stars"].exists)
    XCTAssertTrue(app.buttons["home-counter-fire"].exists)
    let home = XCTAttachment(screenshot: app.screenshot())
    home.name = "Compact quest home"; home.lifetime = .keepAlways; add(home)
    app.buttons["home-counter-stars"].tap()
    XCTAssertTrue(app.navigationBars["Stjerner og prestasjoner"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Studious"].exists)
    XCTAssertTrue(app.staticTexts["Drip check"].exists)
    let rewards = XCTAttachment(screenshot: app.screenshot())
    rewards.name = "Star rewards and achievements"; rewards.lifetime = .keepAlways; add(rewards)
    app.buttons["stars-reward-150"].tap()
    XCTAssertTrue(app.staticTexts["reward-unlock-day"].waitForExistence(timeout: 5))
    app.buttons["close-streak-reward"].tap()
    XCTAssertTrue(app.navigationBars["Stjerner og prestasjoner"].waitForExistence(timeout: 5))

  }
  func testCountdownAndWardrobe() {
    let app = open("waiting")
    XCTAssertTrue(app.staticTexts["Klar om 3 t 0 min"].exists)
    XCTAssertFalse(app.buttons["start-bonus"].exists)
    app.buttons["avatar-picker"].tap()
    XCTAssertTrue(app.navigationBars["Mitt tilbehør"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["tomorrow-outfit"].exists)
    let wardrobe = XCTAttachment(screenshot: app.screenshot())
    wardrobe.name = "Tomorrow outfit wardrobe"; wardrobe.lifetime = .keepAlways; add(wardrobe)
    XCTAssertTrue(app.buttons["Blå caps"].isEnabled)
    XCTAssertFalse(app.buttons["Låst tilbehør"].isEnabled)
  }
  func testReadyBonusHidesCachedDailyAnswersAndFeedback() {
    let app = open("ready")
    app.buttons["start-question"].tap()
    XCTAssertTrue(app.staticTexts["Veiledende karakter 5 av 6"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.otherElements["bonus-answers-hidden"].exists || app.staticTexts["Svarene vises etter bonusrunden"].exists)
    XCTAssertFalse(app.staticTexts["Du vurderer kilden med relevante fagbegreper."].exists)
  }
}

extension ResultFlowTests {
  func testTimelineGroupsDailyAndBonusWithoutHistoryTab() {
    let app = XCUIApplication()
    app.launchEnvironment["SABBO_UI_TEST"] = "1"
    app.launchEnvironment["SABBO_TIMELINE_FIXTURE"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["start-question"].waitForExistence(timeout: 10))
    #if targetEnvironment(macCatalyst)
    app.staticTexts["Sammen"].firstMatch.tap()
    #else
    app.tabBars.buttons["Sammen"].tap()
    XCTAssertFalse(app.tabBars.buttons["Historikk"].exists)
    #endif
    let day = app.buttons["timeline-day-fixture-result"]
    XCTAssertTrue(day.waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "timeline-day-fixture-result").count, 1)
    let timeline = XCTAttachment(screenshot: app.screenshot())
    timeline.name = "Shared timeline"; timeline.lifetime = .keepAlways; add(timeline)
    day.tap()
    XCTAssertTrue(app.staticTexts["Veiledende karakter 5 av 6"].waitForExistence(timeout: 5))
    app.segmentedControls["result-stage"].buttons["Bonusrunde"].tap()
    XCTAssertTrue(app.staticTexts["Veiledende karakter 6 av 6"].waitForExistence(timeout: 5))
    let bonus = XCTAttachment(screenshot: app.screenshot())
    bonus.name = "Bonus result"; bonus.lifetime = .keepAlways; add(bonus)
    XCTAssertFalse(app.staticTexts["Veiledende karakter 3 av 6"].exists)
    XCTAssertFalse(app.buttons["Forbedre svaret"].exists)
    XCTAssertFalse(app.buttons["Øv en gang til"].exists)
    app.segmentedControls["result-stage"].buttons["Dagens økt"].tap()
    XCTAssertTrue(app.staticTexts["Veiledende karakter 5 av 6"].exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Unified session results"; attachment.lifetime = .keepAlways; add(attachment)
  }
}
