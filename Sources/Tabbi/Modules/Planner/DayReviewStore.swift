import Foundation
import TabbiKitCore

/// Drives the End-of-Day Review: shows today's numbers at once, asks the
/// AI the user picked for a short encouraging summary (falling back to a
/// local line), and saves the review when the user taps Done. The review
/// card replaces the checklist inline.
///
/// With `TABBI_DEMO=1` it shows `DayReview.sample` and never asks an AI
/// or touches disk.
@MainActor
final class DayReviewStore: ObservableObject {
    /// The open review, or nil while the checklist shows.
    @Published private(set) var review: DayReview?
    /// True when Done couldn't write the file; the card stays open.
    @Published private(set) var saveFailed = false

    var isActive: Bool { review != nil }
    /// Waiting for the summary; the card shows a shimmer in its place.
    var isSummarizing: Bool { review != nil && review?.summary == nil }

    private let isDemo: Bool
    /// The AI the user picked. Nil (tests) shows the local line at once.
    private let ai: AIService?
    private let repository: DayReviewRepository?
    private var task: Task<Void, Never>?
    /// Bumped on every open and close so a superseded run can't publish.
    private var generation = 0

    /// Longest wait for the AI before using the local summary.
    private static let timeout: Duration = .seconds(30)

    /// `studyPreview` makes the demo previews a study day's wrap-up, with
    /// the demo Anki reviews and a sample study tally; `sampleDay` picks
    /// the demo day reviewed.
    init(storage: EditionStorage, studyPreview: Bool = false, sampleDay: PlannerSampleDay = .work,
         ai: AIService? = nil, runMode: RunMode) {
        let environment = ProcessInfo.processInfo.environment
        isDemo = runMode.isDemo
        self.ai = ai
        repository = isDemo ? nil : DayReviewRepository(storage: storage)
        // Lets demo snapshots render each state: `TABBI_PLANNER_PREVIEW=review`.
        guard isDemo else { return }
        let today = PlannerDayKey(date: Date())
        let progress = studyPreview ? [AnkiSummary.demo().progressItem()] : []
        let sample = DayReview.sample(on: today, kind: sampleDay, study: studyPreview ? .sample : nil,
                                      progress: progress)
        switch environment["TABBI_PLANNER_PREVIEW"] {
        case "review": review = sample
        case "review-loading":
            var loading = sample
            loading.summary = nil
            review = loading
        default: break
        }
    }

    /// Opens the review of `day` and starts writing its summary. `activity`
    /// is the shared log's records of that day, and `study` and `progress`
    /// are what other modules share; on a study day the demo
    /// fills in a sample tally, since no demo module keeps one yet.
    func wrapUp(day: PlannerDay, activity: [ActivityRecord], study: StudyDayTally? = nil,
                progress: [ProgressItem] = [], isStudyDay: Bool = false, sampleDay: PlannerSampleDay = .work) {
        invalidateRun()
        saveFailed = false
        let generation = generation

        if isDemo {
            var sample = DayReview.sample(on: day.date, kind: sampleDay, study: study ?? (isStudyDay ? .sample : nil),
                                         progress: progress)
            // Without an AI the local line shows at once, so there's no wait to preview.
            guard ai != nil else {
                review = sample
                return
            }
            let summary = sample.summary
            sample.summary = nil
            review = sample
            task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.publish(generation, summary: summary)
            }
            return
        }

        var review = DayReviewer.review(of: day, activity: activity, study: study, progress: progress)
        // Nothing is sent before a provider is picked and set up: the
        // local line shows at once instead of a shimmer.
        guard let ai, ai.setupState.isReady else {
            review.summary = DayReviewer.fallbackSummary(for: review)
            self.review = review
            return
        }
        self.review = review
        task = Task { [weak self] in
            let summary = await Self.summary(for: review, from: ai)
            self?.publish(generation, summary: summary ?? DayReviewer.fallbackSummary(for: review))
        }
    }

    /// Saves the review and closes the card. Stays open if the file can't be written.
    func done() {
        guard var review else { return }
        // Done before the AI answered: keep the local line rather than nothing.
        if review.summary == nil { review.summary = DayReviewer.fallbackSummary(for: review) }
        do {
            try repository?.save(review)
        } catch {
            self.review = review
            saveFailed = true
            return
        }
        close()
    }

    /// Closes the card without saving.
    func close() {
        invalidateRun()
        saveFailed = false
        review = nil
    }

    // MARK: - Private

    private func invalidateRun() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func publish(_ generation: Int, summary: String?) {
        guard generation == self.generation, review != nil else { return }
        review?.summary = summary
    }

    /// The AI's cleaned-up summary, or nil when it can't answer, fails, or times out.
    private static func summary(for review: DayReview, from ai: AIService) async -> String? {
        guard let provider = await ai.readyProvider()?.provider,
              let text = try? await provider.answer(.prompt(DayReviewer.prompt(for: review)), timeout: timeout)
        else { return nil }
        return DayReviewer.summary(from: text)
    }
}
