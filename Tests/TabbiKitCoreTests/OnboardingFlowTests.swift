import XCTest
@testable import TabbiKitCore

/// First-run onboarding asks only what the chosen tabs need, each step can be
/// skipped, and Back and re-picking keep the user's changes.
final class OnboardingFlowTests: XCTestCase {
    private let catalog = ModuleCatalog.builtIn
    private var medicine: KitManifest { KitLibrary.bundled["medicine"]! }
    private var essentials: KitManifest { KitLibrary.bundled["essentials"]! }

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
            .setup("pet"), .setup("anki"), .setup("calendar"), .setup("studyMethod"),
        ])
        XCTAssertEqual(flow.stage, .question("stage"))
        XCTAssertEqual(flow.layout, medicine.layout(catalog: catalog))
    }

    func testSkippingWalksEssentialsThroughItsSetupSteps() {
        var flow = flow()
        flow.choose(essentials)
        XCTAssertEqual(flow.stage, .question("day"))
        flow.next()
        XCTAssertEqual(flow.stage, .modules)
        XCTAssertEqual(flow.setupSteps, [.pet, .calendar, .studyMethod])
        flow.next()
        XCTAssertEqual(flow.currentSetupStep, .pet)
        flow.next()
        XCTAssertEqual(flow.currentSetupStep, .calendar)
        flow.next()
        XCTAssertEqual(flow.currentSetupStep, .studyMethod)
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
        flow.choose(essentials)
        XCTAssertFalse(flow.stages.contains(.setup("anki")))
        flow.setEnabled(.anki, true)
        XCTAssertEqual(flow.setupSteps, [.pet, .anki, .calendar, .studyMethod], "ranked, not in tab order")
        flow.setEnabled(.planner, false)
        XCTAssertEqual(flow.setupSteps, [.pet, .anki, .studyMethod])
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
        flow.choose(essentials)
        flow.setEnabled(.spotify, false)
        flow.move(fromOffsets: [3], toOffset: 0)
        let tweaked = flow.layout
        flow.back()
        XCTAssertEqual(flow.stage, .kit)
        flow.choose(essentials)
        XCTAssertEqual(flow.layout, tweaked)
    }

    func testPickingAnotherKitStartsOverFromItsTabs() {
        var flow = flow()
        flow.choose(medicine)
        flow.answer("clinical")
        flow.back()
        flow.back()
        flow.choose(essentials)
        XCTAssertEqual(flow.answers, [:])
        XCTAssertEqual(flow.layout, essentials.layout(catalog: catalog))
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

    func testAskingTheNameOpensOnTheNameStepBeforeTheKit() {
        var flow = OnboardingFlow(catalog: catalog, layout: ModuleLayout(catalog: catalog), asksName: true)
        XCTAssertEqual(flow.stage, .name)
        XCTAssertEqual(flow.stages.prefix(2), [.name, .kit])
        XCTAssertEqual(flow.stageIndex, 0)
        XCTAssertFalse(flow.canGoBack, "the name step is the first one")
        flow.next()
        XCTAssertEqual(flow.stage, .kit, "skipping the name moves on to the kits")
        XCTAssertTrue(flow.canGoBack)
        flow.back()
        XCTAssertEqual(flow.stage, .name)
        flow.next()
        flow.choose(essentials)
        XCTAssertEqual(flow.stage, .question("day"))
        XCTAssertEqual(flow.stages.first, .name, "picking a kit keeps the name step in the progress")
    }

    func testPickingAKitFromTheNameStepAnswersTheKitStep() {
        var flow = OnboardingFlow(catalog: catalog, layout: ModuleLayout(catalog: catalog), asksName: true)
        flow.choose(essentials)
        XCTAssertEqual(flow.stage, .question("day"))
        var scratch = OnboardingFlow(catalog: catalog, layout: ModuleLayout(catalog: catalog), asksName: true)
        scratch.startFromScratch()
        XCTAssertEqual(scratch.stage, .modules)
    }

    func testNotAskingTheNameStartsOnTheKit() {
        let flow = flow()
        XCTAssertFalse(flow.stages.contains(.name))
        XCTAssertEqual(flow.stage, .kit)
    }

    func testBundledModulesWithSetupStepsMatchTheFixture() {
        XCTAssertEqual(catalog.descriptor(for: .closet).setup, [.pet])
        XCTAssertEqual(catalog.descriptor(for: .system).setup, [])
    }
}
