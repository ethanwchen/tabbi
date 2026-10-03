import Foundation
import NotchKitCore

/// Drives the End-of-Day Review: shows today's numbers at once, asks the
/// local `claude` CLI for a short encouraging summary (falling back to a
/// local line), and saves the review when the user taps Done. The review
/// card replaces the checklist inline.
///
/// With `NOTCHDECK_DEMO=1` it shows `DayReview.sample` and never runs the
/// CLI or touches disk.
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
    private let repository: DayReviewRepository?
    private var task: Task<Void, Never>?
    /// Bumped on every open and close so a superseded run can't publish.
    private var generation = 0

    /// Longest wait for Claude before using the local summary.
    private static let timeout: Duration = .seconds(30)

    /// `studyPreview` makes the demo previews a study day's wrap-up, with
    /// the demo Anki reviews and a sample study tally; `sampleDay` picks
    /// the demo day reviewed.
    init(studyPreview: Bool = false, sampleDay: PlannerSampleDay = .work) {
        let environment = ProcessInfo.processInfo.environment
        isDemo = environment["NOTCHDECK_DEMO"] == "1"
        repository = isDemo ? nil : DayReviewRepository()
        // Lets demo snapshots render each state: `NOTCHDECK_PLANNER_PREVIEW=review`.
        guard isDemo else { return }
        let today = PlannerDayKey(date: Date())
        let progress = studyPreview ? [AnkiSummary.demo().progressItem()] : []
        let sample = DayReview.sample(on: today, kind: sampleDay, study: studyPreview ? .sample : nil,
                                      progress: progress)
        switch environment["NOTCHDECK_PLANNER_PREVIEW"] {
        case "review": review = sample
        case "review-loading":
            var loading = sample
            loading.summary = nil
            review = loading
        default: break
        }
    }

    /// Opens the review of `day` and starts writing its summary. `study`
    /// and `progress` are what other modules share; on a study day the demo
    /// fills in a sample tally, since no demo module keeps one yet.
    func wrapUp(day: PlannerDay, focusLog: FocusSessionLog, study: StudyDayTally? = nil,
                progress: [ProgressItem] = [], isStudyDay: Bool = false, sampleDay: PlannerSampleDay = .work) {
        invalidateRun()
        saveFailed = false
        let generation = generation

        if isDemo {
            var sample = DayReview.sample(on: day.date, kind: sampleDay, study: study ?? (isStudyDay ? .sample : nil),
                                         progress: progress)
            let summary = sample.summary
            sample.summary = nil
            review = sample
            task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.publish(generation, summary: summary)
            }
            return
        }

        let review = DayReviewer.review(of: day, focusLog: focusLog, study: study, progress: progress)
        self.review = review
        task = Task { [weak self] in
            let summary = await Self.summary(for: review)
            self?.publish(generation, summary: summary ?? DayReviewer.fallbackSummary(for: review))
        }
    }

    /// Saves the review and closes the card. Stays open if the file can't be written.
    func done() {
        guard var review else { return }
        // Done before Claude answered: keep the local line rather than nothing.
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

    /// Claude's cleaned-up summary, or nil when the CLI is missing, fails, or times out.
    private static func summary(for review: DayReview) async -> String? {
        guard let executable = await Task.detached(priority: .userInitiated, operation: { ClaudeCLI.locate() }).value else {
            return nil
        }
        let prompt = DayReviewer.prompt(for: review)
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var text: String?
                do {
                    let events = ClaudeCLI.stream(executable: executable, prompt: prompt,
                                                  extraArguments: DayReviewer.extraArguments())
                    for try await event in events {
                        if case .result(let result) = event, !result.isError { text = result.text }
                    }
                } catch {
                    // A successful result followed by a non-zero exit still counts.
                }
                return text.flatMap(DayReviewer.summary(from:))
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
