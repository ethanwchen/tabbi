import Foundation

/// The outcome of "Refine with Claude" on an on-device plan.
public enum PlanRefinement: Hashable, Sendable {
    /// Claude moved, resized, retitled or dropped blocks.
    case changed
    /// Claude found nothing to improve.
    case unchanged
}

/// "Refine with Claude": an optional second look at the local planner's
/// proposal. Claude gets the same day, free time and tasks as a plain Plan
/// my day request plus the local plan as the starting point, and its answer
/// goes through the same parser and validator, so a refined plan still never
/// overlaps an event or starts in the past.
public extension DayPlanner {
    /// The prompt for refining `plan` (the blocks still on offer) on
    /// `context`'s day. Blocks name their task id where they work on a
    /// checklist item, so Claude can keep the link.
    static func refinePrompt(for context: DayPlanContext, plan: [PlanBlock]) -> String {
        let clock = clockFormatter(context.calendar)
        let keys = Dictionary(uniqueKeysWithValues: context.taskKeys.map { ($0.task.id, $0.key) })
        let lines = plan.sorted { $0.start < $1.start }.map { block -> String in
            let task = block.linkedTaskID.flatMap { keys[$0] }.map { " (task \($0))" } ?? ""
            return "- \(clock.string(from: block.start))-\(clock.string(from: block.end)) \(block.title)\(task)"
        }
        return """
        \(prompt(for: context, limit: refineLimit(plan)))

        An on-device planner already proposed this plan, which is your starting point:
        \(lines.isEmpty ? "- none" : lines.joined(separator: "\n"))

        Keep what works and change only what clearly makes the day better: \
        the order, block lengths, breaks between blocks, or a task it missed. \
        Answer with the complete plan in the JSON format above, unchanged if it is already good.
        """
    }

    /// Claude's refinement of `plan`, validated against `context`. Blocks
    /// keep the kind (reviews, study) of the local block for the same task,
    /// or with the same title, so the proposal still marks them.
    static func refinement(from text: String, context: DayPlanContext, plan: [PlanBlock]) throws -> [PlanBlock] {
        let blocks = validate(try parse(text, context: context), context: context, limit: refineLimit(plan))
        return blocks.map { block in
            let local = plan.first { $0.linkedTaskID != nil && $0.linkedTaskID == block.linkedTaskID }
                ?? plan.first { $0.title.caseInsensitiveCompare(block.title) == .orderedSame }
            var block = block
            if let local { block.kind = local.kind }
            return block
        }
    }

    /// A refined plan may keep every local block, even past `maximumBlocks`.
    private static func refineLimit(_ plan: [PlanBlock]) -> Int { max(maximumBlocks, plan.count) }
}

public extension DayPlanner {
    /// The final result text of one `claude -p` run with the planner's
    /// arguments, or nil on an error or after `timeout`. Plan my day and the
    /// Schedule's Refine both ask Claude this way.
    static func answer(executable: URL, prompt: String, timeout: Duration = .seconds(60)) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var text: String?
                do {
                    let events = ClaudeCLI.stream(executable: executable, prompt: prompt,
                                                  extraArguments: extraArguments())
                    for try await event in events {
                        if case .result(let result) = event, !result.isError { text = result.text }
                    }
                } catch {
                    // A successful result followed by a non-zero exit still counts.
                }
                return text
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
