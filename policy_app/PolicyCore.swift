import Foundation

enum SexAtBirth: String, CaseIterable, Codable, Identifiable {
    case female = "Female"
    case male = "Male"

    var id: String { rawValue }
}

struct PatientProfile: Equatable {
    var glucose: Double?
    var bmi: Double
    var dbp: Double
    var sbp: Double
    var age: Double
    var sex: SexAtBirth
}

struct PolicyCurvePoint: Identifiable, Equatable {
    enum Curve: String {
        case individual
        case subgroup
    }

    let id: String
    let x: Double
    let y: Double
    let curve: Curve
}

struct DensityPeak: Codable, Equatable, Identifiable {
    let index: Int
    let step: Double
    let density: Double
    let prominence: Double

    var id: Int { index }
}

struct SubgroupProfile: Equatable {
    struct Bucket: Equatable {
        let code: Int
        let label: String
        let rangeLabel: String
    }

    let glucose: Bucket
    let age: Bucket
    let bmi: Bucket
    let bp: Bucket
    let sex: SexAtBirth
    let glucoseImputed: Bool

    var key: String {
        "g\(glucose.code)_a\(age.code)_b\(bmi.code)_p\(bp.code)_sex\(sex.rawValue)_imp\(glucoseImputed ? 1 : 0)"
    }

    var label: String {
        "\(glucose.label), \(age.label), \(bmi.label), \(bp.label)"
    }

    var fullLabel: String {
        let glucoseSource = glucoseImputed ? "glucose imputed" : "glucose measured"
        return "\(glucose.label), \(age.label), \(bmi.label), \(bp.label), \(sex.rawValue), \(glucoseSource)"
    }
}

struct PolicyResult {
    let profile: PatientProfile
    let glucoseRaw: Double
    let glucoseImputed: Bool
    let state: [Double]
    let lqd: [Double]
    let quantile: [Double]
    let density: [Double]
    let referenceQuantile: [Double]
    let referenceDensity: [Double]
    let subgroup: SubgroupProfile
    let peaks: [DensityPeak]
    let meanSteps: Double
    let meanDensity: Double
    let q33: Double
    let q50: Double
    let q67: Double

    let meanRounded: String
    let primaryStepRounded: String
    let peakCardText: String
    let q33Rounded: String
    let q50Rounded: String
    let q67Rounded: String
    let interpretationSummary: String
    let interpretation: String
}

enum PolicyError: LocalizedError, Equatable {
    case missingModelData
    case invalidModelData(String)
    case missingRequiredField(String)
    case invalidNumericInput(String)
    case unknownSex(String)

    var errorDescription: String? {
        switch self {
        case .missingModelData:
            return "Policy model data could not be loaded."
        case .invalidModelData(let message):
            return message
        case .missingRequiredField(let field):
            return "Missing required input: \(field)."
        case .invalidNumericInput(let field):
            return "Invalid numeric input for \(field)."
        case .unknownSex(let value):
            return "Unknown sex at birth: \(value)."
        }
    }
}

struct PolicyModelData: Codable {
    struct Standardization: Codable {
        let mean: Double
        let std: Double
    }

    struct Imputer: Codable {
        let coef: [Double]
        let intercept: Double
        let residualSdScaled: Double
        let residualSdRaw: Double
        let nTrainingRows: Int
        let features: [String]
    }

    struct Policy: Codable {
        let coefficients: [[Double]]
        let basis: [[Double]]
    }

    struct Supports: Codable {
        let lqd: [Double]
        let density: [Double]
    }

    struct Bounds: Codable {
        let min: Double
        let max: Double
    }

    struct DailyStepsSupport: Codable {
        let min: Double
        let max: Double
    }

    struct ExampleRaw: Codable {
        let glucose: String
        let bmi: Double
        let dbp: Double
        let sbp: Double
        let age: Double
        let sex: String
    }

    let checkpointName: String
    let standardization: [String: Standardization]
    let sexMapping: [String: Double]
    let stateOrder: [String]
    let imputer: Imputer
    let policy: Policy
    let supports: Supports
    let glucoseBounds: Bounds
    let dailyStepsSupport: DailyStepsSupport
    let subgroupReferenceSampleCount: Int
    let exampleRaw: ExampleRaw

    static func load(bundle: Bundle = .main) throws -> PolicyModelData {
        let decoder = JSONDecoder()
        if let url = bundle.url(forResource: "PolicyModelData", withExtension: "json") {
            return try decoder.decode(PolicyModelData.self, from: Data(contentsOf: url))
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("PolicyModelData.json")
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return try decoder.decode(PolicyModelData.self, from: Data(contentsOf: sourceURL))
        }

        throw PolicyError.missingModelData
    }
}

struct PolicyEngine {
    let data: PolicyModelData

    init(data: PolicyModelData) {
        self.data = data
    }

    static func live() throws -> PolicyEngine {
        try PolicyEngine(data: PolicyModelData.load())
    }

    func exampleProfile() throws -> PatientProfile {
        guard let sex = SexAtBirth(rawValue: data.exampleRaw.sex) else {
            throw PolicyError.unknownSex(data.exampleRaw.sex)
        }
        return PatientProfile(
            glucose: Double(data.exampleRaw.glucose),
            bmi: data.exampleRaw.bmi,
            dbp: data.exampleRaw.dbp,
            sbp: data.exampleRaw.sbp,
            age: data.exampleRaw.age,
            sex: sex
        )
    }

    func evaluate(profile: PatientProfile) throws -> PolicyResult {
        try validateModelData()
        let stateInfo = buildState(profile: profile)
        let lqd = policyLqd(from: stateInfo.state)
        let quantile = lqdToQuantile(lqd)
        let density = lqdToDensity(lqd: lqd, quantile: quantile)
        let subgroup = profileSubgroup(
            glucoseRaw: stateInfo.glucoseRaw,
            age: profile.age,
            bmi: profile.bmi,
            sbp: profile.sbp,
            dbp: profile.dbp,
            sex: profile.sex,
            glucoseImputed: stateInfo.glucoseImputed
        )
        let reference = subgroupReference(result: stateInfo, subgroup: subgroup)
        let peaks = densityPeaks(density)
        let meanSteps = densityMean(density)
        let meanDensity = densityValue(at: meanSteps, density: density)
        let quantileRows = selectedQuantiles(quantile)
        let q33 = quantileRows[0].value
        let q67 = quantileRows[1].value
        let q50 = interpolate(x: data.supports.lqd, y: quantile, xNew: [0.5])[0]
        let meanRounded = formatHundred(meanSteps)
        let primaryStepRounded = formatHundred(peaks.max(by: { $0.density < $1.density })?.step ?? meanSteps)
        let peakCardText = peaks.map { "≈ \(formatHundred($0.step))" }.joined(separator: ", ")
        let q33Rounded = formatHundred(q33)
        let q50Rounded = formatHundred(q50)
        let q67Rounded = formatHundred(q67)
        let peakSummary = formatStepList(peaks.map(\.step))
        let peakPhrase = peaks.count == 1
            ? "The highest-frequency point in the 90-day distribution is around \(peakSummary) daily steps."
            : "The highest-frequency points in the 90-day distribution are around \(peakSummary) daily steps."
        let peakDaysPhrase = peaks.count == 1 ? "this step level" : "these step levels"
        let interpretationSummary = "90-day target: \(meanRounded) average daily steps. Most frequent level: \(peakCardText)."
        let interpretation =
            "This profile belongs to the subgroup: \(subgroup.fullLabel). " +
            "The gray curves show the subgroup average recommendation for profiles in the same covariate subgroup. " +
            "For this individual profile, the recommended 90-day average is approximately \(meanRounded) daily steps. " +
            "\(peakPhrase) To better lower cardiometabolic risk, we recommend that, in the next 90 days, the user averages approximately " +
            "\(meanRounded) daily steps and walks near \(peakDaysPhrase) on more days. The next 90 days can still be arranged flexibly: " +
            "low activity days can be around approximately \(q33Rounded) daily steps, moderate activity " +
            "periods can stay between approximately \(q33Rounded) and \(q67Rounded) " +
            "daily steps, and high activity periods should reach at least approximately \(q67Rounded) daily steps."

        return PolicyResult(
            profile: profile,
            glucoseRaw: stateInfo.glucoseRaw,
            glucoseImputed: stateInfo.glucoseImputed,
            state: stateInfo.state,
            lqd: lqd,
            quantile: quantile,
            density: density,
            referenceQuantile: reference.quantile,
            referenceDensity: reference.density,
            subgroup: subgroup,
            peaks: peaks,
            meanSteps: meanSteps,
            meanDensity: meanDensity,
            q33: q33,
            q50: q50,
            q67: q67,
            meanRounded: meanRounded,
            primaryStepRounded: primaryStepRounded,
            peakCardText: peakCardText,
            q33Rounded: q33Rounded,
            q50Rounded: q50Rounded,
            q67Rounded: q67Rounded,
            interpretationSummary: interpretationSummary,
            interpretation: interpretation
        )
    }

    func selectedQuantiles(_ quantile: [Double]) -> [(level: Double, value: Double)] {
        let levels = [0.33, 0.67]
        let values = interpolate(x: data.supports.lqd, y: quantile, xNew: levels)
        return levels.enumerated().map { index, level in (level, values[index]) }
    }

    func densityValue(at step: Double, density: [Double]) -> Double {
        interpolate(x: data.supports.density, y: density, xNew: [step])[0]
    }

    func densityMean(_ density: [Double]) -> Double {
        let weighted = density.enumerated().map { index, value in value * data.supports.density[index] }
        return trapz(y: weighted, x: data.supports.density) / trapz(y: density, x: data.supports.density)
    }

    func nearestDensityPoint(in result: PolicyResult, step: Double) -> (step: Double, individual: Double, subgroup: Double) {
        let clamped = clamp(step, min: data.dailyStepsSupport.min, max: data.dailyStepsSupport.max)
        let individual = densityValue(at: clamped, density: result.density)
        let subgroup = densityValue(at: clamped, density: result.referenceDensity)
        return (clamped, individual, subgroup)
    }

    func nearestQuantilePoint(in result: PolicyResult, level: Double) -> (level: Double, individual: Double, subgroup: Double) {
        let clamped = clamp(level, min: 0, max: 1)
        let individual = interpolate(x: data.supports.lqd, y: result.quantile, xNew: [clamped])[0]
        let subgroup = interpolate(x: data.supports.lqd, y: result.referenceQuantile, xNew: [clamped])[0]
        return (clamped, individual, subgroup)
    }
}

private extension PolicyEngine {
    struct StateInfo {
        let glucoseRaw: Double
        let glucoseImputed: Bool
        let state: [Double]
    }

    struct Reference {
        let density: [Double]
        let quantile: [Double]
    }

    func validateModelData() throws {
        guard data.policy.coefficients.count == 7 else {
            throw PolicyError.invalidModelData("Expected 7 policy coefficient rows.")
        }
        guard data.policy.basis.count == data.policy.coefficients[0].count else {
            throw PolicyError.invalidModelData("Basis rows and coefficient columns do not match.")
        }
        guard data.supports.lqd.count == data.policy.basis[0].count,
              data.supports.density.count == data.policy.basis[0].count else {
            throw PolicyError.invalidModelData("Support and basis lengths do not match.")
        }
    }

    func buildState(profile: PatientProfile) -> StateInfo {
        let glucoseRaw: Double
        let glucoseScaled: Double
        let glucoseImputed: Bool

        if let glucose = profile.glucose {
            glucoseRaw = glucose
            glucoseScaled = standardize(glucose, variableName: "GLU")
            glucoseImputed = false
        } else {
            let imputed = imputeGlucoseScaled(
                bmi: profile.bmi,
                dbp: profile.dbp,
                sbp: profile.sbp,
                age: profile.age,
                sex: profile.sex
            )
            glucoseRaw = imputed.glucoseRaw
            glucoseScaled = imputed.glucoseScaled
            glucoseImputed = true
        }

        return StateInfo(
            glucoseRaw: glucoseRaw,
            glucoseImputed: glucoseImputed,
            state: [
                glucoseScaled,
                standardize(profile.bmi, variableName: "BMI"),
                standardize(profile.dbp, variableName: "DBP"),
                standardize(profile.sbp, variableName: "SBP"),
                standardize(profile.age, variableName: "age_att"),
                data.sexMapping[profile.sex.rawValue] ?? 0,
                glucoseImputed ? 1 : 0,
            ]
        )
    }

    func standardize(_ value: Double, variableName: String) -> Double {
        guard let cfg = data.standardization[variableName] else { return value }
        return (value - cfg.mean) / cfg.std
    }

    func unstandardizeGlucose(_ glucoseScaled: Double) -> Double {
        guard let cfg = data.standardization["GLU"] else { return glucoseScaled }
        return glucoseScaled * cfg.std + cfg.mean
    }

    func imputeGlucoseScaled(bmi: Double, dbp: Double, sbp: Double, age: Double, sex: SexAtBirth) -> (glucoseScaled: Double, glucoseRaw: Double) {
        let features = [
            standardize(bmi, variableName: "BMI"),
            standardize(dbp, variableName: "DBP"),
            standardize(sbp, variableName: "SBP"),
            standardize(age, variableName: "age_att"),
            data.sexMapping[sex.rawValue] ?? 0,
        ]
        var glucoseScaled = data.imputer.intercept
        for index in features.indices {
            glucoseScaled += data.imputer.coef[index] * features[index]
        }
        let glucoseRaw = clamp(unstandardizeGlucose(glucoseScaled), min: data.glucoseBounds.min, max: data.glucoseBounds.max)
        return (standardize(glucoseRaw, variableName: "GLU"), glucoseRaw)
    }

    func policyLqd(from state: [Double]) -> [Double] {
        let coefficients = data.policy.coefficients
        let basis = data.policy.basis
        var basisCoef = Array(repeating: 0.0, count: coefficients[0].count)

        for j in basisCoef.indices {
            for k in state.indices {
                basisCoef[j] += state[k] * coefficients[k][j]
            }
        }

        return basis[0].indices.map { i in
            basis.indices.reduce(0.0) { total, j in
                total + basis[j][i] * basisCoef[j]
            }
        }
    }

    func lqdToQuantile(_ lqd: [Double]) -> [Double] {
        let lqdSup = data.supports.lqd
        let densitySup = data.supports.density
        var quantile = Array(repeating: 0.0, count: lqd.count)
        quantile[0] = densitySup[0]

        for i in 1..<lqd.count {
            let left = exp(lqd[i - 1])
            let right = exp(lqd[i])
            quantile[i] = quantile[i - 1] + 0.5 * (left + right) * (lqdSup[i] - lqdSup[i - 1])
        }

        let qMin = quantile[0]
        let qMax = quantile[quantile.count - 1]
        let qRange = qMax - qMin
        let supportRange = densitySup[densitySup.count - 1] - densitySup[0]
        return quantile.map { (($0 - qMin) * supportRange) / qRange + densitySup[0] }
    }

    func lqdToDensity(lqd: [Double], quantile: [Double]) -> [Double] {
        let densitySup = data.supports.density
        let densityTemp = lqd.map { exp(-$0) }
        var density = interpolate(x: quantile, y: densityTemp, xNew: densitySup).map { max($0, 1e-12) }
        let integral = trapz(y: density, x: densitySup)
        density = density.map { $0 / integral }
        return density
    }

    func quantileToDensity(_ quantile: [Double]) -> [Double] {
        let lqdSup = data.supports.lqd
        let densitySup = data.supports.density
        var densityAtQuantile = Array(repeating: 0.0, count: quantile.count)

        for i in quantile.indices {
            let derivative: Double
            if i == 0 {
                derivative = (quantile[1] - quantile[0]) / (lqdSup[1] - lqdSup[0])
            } else if i == quantile.count - 1 {
                derivative = (quantile[i] - quantile[i - 1]) / (lqdSup[i] - lqdSup[i - 1])
            } else {
                derivative = (quantile[i + 1] - quantile[i - 1]) / (lqdSup[i + 1] - lqdSup[i - 1])
            }
            densityAtQuantile[i] = 1 / max(derivative, 1e-12)
        }

        var density = interpolate(x: quantile, y: densityAtQuantile, xNew: densitySup).map { max($0, 1e-12) }
        let integral = trapz(y: density, x: densitySup)
        density = density.map { $0 / integral }
        return density
    }

    func subgroupReference(result: StateInfo, subgroup: SubgroupProfile) -> Reference {
        var random = SeededRandom(seed: hashString(subgroup.key))
        var quantiles: [[Double]] = []
        quantiles.reserveCapacity(data.subgroupReferenceSampleCount)

        for _ in 0..<data.subgroupReferenceSampleCount {
            let glucose = sampleGlucose(in: subgroup.glucose, random: &random)
            let bmi = sampleBmi(in: subgroup.bmi, random: &random)
            let bp = sampleBp(in: subgroup.bp, random: &random)
            let age = sampleAge(in: subgroup.age, random: &random)
            let state = [
                standardize(glucose, variableName: "GLU"),
                standardize(bmi, variableName: "BMI"),
                standardize(bp.dbp, variableName: "DBP"),
                standardize(bp.sbp, variableName: "SBP"),
                standardize(age, variableName: "age_att"),
                data.sexMapping[subgroup.sex.rawValue] ?? 0,
                result.glucoseImputed ? 1.0 : 0.0,
            ]
            quantiles.append(lqdToQuantile(policyLqd(from: state)))
        }

        let averageQuantile = averageArrays(quantiles)
        return Reference(density: quantileToDensity(averageQuantile), quantile: averageQuantile)
    }

    func averageArrays(_ arrays: [[Double]]) -> [Double] {
        var output = Array(repeating: 0.0, count: arrays[0].count)
        for array in arrays {
            for index in array.indices {
                output[index] += array[index]
            }
        }
        return output.map { $0 / Double(arrays.count) }
    }

    func profileSubgroup(glucoseRaw: Double, age: Double, bmi: Double, sbp: Double, dbp: Double, sex: SexAtBirth, glucoseImputed: Bool) -> SubgroupProfile {
        SubgroupProfile(
            glucose: glucoseGroup(glucoseRaw),
            age: ageGroup(age),
            bmi: bmiGroup(bmi),
            bp: bpLevel(sbp: sbp, dbp: dbp),
            sex: sex,
            glucoseImputed: glucoseImputed
        )
    }

    func glucoseGroup(_ glucose: Double) -> SubgroupProfile.Bucket {
        if glucose > 150 { return .init(code: 2, label: "High glucose", rangeLabel: "G > 150") }
        if (glucose >= 120 && glucose <= 150) || (glucose >= 70 && glucose <= 80) {
            return .init(code: 1, label: "Borderline glucose", rangeLabel: "70 <= G <= 80 or 120 <= G <= 150")
        }
        if glucose < 70 { return .init(code: 3, label: "Low glucose", rangeLabel: "G < 70") }
        if glucose > 80 && glucose < 120 { return .init(code: 0, label: "Normal glucose", rangeLabel: "80 < G < 120") }
        return .init(code: -1, label: "Undefined glucose", rangeLabel: "undefined")
    }

    func ageGroup(_ age: Double) -> SubgroupProfile.Bucket {
        if age < 40 { return .init(code: 0, label: "Younger age", rangeLabel: "Age < 40") }
        if age >= 40 && age < 60 { return .init(code: 1, label: "Middle age", rangeLabel: "40 <= Age < 60") }
        return .init(code: 2, label: "Older age", rangeLabel: "Age >= 60")
    }

    func bmiGroup(_ bmi: Double) -> SubgroupProfile.Bucket {
        if bmi < 18.5 { return .init(code: 1, label: "Underweight BMI", rangeLabel: "BMI < 18.5") }
        if bmi >= 18.5 && bmi < 25 { return .init(code: 0, label: "Normal BMI", rangeLabel: "18.5 <= BMI < 25") }
        if bmi >= 25 && bmi < 30 { return .init(code: 2, label: "Overweight BMI", rangeLabel: "25 <= BMI < 30") }
        return .init(code: 3, label: "Obese BMI", rangeLabel: "BMI >= 30")
    }

    func bpLevel(sbp: Double, dbp: Double) -> SubgroupProfile.Bucket {
        if sbp >= 130 || dbp >= 80 {
            return .init(code: 2, label: "Hypertension blood pressure", rangeLabel: "SBP >= 130 or DBP >= 80")
        }
        if sbp >= 120 && sbp < 130 && dbp < 80 {
            return .init(code: 1, label: "Elevated blood pressure", rangeLabel: "120 <= SBP < 130 and DBP < 80")
        }
        return .init(code: 0, label: "Normal blood pressure", rangeLabel: "SBP < 120 and DBP < 80")
    }

    func sampleGlucose(in group: SubgroupProfile.Bucket, random: inout SeededRandom) -> Double {
        if group.code == 0 { return uniform(random: &random, min: 80 + 1e-9, max: 120 - 1e-9) }
        if group.code == 1 {
            return random.next() < 0.25
                ? uniform(random: &random, min: 70, max: 80 + 1e-9)
                : uniform(random: &random, min: 120, max: 150 + 1e-9)
        }
        if group.code == 2 { return uniform(random: &random, min: 150 + 1e-9, max: data.glucoseBounds.max) }
        if group.code == 3 { return uniform(random: &random, min: data.glucoseBounds.min, max: 70) }
        return uniform(random: &random, min: data.glucoseBounds.min, max: data.glucoseBounds.max)
    }

    func sampleAge(in group: SubgroupProfile.Bucket, random: inout SeededRandom) -> Double {
        if group.code == 0 { return uniform(random: &random, min: 19.44, max: 40) }
        if group.code == 1 { return uniform(random: &random, min: 40, max: 60) }
        return uniform(random: &random, min: 60, max: 83.77)
    }

    func sampleBmi(in group: SubgroupProfile.Bucket, random: inout SeededRandom) -> Double {
        if group.code == 1 { return uniform(random: &random, min: 16, max: 18.5) }
        if group.code == 0 { return uniform(random: &random, min: 18.5, max: 25) }
        if group.code == 2 { return uniform(random: &random, min: 25, max: 30) }
        return uniform(random: &random, min: 30, max: 52.22)
    }

    func sampleBp(in group: SubgroupProfile.Bucket, random: inout SeededRandom) -> (sbp: Double, dbp: Double) {
        if group.code == 0 {
            return (uniform(random: &random, min: 81, max: 120), uniform(random: &random, min: 40, max: 80))
        }
        if group.code == 1 {
            return (uniform(random: &random, min: 120, max: 130), uniform(random: &random, min: 40, max: 80))
        }
        for _ in 0..<10_000 {
            let sbp = uniform(random: &random, min: 81, max: 180)
            let dbp = uniform(random: &random, min: 40, max: 117.98)
            if sbp >= 130 || dbp >= 80 { return (sbp, dbp) }
        }
        return (uniform(random: &random, min: 130, max: 180), uniform(random: &random, min: 80, max: 117.98))
    }

    func uniform(random: inout SeededRandom, min: Double, max: Double) -> Double {
        min + random.next() * (max - min)
    }

    func densityPeaks(_ density: [Double], maxPeaks: Int = 3) -> [DensityPeak] {
        let densitySup = data.supports.density
        let maxDensity = density.max() ?? 0
        let globalIndex = density.firstIndex(of: maxDensity) ?? 0
        var candidates: [Int] = []

        if density.count < 3 {
            return [DensityPeak(index: globalIndex, step: densitySup[globalIndex], density: maxDensity, prominence: peakProminence(density, index: globalIndex))]
        }

        if density[0] > density[1] { candidates.append(0) }
        for i in 1..<(density.count - 1) {
            let isPeak =
                (density[i] >= density[i - 1] && density[i] > density[i + 1]) ||
                (density[i] > density[i - 1] && density[i] >= density[i + 1])
            if isPeak { candidates.append(i) }
        }
        if density[density.count - 1] > density[density.count - 2] {
            candidates.append(density.count - 1)
        }

        var filtered = candidates
            .map { index in
                DensityPeak(index: index, step: densitySup[index], density: density[index], prominence: peakProminence(density, index: index))
            }
            .filter { $0.density >= maxDensity * 0.12 && $0.prominence >= maxDensity * 0.03 }
            .sorted { $0.density > $1.density }

        if !filtered.contains(where: { $0.index == globalIndex }) {
            filtered.insert(
                DensityPeak(index: globalIndex, step: densitySup[globalIndex], density: maxDensity, prominence: peakProminence(density, index: globalIndex)),
                at: 0
            )
        }

        var selected: [DensityPeak] = []
        for peak in filtered {
            let farEnough = selected.allSatisfy { abs($0.step - peak.step) >= 1000 }
            if farEnough { selected.append(peak) }
            if selected.count >= maxPeaks { break }
        }
        return selected.sorted { $0.step < $1.step }
    }

    func peakProminence(_ density: [Double], index: Int) -> Double {
        let height = density[index]
        var leftMin = height
        var rightMin = height

        for i in stride(from: index, through: 0, by: -1) {
            leftMin = min(leftMin, density[i])
            if i < index && density[i] > height { break }
        }
        for i in index..<density.count {
            rightMin = min(rightMin, density[i])
            if i > index && density[i] > height { break }
        }
        return height - max(leftMin, rightMin)
    }

    func formatStepList(_ values: [Double]) -> String {
        let formatted = values.map { "approximately \(formatHundred($0))" }
        if formatted.count == 1 { return formatted[0] }
        if formatted.count == 2 { return "\(formatted[0]) and \(formatted[1])" }
        return "\(formatted.dropLast().joined(separator: ", ")), and \(formatted[formatted.count - 1])"
    }

    func roundToHundred(_ value: Double) -> Double {
        (value / 100).rounded() * 100
    }

    func formatHundred(_ value: Double) -> String {
        formatInteger(roundToHundred(value))
    }

    func formatInteger(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }

    func interpolate(x: [Double], y: [Double], xNew: [Double]) -> [Double] {
        var out = Array(repeating: 0.0, count: xNew.count)
        var j = 0
        for i in xNew.indices {
            let xp = xNew[i]
            while j < x.count - 2 && x[j + 1] < xp {
                j += 1
            }
            if xp <= x[0] {
                out[i] = y[0]
            } else if xp >= x[x.count - 1] {
                out[i] = y[y.count - 1]
            } else {
                let denom = x[j + 1] - x[j]
                let t = denom == 0 ? 0 : (xp - x[j]) / denom
                out[i] = y[j] + t * (y[j + 1] - y[j])
            }
        }
        return out
    }

    func trapz(y: [Double], x: [Double]) -> Double {
        var total = 0.0
        for i in 1..<y.count {
            total += 0.5 * (y[i - 1] + y[i]) * (x[i] - x[i - 1])
        }
        return total
    }

    func dot(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
    }

    func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    func hashString(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for scalar in text.unicodeScalars {
            hash ^= UInt32(scalar.value)
            hash = hash &* 16_777_619
        }
        return hash
    }
}

private struct SeededRandom {
    private var value: UInt32

    init(seed: UInt32) {
        value = seed
    }

    mutating func next() -> Double {
        value = value &+ 0x6D2B79F5
        var t = value
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        let output = t ^ (t >> 14)
        return Double(output) / 4_294_967_296.0
    }
}
