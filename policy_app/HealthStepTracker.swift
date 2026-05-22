import Foundation
import Combine

#if canImport(HealthKit)
import HealthKit
#endif

struct DailyStepRecord: Identifiable, Equatable {
    let date: Date
    let steps: Double
    let hasData: Bool

    var id: Date { date }
}

struct DayCountGoalProgress: Identifiable, Equatable {
    let id: String
    let title: String
    let count: Int
    let targetDays: Int
    let thresholdRounded: String
    let status: String
}

struct StepTrackerMetrics: Equatable {
    let currentCycleLabel: String
    let averageSoFar: String
    let neededNext: String
    let lowStepDays: String
    let highStepDays: String
    let missingStepDays: String
    let dataCheckNote: String
    let score: Int?
    let scoreStage: String
    let scoreMessage: String
    let scoreProgress: Double
    let goals: [DayCountGoalProgress]
}

struct TodayPlanningGuide: Equatable {
    let title: String
    let rangeText: String
    let detail: String
}

@MainActor
final class HealthStepTracker: ObservableObject {
    enum State: Equatable {
        case idle
        case unavailable
        case loading
        case ready
        case failed(String)
    }

    @Published var cycleStartDate: Date {
        didSet {
            let normalized = min(Calendar.current.startOfDay(for: cycleStartDate), Calendar.current.startOfDay(for: Date()))
            if cycleStartDate != normalized {
                cycleStartDate = normalized
            } else {
                UserDefaults.standard.set(cycleStartDate, forKey: Self.cycleStartKey)
            }
        }
    }

    @Published private(set) var records: [DailyStepRecord] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var statusMessage = "Connect Apple Health to load daily steps for this 90-day cycle."
    @Published private(set) var hasRequestedHealthAccess = false

    private static let cycleStartKey = "HealthStepTrackerCycleStartDate"
    private let calendar = Calendar.current

    #if os(iOS) && canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif

    init() {
        if let saved = UserDefaults.standard.object(forKey: Self.cycleStartKey) as? Date {
            cycleStartDate = min(Calendar.current.startOfDay(for: saved), Calendar.current.startOfDay(for: Date()))
        } else {
            cycleStartDate = Calendar.current.startOfDay(for: Date())
        }
    }

    func connectAndLoad() async {
        #if os(iOS) && canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            statusMessage = "Apple Health is not available on this device."
            return
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            state = .unavailable
            statusMessage = "Step count data is not available."
            return
        }

        state = .loading
        statusMessage = "Requesting Apple Health permission..."

        do {
            try await requestAuthorization(reading: stepType)
            hasRequestedHealthAccess = true
            try await loadSteps()
        } catch {
            state = .failed(error.localizedDescription)
            statusMessage = "Could not load Apple Health steps: \(error.localizedDescription)"
        }
        #else
        state = .unavailable
        statusMessage = "HealthKit step reading is available on iPhone through the iOS app."
        #endif
    }

    func reloadIfConnected() async {
        guard hasRequestedHealthAccess else { return }
        await refresh()
    }

    func refresh() async {
        #if os(iOS) && canImport(HealthKit)
        state = .loading
        do {
            try await loadSteps()
        } catch {
            state = .failed(error.localizedDescription)
            statusMessage = "Could not refresh Apple Health steps: \(error.localizedDescription)"
        }
        #else
        state = .unavailable
        statusMessage = "HealthKit step reading is available on iPhone through the iOS app."
        #endif
    }

    func metrics(for result: PolicyResult, engine: PolicyEngine) -> StepTrackerMetrics {
        let hasStepRead = state == .ready || !records.isEmpty
        let observedRecords = records.filter(\.hasData)
        let stepValues = observedRecords.map(\.steps)
        let loggedDays = stepValues.count
        let totalSteps = stepValues.reduce(0, +)
        let average = loggedDays > 0 ? totalSteps / Double(loggedDays) : nil
        let checkedDays = currentCycleDay
        let missingDays = max(0, checkedDays - observedRecords.count)
        let remainingDays = max(90 - loggedDays, 0)
        let needed = remainingDays > 0 && loggedDays > 0
            ? max(0, (result.meanSteps * 90 - totalSteps) / Double(remainingDays))
            : nil

        let goals = [
            makeGoal(id: "usual", title: "Easy-day goal", targetDays: 60, threshold: result.q33, thresholdRounded: result.q33Rounded, stepValues: stepValues, loggedDays: loggedDays),
            makeGoal(id: "middle", title: "Regular-day goal", targetDays: 45, threshold: result.q50, thresholdRounded: result.q50Rounded, stepValues: stepValues, loggedDays: loggedDays),
            makeGoal(id: "active", title: "Active-day goal", targetDays: 30, threshold: result.q67, thresholdRounded: result.q67Rounded, stepValues: stepValues, loggedDays: loggedDays)
        ]

        let scoreInfo = liveScore(
            stepValues: stepValues,
            average: average,
            goals: goals,
            result: result,
            engine: engine
        )

        return StepTrackerMetrics(
            currentCycleLabel: "Day \(currentCycleDay) of 90",
            averageSoFar: average.map(formatHundred) ?? "--",
            neededNext: needed.map(formatHundred) ?? "--",
            lowStepDays: hasStepRead ? "\(stepValues.filter { $0 < 100 }.count)" : "--",
            highStepDays: hasStepRead ? "\(stepValues.filter { $0 > 22300 }.count)" : "--",
            missingStepDays: hasStepRead ? "\(missingDays)" : "--",
            dataCheckNote: hasStepRead
                ? "Checked \(checkedDays) day\(checkedDays == 1 ? "" : "s") in this cycle. Future days are not counted as missing."
                : "Connect Health to check missing or out-of-range step days.",
            score: scoreInfo.score,
            scoreStage: scoreInfo.stage,
            scoreMessage: scoreInfo.message,
            scoreProgress: scoreInfo.progress,
            goals: goals
        )
    }

    func todayPlanningGuide(for result: PolicyResult) -> TodayPlanningGuide {
        let observedRecords = records.filter(\.hasData)
        let stepValues = observedRecords.map(\.steps)
        let loggedDays = stepValues.count

        guard loggedDays > 0 else {
            return TodayPlanningGuide(
                title: "Easy-regular day",
                rangeText: "\(result.q33Rounded)-\(result.q50Rounded) steps",
                detail: "Start with this practical range while your 90-day progress data builds up."
            )
        }

        let cycleDay = currentCycleDay
        let easyCount = stepValues.filter { $0 >= result.q33 }.count
        let regularCount = stepValues.filter { $0 >= result.q50 }.count
        let activeCount = stepValues.filter { $0 >= result.q67 }.count
        let expectedEasy = expectedGoalDays(by: cycleDay, targetDays: 60)
        let expectedRegular = expectedGoalDays(by: cycleDay, targetDays: 45)
        let expectedActive = expectedGoalDays(by: cycleDay, targetDays: 30)
        let average = stepValues.reduce(0, +) / Double(loggedDays)
        let averageBehind = average < result.meanSteps * 0.95

        if activeCount < expectedActive {
            return TodayPlanningGuide(
                title: "Active-day opportunity",
                rangeText: "≈ \(result.q67Rounded) steps or more",
                detail: "Your active-day count is behind the pace for about 30 active days in this 90-day plan."
            )
        }

        if regularCount < expectedRegular || averageBehind {
            return TodayPlanningGuide(
                title: "Regular-active day",
                rangeText: "\(result.q50Rounded)-\(result.q67Rounded) steps",
                detail: "This range helps support your regular-day count or 90-day average progress."
            )
        }

        if average >= result.meanSteps * 1.08,
           easyCount >= expectedEasy,
           regularCount >= expectedRegular,
           activeCount >= expectedActive {
            return TodayPlanningGuide(
                title: "Easy day is fine",
                rangeText: "\(result.q33Rounded)-\(result.q50Rounded) steps",
                detail: "Your current pattern is ahead of pace, so a lighter day can still fit the 90-day distribution."
            )
        }

        return TodayPlanningGuide(
            title: "Easy-regular day",
            rangeText: "\(result.q33Rounded)-\(result.q50Rounded) steps",
            detail: "Your current pattern is on pace, so use this practical range for today."
        )
    }

    private var currentCycleDay: Int {
        let today = calendar.startOfDay(for: Date())
        let offset = calendar.dateComponents([.day], from: cycleStartDate, to: today).day ?? 0
        return Int(clamp(Double(offset + 1), min: 1, max: 90))
    }

    private func expectedGoalDays(by cycleDay: Int, targetDays: Int) -> Int {
        Int(floor((Double(cycleDay) / 90) * Double(targetDays)))
    }

    private func makeGoal(
        id: String,
        title: String,
        targetDays: Int,
        threshold: Double,
        thresholdRounded: String,
        stepValues: [Double],
        loggedDays: Int
    ) -> DayCountGoalProgress {
        let count = stepValues.filter { $0 >= threshold }.count
        let expectedForLogged = max(1, Int(round((Double(loggedDays) / 90) * Double(targetDays))))
        let ratio = loggedDays > 0 ? Double(count) / Double(expectedForLogged) : .nan
        return DayCountGoalProgress(
            id: id,
            title: title,
            count: count,
            targetDays: targetDays,
            thresholdRounded: thresholdRounded,
            status: statusLabel(ratio: ratio, loggedDays: loggedDays)
        )
    }

    private func liveScore(
        stepValues: [Double],
        average: Double?,
        goals: [DayCountGoalProgress],
        result: PolicyResult,
        engine: PolicyEngine
    ) -> (score: Int?, stage: String, message: String, progress: Double) {
        let loggedDays = stepValues.count
        guard loggedDays > 0, let average else {
            return (
                nil,
                "Not started",
                "Add at least 7 days of steps to calculate a Plan match score.",
                0
            )
        }

        guard loggedDays >= 7 else {
            return (
                nil,
                "Getting started",
                "Getting started: \(loggedDays) of 7 days logged. The score starts after 7 days so it is not based on too little data.",
                0
            )
        }

        let averageScore = meanAlignmentScore(average: average, target: result.meanSteps)
        let goalScores = goals.map { goal -> Double in
            guard goal.targetDays > 0 else { return 0 }
            let expectedForLogged = max(1, Int(round((Double(loggedDays) / 90) * Double(goal.targetDays))))
            return min(Double(goal.count) / Double(expectedForLogged), 1) * 100
        }
        let goalScore = goalScores.reduce(0, +) / Double(max(goalScores.count, 1))
        let distributionScore = distributionShapeScore(stepValues: stepValues, result: result, engine: engine)
        let distributionReliability = clamp((Double(loggedDays) - 7) / 23, min: 0, max: 1)
        let distributionWeight = 0.20 * distributionReliability
        let totalWeight = 0.45 + 0.35 + distributionWeight
        let rawScore = (
            averageScore * 0.45 +
            goalScore * 0.35 +
            distributionScore * distributionWeight
        ) / totalWeight
        let sampleReliability = clamp((Double(loggedDays) - 6) / 24, min: 0.25, max: 1)
        let score = Int(clamp(round(75 * (1 - sampleReliability) + rawScore * sampleReliability), min: 0, max: 100))
        let message: String
        if score >= 80 {
            message = "On plan: your average, goal-day counts, and step pattern are close to the 90-day prescription."
        } else if score >= 60 {
            message = "Close: one part of the plan needs support, such as average steps, goal-day counts, or the overall step pattern."
        } else {
            message = "Needs attention: your logged pattern is not yet matching the recommended 90-day distribution. Focus on the next few days."
        }

        return (score, scoreStage(score: score, loggedDays: loggedDays), message, Double(score) / 100)
    }

    private func meanAlignmentScore(average: Double, target: Double) -> Double {
        let isUnderTarget = average < target
        let tolerance = Swift.max(isUnderTarget ? 1_200 : 1_800, target * (isUnderTarget ? 0.18 : 0.25))
        let error = abs(average - target)
        return clamp(100 * (1 - error / (2 * tolerance)), min: 0, max: 100)
    }

    private func distributionShapeScore(
        stepValues: [Double],
        result: PolicyResult,
        engine: PolicyEngine
    ) -> Double {
        let levels = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
        let errors = levels.map { level in
            abs(actualQuantile(stepValues, level: level) - engine.nearestQuantilePoint(in: result, level: level).individual)
        }
        let meanAbsError = errors.reduce(0, +) / Double(errors.count)
        let tolerance = Swift.max(1_800, result.meanSteps * 0.22)
        return clamp(100 * (1 - meanAbsError / (2 * tolerance)), min: 0, max: 100)
    }

    private func statusLabel(ratio: Double, loggedDays: Int) -> String {
        guard ratio.isFinite else { return "--" }
        if loggedDays > 0 && loggedDays < 7 { return "Getting started" }
        if ratio >= 1 { return "On plan" }
        if ratio >= 0.8 { return "Close" }
        return "Needs attention"
    }

    private func scoreStage(score: Int, loggedDays: Int) -> String {
        if loggedDays == 0 { return "Not started" }
        if loggedDays < 7 { return "Getting started" }
        if score >= 80 { return "On plan" }
        if score >= 60 { return "Close" }
        return "Needs attention"
    }

    private func actualQuantile(_ values: [Double], level: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let position = level * Double(sorted.count - 1)
        let left = Int(floor(position))
        let right = Int(ceil(position))
        if left == right { return sorted[left] }
        let weight = position - Double(left)
        return sorted[left] * (1 - weight) + sorted[right] * weight
    }

    private func formatHundred(_ value: Double) -> String {
        let rounded = (value / 100).rounded() * 100
        return trackerIntegerFormatter.string(from: NSNumber(value: rounded)) ?? "\(Int(rounded))"
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    #if os(iOS) && canImport(HealthKit)
    private func requestAuthorization(reading stepType: HKQuantityType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: [stepType]) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthStepTrackerError.authorizationDenied)
                }
            }
        }
    }

    private func loadSteps() async throws {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthStepTrackerError.stepTypeUnavailable
        }

        let start = calendar.startOfDay(for: cycleStartDate)
        let ninetyDayEnd = calendar.date(byAdding: .day, value: 90, to: start) ?? Date()
        let end = min(Date(), ninetyDayEnd)
        let fetched = try await fetchDailySteps(stepType: stepType, start: start, end: end)
        records = fetched
        state = .ready
        let daysWithSteps = fetched.filter(\.hasData).count
        statusMessage = daysWithSteps == 0
            ? "Connected to Apple Health. No step data was found for this cycle yet."
            : "Connected to Apple Health through HealthKit. Read \(daysWithSteps) day\(daysWithSteps == 1 ? "" : "s") of steps."
    }

    private func fetchDailySteps(stepType: HKQuantityType, start: Date, end: Date) async throws -> [DailyStepRecord] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[DailyStepRecord], Error>) in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
            let interval = DateComponents(day: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }

                var output: [DailyStepRecord] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = statistics.sumQuantity()
                    let steps = quantity?.doubleValue(for: HKUnit.count()) ?? 0
                    output.append(DailyStepRecord(date: statistics.startDate, steps: steps, hasData: quantity != nil))
                }
                continuation.resume(returning: output)
            }

            healthStore.execute(query)
        }
    }
    #endif
}

enum HealthStepTrackerError: LocalizedError {
    case authorizationDenied
    case stepTypeUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Health permission was not granted."
        case .stepTypeUnavailable:
            return "Step count data is not available."
        }
    }
}

private let trackerIntegerFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    return formatter
}()
