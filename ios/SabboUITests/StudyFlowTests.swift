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
    XCTAssertFalse(app.buttons["Svar og eksempelsvar"].exists)
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
  func testGradeRevealKeepsTheFinalGradeAccessibleAndLands() {
    let app = open("graded")
    XCTAssertTrue(app.staticTexts["Veiledende karakter 5 av 6"].exists)
    let counting = XCTAttachment(screenshot: app.screenshot())
    counting.name = "Grade reveal counting"; counting.lifetime = .keepAlways; add(counting)
    XCTAssertTrue(app.staticTexts["Sterkt levert!"].waitForExistence(timeout: 6))
    let landed = XCTAttachment(screenshot: app.screenshot())
    landed.name = "Grade reveal landed"; landed.lifetime = .keepAlways; add(landed)
    app.buttons["result-done"].tap()
    XCTAssertTrue(app.buttons["start-question"].waitForExistence(timeout: 5))
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
    XCTAssertTrue(app.navigationBars["Stjerner og achievements"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Studious"].exists)
    XCTAssertTrue(app.staticTexts["Drip check"].exists)
    let rewards = XCTAttachment(screenshot: app.screenshot())
    rewards.name = "Star rewards and achievements"; rewards.lifetime = .keepAlways; add(rewards)
    app.buttons["stars-reward-150"].tap()
    XCTAssertTrue(app.staticTexts["reward-unlock-day"].waitForExistence(timeout: 5))
    let gift = XCTAttachment(screenshot: app.screenshot())
    gift.name = "Locked star gift"; gift.lifetime = .keepAlways; add(gift)
    app.buttons["close-streak-reward"].tap()
    XCTAssertTrue(app.navigationBars["Stjerner og achievements"].waitForExistence(timeout: 5))
    app.buttons["Ferdig"].tap()
    let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
      object: app.navigationBars["Stjerner og achievements"])
    XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    app.buttons["home-counter-fire"].tap()
    XCTAssertTrue(app.navigationBars["Streak"].waitForExistence(timeout: 5))
    let streak = XCTAttachment(screenshot: app.screenshot())
    streak.name = "Streak treasure chests"; streak.lifetime = .keepAlways; add(streak)
  }
  func testEarnedGiftOpensBeforeRevealingItsMessage() {
    let app = open("waiting")
    app.buttons["home-counter-stars"].tap()
    XCTAssertTrue(app.navigationBars["Stjerner og achievements"].waitForExistence(timeout: 5))
    app.buttons["stars-reward-50"].tap()
    XCTAssertTrue(app.staticTexts["reward-message"].waitForExistence(timeout: 6))
    XCTAssertFalse(app.staticTexts["reward-unlock-day"].exists)
    let chest = XCTAttachment(screenshot: app.screenshot())
    chest.name = "Opened star gift"; chest.lifetime = .keepAlways; add(chest)
    app.buttons["close-streak-reward"].tap()
    XCTAssertTrue(app.navigationBars["Stjerner og achievements"].waitForExistence(timeout: 5))
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
    let bonusButton = app.segmentedControls["result-stage"].buttons["Bonusrunde"]
    XCTAssertFalse(app.staticTexts["Veiledende karakter 5 av 6"].frame.intersects(bonusButton.frame),
      "Decorative grade confetti must not cover the result selector's accessibility area")
    bonusButton.tap()
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


extension ResultFlowTests {
  func testSubmitLeadsToQuestionChoiceAndKeepsAutomaticallyMergedAnswer() {
    let app = XCUIApplication()
    app.launchEnvironment["SABBO_UI_TEST"] = "1"
    app.launchEnvironment["SABBO_DRAFT_FIXTURE"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["start-question"].waitForExistence(timeout: 10))
    app.buttons["start-question"].tap()
    app.buttons["next-question"].tap()
    app.buttons["next-question"].tap()
    let submit = app.buttons["submit-session"]
    XCTAssertTrue(submit.waitForExistence(timeout: 5))
    XCTAssertTrue(submit.isEnabled)
    submit.tap()
    let choice = app.buttons["draft-choice-q1-remote"]
    XCTAssertTrue(choice.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["draft-choice-q2-remote"].exists)
    XCTAssertFalse(app.buttons["confirm-draft-choices"].isEnabled)
    let before = XCTAttachment(screenshot: app.screenshot())
    before.name = "Choose the answer to submit"; before.lifetime = .keepAlways; add(before)
    choice.tap()
    app.buttons["confirm-draft-choices"].tap()
    XCTAssertTrue(submit.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Jeg undersøker avsenderen og metoden."].exists)
    XCTAssertTrue(app.staticTexts["Jeg sammenligner flere uavhengige kilder."].exists)
    XCTAssertTrue(submit.isEnabled)
    let after = XCTAttachment(screenshot: app.screenshot())
    after.name = "Review both resolved answers"; after.lifetime = .keepAlways; add(after)
    submit.tap()
    XCTAssertTrue(app.buttons["result-done"].waitForExistence(timeout: 5))
  }
}

extension ResultFlowTests {
  func testUpdateNoticeCanBeDismissedWithoutBlockingStudy() {
    let app = XCUIApplication()
    app.launchEnvironment["SABBO_UI_TEST"] = "1"
    app.launchEnvironment["SABBO_UPDATE_FIXTURE"] = "1"
    app.launch()
    XCTAssertTrue(app.staticTexts["Oppdatering tilgjengelig"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.links["open-testflight"].exists || app.buttons["open-testflight"].exists)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "Update notice on home"; shot.lifetime = .keepAlways; add(shot)
    app.buttons["dismiss-update"].tap()
    XCTAssertFalse(app.staticTexts["Oppdatering tilgjengelig"].exists)
    XCTAssertTrue(app.buttons["start-question"].exists)
    app.buttons["start-question"].tap()
    XCTAssertFalse(app.buttons["dismiss-update"].exists)
  }
}


extension ResultFlowTests {
  private func presentation(_ mode: String, large: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["SABBO_UI_TEST"] = "1"
    app.launchEnvironment["SABBO_PRESENTATION_FIXTURE"] = mode
    if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
    app.launch()
    XCTAssertTrue(app.buttons["start-question"].waitForExistence(timeout: 10))
    return app
  }
  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<12 {
      if element.isHittable { return }
      let scroll = activeScroll(app)
      // Short drags avoid jumping past controls in compact result sheets.
      // Aim toward the middle so the fixed footer cannot cover the target.
      let movingDown = element.frame.midY < scroll.frame.midY
      let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: movingDown ? 0.35 : 0.65))
      let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: movingDown ? 0.65 : 0.35))
      start.press(forDuration: 0.05, thenDragTo: end)
    }
  }
  private func activeScroll(_ app: XCUIApplication) -> XCUIElement {
    app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app.scrollViews.firstMatch
  }
  private func evidence(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
  }
  func testLongAnswersCompareAtTheSameQuestionAndProtectLockedPeers() {
    for mode in ["reading", "locked"] {
      let app = presentation(mode)
      #if targetEnvironment(macCatalyst)
      app.staticTexts["Sammen"].firstMatch.tap()
      #else
      app.tabBars.buttons["Sammen"].tap()
      #endif
      let day = app.buttons["timeline-day-presentation-day"]
      XCTAssertTrue(day.waitForExistence(timeout: 5))
      evidence(app, "Searchable shared timeline " + mode)
      day.tap()
      let toggle = app.switches["compare-answers"]
      XCTAssertTrue(toggle.waitForExistence(timeout: 5))
      toggle.tap()
      let next = app.buttons["Neste oppgave"]
      reveal(next, app: app); next.tap()
      XCTAssertTrue(app.staticTexts["Oppgave 2"].exists)
      evidence(app, "Question comparison " + mode)
      if mode == "locked" {
        XCTAssertFalse(app.staticTexts["Jeg sammenligner utvalgene."].exists)
      } else {
        reveal(app.staticTexts["Jeg sammenligner utvalgene."], app: app)
        XCTAssertTrue(app.staticTexts["Jeg sammenligner utvalgene."].exists)
        evidence(app, "Both answers and criteria")
      }
      app.terminate()
    }
  }
  func testSwitchingPeopleRetainsQuestionAndBonusStage() {
    let app = presentation("reading")
    app.buttons["start-question"].tap()
    let next = app.buttons["Neste oppgave"]
    reveal(next, app: app); next.tap()
    XCTAssertTrue(app.staticTexts["Oppgave 2"].exists)
    let person = app.segmentedControls["result-person"]
    for _ in 0..<8 {
      if person.buttons.element(boundBy: 1).isHittable { break }
      activeScroll(app).swipeDown()
    }
    person.buttons.element(boundBy: 1).tap()
    XCTAssertTrue(app.staticTexts["Oppgave 2"].exists)
    app.segmentedControls["result-stage"].buttons["Bonusrunde"].tap()
    XCTAssertTrue(app.staticTexts["Ingen bonusbesvarelse fra denne personen ennå."].waitForExistence(timeout: 5))
    evidence(app, "Peer bonus empty state")
    person.buttons["Meg"].tap()
    XCTAssertTrue(app.segmentedControls["result-stage"].buttons["Bonusrunde"].isSelected)
    XCTAssertTrue(app.staticTexts["Oppgave 2"].exists)
    evidence(app, "Person switch retains question and bonus round")
  }
  func testWritingResumesQuestionAndKeepsKeyboardNavigationAvailable() {
    let app = presentation("writing")
    app.buttons["start-question"].tap()
    XCTAssertTrue(app.staticTexts["Oppgave 2 av 2"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["next-question"].isEnabled)
    let editor = app.textViews["answer-editor"]
    reveal(editor, app: app); editor.tap(); editor.typeText("Jeg sammenligner to forklaringer.")
    XCTAssertEqual(editor.value as? String, "Jeg sammenligner to forklaringer.")
    XCTAssertTrue(app.buttons["next-question"].isHittable)
    evidence(app, "Writing with keyboard navigation")
    app.buttons["Lukk"].tap()
    app.buttons["start-question"].tap()
    XCTAssertTrue(app.staticTexts["Oppgave 2 av 2"].waitForExistence(timeout: 5))
    reveal(editor, app: app)
    XCTAssertEqual(editor.value as? String, "Jeg sammenligner to forklaringer.")
    app.buttons["next-question"].tap()
    reveal(app.buttons["submit-session"], app: app)
    XCTAssertTrue(app.buttons["submit-session"].isEnabled)
    evidence(app, "Long answer final review")
  }
  func testLargeTextShowsUntruncatedNextStepAndCriterionLabels() {
    let app = presentation("reading", large: true)
    app.buttons["start-question"].tap()
    let advice = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Beskriv hvilke opplysninger")).firstMatch
    reveal(advice, app: app)
    XCTAssertTrue(advice.label.contains("mulige forklaringer."))
    evidence(app, "Large text full next step")
    let criterion = app.staticTexts["Sammenligne kildenes metode og avsender"]
    reveal(criterion, app: app)
    XCTAssertTrue(criterion.exists)
    XCTAssertTrue(app.staticTexts["Godt oppfylt"].exists)
    evidence(app, "Large text named criterion")
  }
}
