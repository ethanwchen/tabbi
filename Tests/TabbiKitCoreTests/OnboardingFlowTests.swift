import XCTest
@testable import TabbiKitCore

/// First-run onboarding asks only what the chosen tabs need, each step can be
/// skipped, and Back and re-picking keep the user's changes.
final class OnboardingFlowTests: XCTestCase {
    private let catalog = ModuleCatalog.builtIn
    private var medicine: KitManifest { KitLibrary.bundled["medicine"]! }
    private var productivity: KitManifest { KitLibrary.bundled["productivity"]! }

    private func flow() -> OnboardingFlow {
        OnboardingFlow(catalog: catalog, layout: ModuleLayout(catalog: catalog))
    }

    func testStartsOnTheKitStep() {
        let flow = flow()
        XCTAssertEqual(flow.stage, .kit)
        XCTAssertFalse(flow.canGoBack)
        XCTAssertEqual(flow.stageIndex, 0)
    }

    func testMedSchoolAsksItsQuestionsThenTabsThenOnlyItsModulesSetup() {
        var flow = flow()
        flow.choose(medicine)
        XCTAssertEqual(flow.stages, [
            .kit, .question("stage"), .question("anki"), .modules,
            .setup("pet"), .setup("anki"), .setup("calendar"), .setup("studyMethod"), .setup("party"),
        ])
        XCTAssertEqual(flow.stage, .question("stage"))
        XCTAssertEqual(flow.layout, medicine.layout(catalog: catalog))
    }

    func testSkippingWalksProductivityToItsOnlySetupStep() {
        var flow = flow()
        flow.choose(productivity)
        XCTAssertEqual(flow.stage, .question("work"))
        flow.next()
        XCTAssertEqual(flow.stage, .modules)
        XCTAssertEqual(flow.setupSteps, [.calendar])
        flow.next()
        XCTAssertEqual(flow.currentSetupStep, .calendar)
        flow.next()
        XCTAssertEqual(flow.stage, .finished)
        XCTAssertEqual(flow.stageIndex, flow.stages.count)
    }

    func testASingleChoiceAnswerTakesOneTapAndCanTurnATabOff() {
        var flow = flow()
        flow.choose(medicine)
        flow.answer("preclinical")
        XCTAssertEqual(flow.stage, .question("anki"))
        flow.answer("no")
        XCTAssertEqual(flow.stage, .modules)
        XCTAssertEqual(flow.answers, ["stage": ["preclinical"], "anki": ["no"]])
        XCTAssertFalse(flow.layout.isEnabled(.anki))
        XCTAssertFalse(flow.setupSteps.contains(.anki), "no Anki tab, so no Connect Anki step")
    }

    func testTurningATabOnAddsItsSetupStepJustInTime() {
        var flow = flow()
        flow.choose(productivity)
        XCTAssertFalse(flow.stages.contains(.setup("pet")))
        flow.setEnabled(.closet, true)
        XCTAssertEqual(flow.setupSteps, [.pet, .calendar], "ranked, not in tab order")
        flow.setEnabled(.planner, false)
        XCTAssertEqual(flow.setupSteps, [.pet])
    }

    func testTwoModulesNeedingTheSameStepAskItOnce() {
        let shared = OnboardingSetupStep("shared", title: "Shared", symbol: "star")
        let catalog = ModuleCatalog([
            ModuleDescriptor(id: "a", title: "A", symbol: "a.circle", category: .fun,
                             accent: ModuleAccent(red: 1, green: 0, blue: 0), setup: [shared, .pet]),
            ModuleDescriptor(id: "b", title: "B", symbol: "b.circle", category: .fun,
                             accent: ModuleAccent(red: 0, green: 1, blue: 0), setup: [shared]),
        ])
        let flow = OnboardingFlow(catalog: catalog, layout: ModuleLayout(catalog: catalog))
        XCTAssertEqual(flow.setupSteps.map(\.id), ["pet", "shared"])
    }

    func testStartFromScratchBeginsWithOneTabAndNoQuestions() {
        var flow = flow()
        flow.startFromScratch()
        XCTAssertNil(flow.kit)
        XCTAssertTrue(flow.startedFromScratch)
        XCTAssertEqual(flow.stage, .modules)
        XCTAssertEqual(flow.layout.enabled, [catalog.ids[0]])
        XCTAssertEqual(flow.layout.order, catalog.ids)
    }

    func testGoingBackAndRepickingTheSameKitKeepsTabChanges() {
        var flow = flow()
        flow.choose(productivity)
        flow.setEnabled(.system, false)
        flow.move(fromOffsets: [3], toOffset: 0)
        let tweaked = flow.layout
        flow.back()
        XCTAssertEqual(flow.stage, .kit)
        flow.choose(productivity)
        XCTAssertEqual(flow.layout, tweaked)
    }

    func testPickingAnotherKitStartsOverFromItsTabs() {
        var flow = flow()
        flow.choose(medicine)
        flow.answer("clinical")
        flow.back()
        flow.back()
        flow.choose(productivity)
        XCTAssertEqual(flow.answers, [:])
        XCTAssertEqual(flow.layout, productivity.layout(catalog: catalog))
    }

    func testTheLastTabCannotBeTurnedOff() {
        var flow = flow()
        flow.startFromScratch()
        XCTAssertFalse(flow.setEnabled(catalog.ids[0], false))
        XCTAssertEqual(flow.layout.enabled, [catalog.ids[0]])
    }

    func testFinishSkipsTheRestFromAnywhere() {
        var flow = flow()
        flow.choose(medicine)
        flow.finish()
        XCTAssertEqual(flow.stage, .finished)
        XCTAssertFalse(flow.canGoBack)
        flow.back()
        XCTAssertEqual(flow.stage, .finished)
    }

    func testRerunningPreselectsTheActiveKitAndAnswers() {
        let answers: KitAnswers = ["stage": ["clinical"]]
        var flow = OnboardingFlow(catalog: catalog, layout: medicine.layout(catalog: catalog, answers: answers),
                                  kit: medicine, answers: answers)
        XCTAssertEqual(flow.stage, .kit)
        flow.choose(medicine)
        XCTAssertEqual(flow.answers, answers, "re-picking the active kit keeps its answers")
    }

    func testBundledModulesWithSetupStepsMatchTheFixture() {
        XCTAssertEqual(catalog.descriptor(for: .closet).setup, [.pet])
        XCTAssertEqual(catalog.descriptor(for: .system).setup, [])
    }
}
