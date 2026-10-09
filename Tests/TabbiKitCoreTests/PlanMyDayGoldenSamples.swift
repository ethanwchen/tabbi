import Foundation
import TabbiKitCore

/// The days and proposals `PlanMyDayGoldenFixture` records.
extension PlanMyDayGoldenFixture {
    /// Wall-clock times on one day in one time zone, as seconds since 1970.
    struct Clock {
        let timeZone: String
        let midnight: Date
        let calendar: Calendar

        init(_ timeZone: String, _ year: Int, _ month: Int, _ day: Int) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZone)!
            self.timeZone = timeZone
            self.calendar = calendar
            midnight = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }

        func t(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Double {
            calendar.date(bySettingHour: hour, minute: minute, second: second, of: midnight)!.timeIntervalSince1970
        }

        func event(_ id: String, _ title: String, _ start: (Int, Int), _ end: (Int, Int), allDay: Bool = false) -> Event {
            if allDay {
                let next = calendar.date(byAdding: .day, value: 1, to: midnight)!
                return Event(id: id, title: title, start: midnight.timeIntervalSince1970,
                             end: next.timeIntervalSince1970, isAllDay: true)
            }
            return Event(id: id, title: title, start: t(start.0, start.1), end: t(end.0, end.1))
        }
    }

    static func taskID(_ number: Int) -> String {
        String(format: "00000000-0000-4000-8000-%012d", number)
    }

    static func task(_ number: Int, _ title: String, done: Bool = false) -> Task {
        Task(id: taskID(number), title: title, isDone: done)
    }

    static let monday = Clock("America/Los_Angeles", 2026, 10, 12)

    /// The days, each planned on device, as a study day and from Claude's
    /// answers, whatever its `planMode`.
    static func sampleDays() -> [(name: String, input: DayInput)] {
        let day = monday
        let workEvents: [Event] = [
            day.event("holiday", "Columbus Day", (0, 0), (0, 0), allDay: true),
            day.event("standup", "Standup", (10, 0), (10, 15)),
            day.event("lunch", "Lunch with Sam", (12, 0), (13, 0)),
            day.event("one-on-one", "1:1 with Priya", (13, 0), (13, 30)),
            day.event("blank", "  ", (16, 0), (16, 30)),
        ]
        let workTasks: [Task] = [
            task(1, "Ship planner beta"),
            task(2, "  Draft   release notes "),
            task(3, "Water the plants", done: true),
            task(4, "Review the onboarding copy for the Med School kit"),
        ]
        let workProvided: [Provided] = [
            Provided(module: "anki", progress: [
                Goal(id: "reviews", title: "Anki reviews", completed: 120, target: 300, unit: "cards"),
            ]),
            Provided(module: "leetcode", tasks: [
                SharedTask(id: "daily", title: "LeetCode: Two Sum", estimatedMinutes: 20),
                SharedTask(id: "done", title: "LeetCode: Warm-up", isDone: true, estimatedMinutes: 10),
            ]),
            Provided(module: "focus", progress: [
                Goal(id: "focus", title: "Focus goal", completed: 0, target: 4, unit: "sessions", waitsForStart: true),
            ]),
        ]
        let workAnswers: [String] = [
            // Fenced, with prose around it, a task key and a shared-work key.
            """
            Here is a plan for you:
            ```json
            {"blocks":[{"start":"10:20","end":"11:50","title":"Ship planner beta","task":"t1"},\
            {"start":"13:40","end":"14:25","title":"Draft release notes","task":"T2"},\
            {"start":"14:35","end":"15:05","title":"Anki reviews","task":"t4"}]}
            ```
            Good luck!
            """,
            // A bare array with H:mm times, a lowercase UUID and the taskId key.
            """
            [{"start":"9:45","end":"9:59","title":"Too short"},\
            {"start":"14:00","end":"15:30","title":"  Review   onboarding copy ","taskId":"\(taskID(4).lowercased())"},\
            {"start":"15:00","end":"16:45","title":"Overlaps the last one and a meeting"}]
            """,
            // Bad entries are skipped: missing fields, end before start, bad
            // times, a blank title, an unknown task; 24:00 is midnight.
            """
            {"blocks":[{"start":"11:00","title":"No end"},{"start":"15:00","end":"14:00","title":"Backwards"},\
            {"start":"25:00","end":"26:00","title":"Hour 25"},{"start":"10:5","end":"11:00","title":"One-digit minute"},\
            {"start":"10:30","end":"11:30","title":"   "},{"start":"17:00","end":"24:00","title":"Until midnight","task":"t9"},\
            {"start":"08:00","end":"09:30","title":"Before now","linkedTaskID":"t1"}]}
            """,
            // More blocks than fit, all valid: the validator keeps five.
            """
            {"blocks":[{"start":"10:20","end":"10:40","title":"One"},{"start":"10:45","end":"11:05","title":"Two"},\
            {"start":"11:10","end":"11:30","title":"Three"},{"start":"11:35","end":"11:55","title":"Four"},\
            {"start":"13:40","end":"14:00","title":"Five"},{"start":"14:05","end":"14:25","title":"Six"}]}
            """,
            "{\"blocks\":[]}",
            "I could not find any free time today.",
            "{\"plan\":\"none\"}",
            "\"just a string\"",
        ]

        var days: [(name: String, input: DayInput)] = []

        var workday = DayInput(timeZone: day.timeZone, now: day.t(9, 41, 30), events: workEvents, tasks: workTasks,
                               provided: workProvided, answers: workAnswers)
        workday.refineAnswers = refineAnswers(for: workday)
        days.append(("workday-local", workday))

        var claudeDay = workday
        claudeDay.settings.planMode = "claude"
        claudeDay.refineAnswers = []
        days.append(("workday-claude", claudeDay))

        var claudeFails = claudeDay
        claudeFails.answers = ["I could not find any free time today."]
        days.append(("workday-claude-no-json", claudeFails))

        var claudeEmpty = claudeDay
        claudeEmpty.answers = ["{\"blocks\":[]}"]
        days.append(("workday-claude-empty-plan", claudeEmpty))

        // A study day: lectures, a lab, a big review queue, a later end.
        let studyEvents: [Event] = [
            day.event("lecture", "Cardiology lecture", (9, 0), (11, 0)),
            day.event("lab", "Anatomy lab", (14, 0), (16, 0)),
            day.event("shift", "Clinic shift", (19, 30), (21, 30)),
        ]
        let studyProvided: [Provided] = [
            Provided(module: "anki", progress: [
                Goal(id: "reviews", title: "Anki reviews", completed: 80, target: 400, unit: "cards"),
            ]),
            Provided(module: "study", progress: [
                Goal(id: "questions", title: "UWorld questions", completed: 0, target: 40, unit: "questions"),
                Goal(id: "minutes", title: "Study time", completed: 30, target: 240, unit: "min", waitsForStart: true),
            ]),
        ]
        var studyDay = DayInput(timeZone: day.timeZone, now: day.t(8, 5), events: studyEvents,
                                tasks: [task(11, "Renal physiology chapter"), task(12, "Pharm flashcards")],
                                provided: studyProvided)
        studyDay.settings = Settings(planMode: "study", studyMethod: "fiftyTwoSeventeen", reviewsFirst: true,
                                     eventBufferMinutes: 10, studyBlockTitle: "Study block", secondsPerCard: 8,
                                     dayEndHour: 21)
        studyDay.refineAnswers = refineAnswers(for: studyDay)
        days.append(("study-day-52-17", studyDay))

        // Reviews last, a queue past the cap split over gaps, long breaks.
        var reviewsLast = studyDay
        reviewsLast.now = day.t(11, 2)
        reviewsLast.provided = [Provided(module: "anki", progress: [
            Goal(id: "reviews", title: "Anki reviews", completed: 0, target: 900, unit: "cards"),
        ])]
        reviewsLast.tasks = []
        reviewsLast.settings = Settings(planMode: "study", studyMethod: "pomodoro", reviewsFirst: false,
                                        eventBufferMinutes: 0, studyBlockTitle: "  Deep   work ", secondsPerCard: 10,
                                        dayEndHour: 22)
        reviewsLast.refineAnswers = []
        days.append(("study-reviews-last", reviewsLast))

        // Every study method's block and break lengths on the same day.
        for method in ["ultradian", "flowtime", "ankiSprint", "questionBlock", "custom", "timer"] {
            var input = studyDay
            input.settings.studyMethod = method
            input.settings.planMode = method == "timer" ? "local" : "study"
            input.refineAnswers = []
            days.append(("method-\(method)", input))
        }

        // Long shared work split into blocks, up to the focus limit.
        let longWork: [Provided] = [Provided(module: "projects", tasks: [
            SharedTask(id: "thesis", title: "Thesis chapter", estimatedMinutes: 200),
            SharedTask(id: "grant", title: "Grant draft", estimatedMinutes: 150),
            SharedTask(id: "slides", title: "Slides", estimatedMinutes: 101),
            SharedTask(id: "email", title: "Email", estimatedMinutes: 3),
            SharedTask(id: "blank", title: "   "),
        ])]
        var longDay = DayInput(timeZone: day.timeZone, now: day.t(6, 0), events: [
            day.event("gym", "Gym", (12, 15), (13, 0)),
        ], tasks: [task(21, "Read paper"), task(22, "Gym")], provided: longWork)
        longDay.settings.dayEndHour = 22
        longDay.answers = ["{\"blocks\":[{\"start\":\"06:00\",\"end\":\"08:00\",\"title\":\"Early start\"}]}"]
        days.append(("long-work-splits", longDay))

        // Planning in the evening: two hours from now, past the usual end.
        var evening = DayInput(timeZone: day.timeZone, now: day.t(19, 7), events: [
            day.event("dinner", "Dinner", (19, 30), (20, 15)),
        ], tasks: [task(31, "Tidy inbox")])
        evening.settings.planMode = "claude"
        evening.answers = ["{\"blocks\":[{\"start\":\"20:15\",\"end\":\"21:30\",\"title\":\"Tidy inbox\",\"task\":\"t1\"}]}"]
        days.append(("evening", evening))

        // After 10 pm nothing is left to plan.
        var late = DayInput(timeZone: day.timeZone, now: day.t(22, 30), tasks: [task(41, "Anything")])
        late.answers = ["{\"blocks\":[{\"start\":\"22:30\",\"end\":\"23:30\",\"title\":\"Anything\"}]}"]
        days.append(("after-ten", late))

        // Back-to-back meetings leave only slivers.
        let packed: [Event] = [
            day.event("a", "Design review", (9, 0), (10, 50)),
            day.event("b", "Hiring sync", (11, 0), (12, 55)),
            day.event("c", "Planning", (13, 5), (15, 0)),
            day.event("d", "Customer call", (15, 10), (18, 0)),
        ]
        days.append(("packed-calendar", DayInput(timeZone: day.timeZone, now: day.t(8, 58), events: packed,
                                                 tasks: [task(51, "Write spec")])))

        // A meeting under way at `now`, and an early kit end hour.
        var early = DayInput(timeZone: day.timeZone, now: day.t(7, 3), events: [
            day.event("early", "Breakfast meeting", (6, 30), (7, 40)),
            day.event("same-title", "Write report", (11, 0), (11, 30)),
        ], tasks: [task(61, "Write report"), task(62, "Plan trip")])
        early.settings.dayEndHour = 10
        early.settings.eventBufferMinutes = 15
        early.answers = ["{\"blocks\":[{\"start\":\"07:00\",\"end\":\"08:30\",\"title\":\"Plan trip\",\"task\":\"t2\"}]}"]
        days.append(("early-end-meeting-under-way", early))

        // The day clocks spring forward (New York, 8 March 2026).
        let spring = Clock("America/New_York", 2026, 3, 8)
        var dst = DayInput(timeZone: spring.timeZone, now: spring.t(8, 0), events: [
            spring.event("brunch", "Brunch", (11, 0), (12, 30)),
        ], tasks: [task(71, "Taxes"), task(72, "Call mom")])
        dst.answers = ["{\"blocks\":[{\"start\":\"09:00\",\"end\":\"10:30\",\"title\":\"Taxes\",\"task\":\"t1\"},"
            + "{\"start\":\"13:00\",\"end\":\"24:00\",\"title\":\"Call mom\",\"task\":\"t2\"}]}"]
        dst.refineAnswers = refineAnswers(for: dst)
        days.append(("dst-spring-forward", dst))

        // A day east of UTC, with nothing on the calendar.
        let tokyo = Clock("Asia/Tokyo", 2026, 10, 13)
        var empty = DayInput(timeZone: tokyo.timeZone, now: tokyo.t(9, 0), tasks: [task(81, "Write blog post")])
        empty.answers = ["{\"blocks\":[{\"start\":\"09:00\",\"end\":\"10:00\",\"title\":\"Write blog post\",\"task\":\"t1\"}]}"]
        days.append(("empty-calendar-tokyo", empty))

        return days
    }

    /// Refine answers for a day: the local plan as it is (unchanged), the
    /// plan with its first block moved and retitled (kinds carried over by
    /// task and by title), one with no JSON, and an empty plan.
    private static func refineAnswers(for input: DayInput) -> [String] {
        let output = plan(input)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: input.timeZone)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let keys = Dictionary(uniqueKeysWithValues: output.taskKeys.compactMap { entry -> (String, String)? in
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[1], parts[0]) : nil
        })
        func entry(_ start: Double, _ end: Double, _ title: String, _ task: String?) -> String {
            let link = task.flatMap { keys[$0] }.map { ",\"task\":\"\($0)\"" } ?? ""
            return "{\"start\":\"\(formatter.string(from: Date(timeIntervalSince1970: start)))\","
                + "\"end\":\"\(formatter.string(from: Date(timeIntervalSince1970: end)))\",\"title\":\"\(title)\"\(link)}"
        }
        let blocks = output.local.blocks
        let same = blocks.map { entry($0.start, $0.end, $0.title, $0.task) }
        var changed = same
        if let first = blocks.first {
            changed[0] = entry(first.start + 5 * 60, first.end, first.task == nil ? first.title.lowercased() : "Renamed",
                               first.task)
            changed.reverse()
        }
        return [
            "{\"blocks\":[\(same.joined(separator: ","))]}",
            "{\"blocks\":[\(changed.joined(separator: ","))]}",
            "Looks good to me.",
            "{\"blocks\":[]}",
        ]
    }

    // MARK: Proposals

    static func blockID(_ number: Int) -> String {
        String(format: "B0000000-0000-4000-8000-%012d", number)
    }

    static var sampleProposals: [(String, [Block], [Interval], [StepInput])] {
        let day = monday
        func block(_ number: Int, _ start: (Int, Int), _ end: (Int, Int), _ title: String, task: Int? = nil,
                   kind: String = "focus") -> Block {
            Block(id: blockID(number), start: day.t(start.0, start.1), end: day.t(end.0, end.1), title: title,
                  task: task.map(taskID), kind: kind)
        }
        func rest(_ start: (Int, Int), _ end: (Int, Int)) -> Interval {
            Interval(start: day.t(start.0, start.1), end: day.t(end.0, end.1))
        }
        let study: [Block] = [
            block(1, (10, 0), (10, 30), "Anki reviews", kind: "reviews"),
            block(2, (10, 35), (11, 0), "Renal chapter", task: 11, kind: "study"),
            block(3, (11, 5), (11, 30), "Study block", kind: "study"),
            block(4, (13, 0), (13, 25), "Study block", kind: "study"),
            block(5, (14, 0), (15, 0), "Pharm flashcards", task: 12, kind: "study"),
        ]
        let studyBreaks: [Interval] = [rest((10, 30), (10, 35)), rest((11, 0), (11, 5))]
        let meeting = day.event("surprise", "Surprise meeting", (10, 40), (10, 50))

        return [
            ("dismiss-then-add-all", study, studyBreaks, [
                StepInput(action: "dismiss", id: blockID(2)),
                StepInput(action: "dismiss", id: blockID(9)),
                StepInput(action: "add", at: day.t(9, 30), events: []),
            ]),
            ("add-one-at-a-time-as-time-passes", study, studyBreaks, [
                StepInput(action: "add", ids: [blockID(1)], at: day.t(10, 7, 30), events: []),
                StepInput(action: "add", ids: [blockID(2)], at: day.t(10, 20), events: [meeting]),
                StepInput(action: "add", ids: [blockID(3)], at: day.t(11, 20), events: []),
                StepInput(action: "add", ids: [blockID(4)], at: day.t(12, 0), events: [
                    day.event("all-day", "Holiday", (0, 0), (0, 0), allDay: true),
                    day.event("cover", "Covers it", (12, 55), (13, 30)),
                ]),
                StepInput(action: "add", ids: [blockID(5)], at: day.t(12, 0), events: [
                    day.event("split", "Splits it", (14, 10), (14, 20)),
                ]),
            ]),
            ("writer-fails-then-succeeds", study, studyBreaks, [
                StepInput(action: "add", at: day.t(9, 0), events: [], writerFails: true),
                StepInput(action: "add", ids: [blockID(3), blockID(4), blockID(9)], at: day.t(9, 0), events: [],
                          writerFails: false),
                StepInput(action: "add", ids: [], at: day.t(9, 0), events: []),
            ]),
            ("refine", study, studyBreaks, [
                StepInput(action: "refine", blocks: []),
                StepInput(action: "refine", blocks: study.reversed()),
                StepInput(action: "refine", blocks: [
                    block(11, (10, 0), (10, 30), "Anki reviews", kind: "reviews"),
                    block(12, (10, 35), (11, 0), "Renal chapter", task: 11, kind: "study"),
                    block(13, (11, 30), (12, 0), "Study block", kind: "study"),
                ]),
                StepInput(action: "dismiss", id: blockID(12)),
                StepInput(action: "add", at: day.t(9, 0), events: []),
            ]),
        ]
    }
}
