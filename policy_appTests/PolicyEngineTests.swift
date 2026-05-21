import Foundation
import Testing
@testable import policy_app

private final class BundleToken {}

struct PolicyEngineTests {
    @Test func swiftEngineMatchesHTMLGoldenFixtures() throws {
        let engine = try PolicyEngine(data: PolicyModelData.load())
        let fixtures = try GoldenFixtures.load()

        for fixture in fixtures.profiles {
            let result = try engine.evaluate(profile: fixture.patientProfile)

            expectArray(result.lqd, fixture.lqd, tolerance: 1e-6, label: "\(fixture.id) lqd")
            expectArray(result.quantile, fixture.quantile, tolerance: 1e-6, label: "\(fixture.id) quantile")
            expectArray(result.density, fixture.density, tolerance: 1e-6, label: "\(fixture.id) density")
            expectArray(result.referenceQuantile, fixture.referenceQuantile, tolerance: 1e-6, label: "\(fixture.id) reference quantile")
            expectArray(result.referenceDensity, fixture.referenceDensity, tolerance: 1e-6, label: "\(fixture.id) reference density")
            expectArray(result.state, fixture.state, tolerance: 1e-10, label: "\(fixture.id) state")

            #expect(abs(result.glucoseRaw - fixture.glucoseRaw) <= 1e-10)
            #expect(result.glucoseImputed == (fixture.glucoseImputed == 1))
            #expect(result.subgroup.key == fixture.subgroupKey)
            #expect(result.subgroup.label == fixture.subgroupLabel)
            #expect(abs(result.meanSteps - fixture.meanSteps) <= 1e-6)
            #expect(abs(result.meanDensity - fixture.meanDensity) <= 1e-10)
            #expect(abs(result.q33 - fixture.q33) <= 1e-6)
            #expect(abs(result.q67 - fixture.q67) <= 1e-6)
            #expect(result.meanRounded == fixture.meanRounded)
            #expect(result.peakCardText == fixture.peakCardText)
            #expect(result.q33Rounded == fixture.q33Rounded)
            #expect(result.q67Rounded == fixture.q67Rounded)
            #expect(result.peaks.count == fixture.peaks.count)

            for (actual, expected) in zip(result.peaks, fixture.peaks) {
                #expect(actual.index == expected.index)
                #expect(abs(actual.step - expected.step) <= 1e-10)
                #expect(abs(actual.density - expected.density) <= 1e-10)
                #expect(abs(actual.prominence - expected.prominence) <= 1e-10)
            }
        }
    }

    @Test func profileFormValidationMatchesRequiredFieldBehavior() throws {
        let data = try PolicyModelData.load()
        var form = ProfileFormState(example: data.exampleRaw)
        form.bmi = ""

        do {
            _ = try form.validatedProfile()
            Issue.record("Expected BMI validation to fail.")
        } catch let error as PolicyError {
            #expect(error == .missingRequiredField("bmi"))
        }

        form.bmi = "not-a-number"
        do {
            _ = try form.validatedProfile()
            Issue.record("Expected BMI numeric validation to fail.")
        } catch let error as PolicyError {
            #expect(error == .invalidNumericInput("bmi"))
        }
    }
}

private func expectArray(_ actual: [Double], _ expected: [Double], tolerance: Double, label: String) {
    #expect(actual.count == expected.count, "\(label) count")
    for index in 0..<min(actual.count, expected.count) {
        let delta = abs(actual[index] - expected[index])
        #expect(delta <= tolerance, "\(label)[\(index)] delta \(delta)")
    }
}

private struct GoldenFixtures: Decodable {
    let profiles: [GoldenProfile]

    static func load() throws -> GoldenFixtures {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: "PolicyGoldenFixtures", withExtension: "json") else {
            throw PolicyError.missingModelData
        }
        return try JSONDecoder().decode(GoldenFixtures.self, from: Data(contentsOf: url))
    }
}

private struct GoldenProfile: Decodable {
    let id: String
    let lqd: [Double]
    let quantile: [Double]
    let density: [Double]
    let glucoseRaw: Double
    let glucoseImputed: Int
    let state: [Double]
    let subgroupKey: String
    let subgroupLabel: String
    let referenceDensity: [Double]
    let referenceQuantile: [Double]
    let peaks: [DensityPeak]
    let meanSteps: Double
    let meanDensity: Double
    let q33: Double
    let q67: Double
    let meanRounded: String
    let peakCardText: String
    let q33Rounded: String
    let q67Rounded: String

    var patientProfile: PatientProfile {
        switch id {
        case "default_example":
            PatientProfile(glucose: nil, bmi: 29.21, dbp: 74.59, sbp: 123.87, age: 55.46, sex: .female)
        case "normal_measured":
            PatientProfile(glucose: 100, bmi: 24, dbp: 70, sbp: 115, age: 35, sex: .female)
        case "high_risk_male":
            PatientProfile(glucose: 160, bmi: 32, dbp: 85, sbp: 140, age: 67, sex: .male)
        case "low_glucose_elevated_bp":
            PatientProfile(glucose: 65, bmi: 18.2, dbp: 76, sbp: 125, age: 45, sex: .male)
        default:
            fatalError("Unknown golden fixture id: \(id)")
        }
    }
}
