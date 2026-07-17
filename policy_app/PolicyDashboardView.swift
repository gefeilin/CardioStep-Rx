import Charts
import SwiftUI

enum PolicyChartMode: String, CaseIterable, Identifiable {
    case density = "Density function"
    case quantile = "Quantile function"

    var id: String { rawValue }
}

private enum MobileDashboardTab: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case chart = "Chart"
    case track = "Track"
    case insight = "About"
    case profile = "Profile"

    var id: String { rawValue }

    var analyticsViewName: String {
        switch self {
        case .plan:
            return "plan"
        case .chart:
            return "chart"
        case .track:
            return "track"
        case .insight:
            return "about"
        case .profile:
            return "profile"
        }
    }

    var analyticsEventName: String? {
        switch self {
        case .plan:
            return "view_plan"
        case .chart:
            return "view_chart"
        case .track:
            return "view_track"
        case .insight:
            return "view_insight"
        case .profile:
            return nil
        }
    }

    var systemImage: String {
        switch self {
        case .plan:
            return "target"
        case .chart:
            return "chart.xyaxis.line"
        case .track:
            return "heart.text.square"
        case .insight:
            return "info.circle"
        case .profile:
            return "slider.horizontal.3"
        }
    }
}

struct PolicyDashboardView: View {
    let engine: PolicyEngine

    @State private var form: ProfileFormState
    @State private var result: PolicyResult
    @State private var chartMode: PolicyChartMode = .density
    @State private var isShowingProfileEditor = false
    @State private var profileEditorDetent: PresentationDetent = .height(680)
    @State private var isInsightExpanded = false
    @State private var selectedDensityStep: Double?
    @State private var selectedQuantileLevel: Double?
    @StateObject private var stepTracker = HealthStepTracker()
    @State private var activeMobileTab: MobileDashboardTab = .plan
    @State private var lastContentMobileTab: MobileDashboardTab = .plan
    @State private var didTrackInitialView = false

    init(engine: PolicyEngine) {
        self.engine = engine
        let initialForm = ProfileFormState(example: engine.data.exampleRaw)
        _form = State(initialValue: initialForm)
        do {
            _result = State(initialValue: try engine.evaluate(profile: initialForm.validatedProfile()))
        } catch {
            let fallback = PatientProfile(glucose: 100, bmi: 24, dbp: 70, sbp: 115, age: 50, sex: .female)
            _result = State(initialValue: try! engine.evaluate(profile: fallback))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 820
            Group {
                if isWide {
                    ScrollView {
                        wideContent(proxy: proxy)
                    }
                } else {
                    ScrollView {
                        mobileContent()
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 104)
                    }
                    .safeAreaInset(edge: .bottom) {
                        MobileDashboardTabBar(selection: isShowingProfileEditor ? .profile : activeMobileTab) { tab in
                            selectMobileTab(tab)
                        }
                    }
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .overlay(alignment: .top) {
                AppTheme.background
                    .frame(height: proxy.safeAreaInsets.top + 6)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .sheet(isPresented: $isShowingProfileEditor, onDismiss: handleProfileDismiss) {
                NavigationStack {
                    ScrollView {
                        profilePanel(isEmbedded: false)
                            .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .navigationTitle("Edit Profile")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                isShowingProfileEditor = false
                            }
                        }
                    }
                }
                .presentationDetents([.height(680), .large], selection: $profileEditorDetent)
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                guard !didTrackInitialView else { return }
                didTrackInitialView = true
                AnalyticsClient.shared.track(
                    "view_plan",
                    properties: [
                        "view": "plan",
                        "source": "initial"
                    ]
                )
            }
        }
    }

    private func wideContent(proxy: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 16) {
            profileCard(isEmbedded: true)
                .frame(width: min(360, proxy.size.width * 0.36))
            resultsColumn(isWide: true)
        }
        .padding(18)
    }

    @ViewBuilder
    private func mobileContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(isWide: false)

            switch activeMobileTab {
            case .plan:
                MainStepGoalCard(result: result)
                TodayPlanningGuideCard(guide: stepTracker.todayPlanningGuide(for: result))
                FlexibleRangeSection(result: result)
                MissedDayCard()
                SafetyDisclaimerView()
            case .chart:
                ChartPanel(
                    engine: engine,
                    result: result,
                    mode: $chartMode,
                    selectedDensityStep: $selectedDensityStep,
                    selectedQuantileLevel: $selectedQuantileLevel
                )
            case .track:
                HealthTrackerPanel(engine: engine, result: result, tracker: stepTracker)
            case .insight:
                FeedbackContactCard()
                CitationCard()
                WhyThisPlanAboutCard(result: result)
                ResearchModelCard()
                InsightPanel(result: result, isExpanded: $isInsightExpanded)
                SubgroupPanel(result: result)
                SafetyDisclaimerView()
            case .profile:
                EmptyView()
            }
        }
    }

    private func selectMobileTab(_ tab: MobileDashboardTab) {
        if tab == .profile {
            openProfileEditor(source: "mobile_tab")
            return
        }

        activeMobileTab = tab
        lastContentMobileTab = tab
        if let eventName = tab.analyticsEventName {
            AnalyticsClient.shared.track(
                eventName,
                properties: [
                    "view": tab.analyticsViewName,
                    "source": "mobile_tab"
                ]
            )
        }
        if isShowingProfileEditor {
            isShowingProfileEditor = false
        }
    }

    private func openProfileEditor(source: String = "dashboard") {
        profileEditorDetent = .height(680)
        isShowingProfileEditor = true
        AnalyticsClient.shared.track("open_profile", properties: ["source": source])
    }

    private func handleProfileDismiss() {
        if activeMobileTab == .profile {
            activeMobileTab = lastContentMobileTab
        }
    }

    private func resultsColumn(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(isWide: isWide)
            MainStepGoalCard(result: result)
            TodayPlanningGuideCard(guide: stepTracker.todayPlanningGuide(for: result))
            FlexibleRangeSection(result: result)
            MissedDayCard()
            HealthTrackerPanel(engine: engine, result: result, tracker: stepTracker)
            ChartPanel(
                engine: engine,
                result: result,
                mode: $chartMode,
                selectedDensityStep: $selectedDensityStep,
                selectedQuantileLevel: $selectedQuantileLevel
            )
            FeedbackContactCard()
            CitationCard()
            WhyThisPlanAboutCard(result: result)
            ResearchModelCard()
            InsightPanel(result: result, isExpanded: $isInsightExpanded)
            SubgroupPanel(result: result)
            SafetyDisclaimerView()
        }
        .frame(maxWidth: isWide ? .infinity : nil, alignment: .topLeading)
    }

    private func header(isWide: Bool, showsBrand: Bool = true) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if showsBrand {
                    Text("CardioStepRx")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.green)
                        .lineLimit(1)
                }
                Text("Your 90-day Precision Physical Activity Prescription")
                    .font(.system(size: isWide ? 30 : 25, weight: .bold, design: .default))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier("appTitle")
                Text("Personalized daily-step guidance to reduce cardiometabolic risk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func profileCard(isEmbedded: Bool) -> some View {
        profilePanel(isEmbedded: isEmbedded)
            .cardStyle()
    }

    private func profilePanel(isEmbedded: Bool) -> some View {
        ProfileEditorPanel(
            engine: engine,
            form: $form,
            result: $result,
            dismissAfterGenerate: !isEmbedded,
            showsHeader: isEmbedded
        )
    }
}

private struct MobileDashboardTabBar: View {
    let selection: MobileDashboardTab
    let onSelect: (MobileDashboardTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MobileDashboardTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? AppTheme.green : AppTheme.reference)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(selection == tab ? AppTheme.green.opacity(0.10) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.white.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.line.opacity(0.65))
                .frame(height: 1)
        }
        .shadow(color: AppTheme.ink.opacity(0.08), radius: 30, x: 0, y: -12)
    }
}

private enum HeightUnit: String, CaseIterable, Identifiable {
    case centimeters = "cm"
    case feetInches = "ft/in"

    var id: String { rawValue }
}

private enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms = "kg"
    case pounds = "lbs"

    var id: String { rawValue }
}

private struct ProfileFormState: Equatable {
    private static let defaultHeightCm = 170.0
    private static let poundsPerKilogram = 2.2046226218

    var glucose: String
    var heightUnit: HeightUnit
    var heightCentimeters: String
    var heightFeet: Int
    var heightInches: Int
    var weightUnit: WeightUnit
    var weightKilograms: String
    var weightPounds: String
    var dbp: String
    var sbp: String
    var age: String
    var sex: SexAtBirth

    init(example: PolicyModelData.ExampleRaw) {
        let heightCm = Self.defaultHeightCm
        let weightKg = (example.bmi * pow(heightCm / 100.0, 2)).rounded()
        let totalInches = Int((heightCm / 2.54).rounded())

        glucose = example.glucose
        heightUnit = .centimeters
        heightCentimeters = Self.formatInput(heightCm)
        heightFeet = max(3, min(8, totalInches / 12))
        heightInches = max(0, min(11, totalInches % 12))
        weightUnit = .kilograms
        weightKilograms = Self.formatInput(weightKg)
        weightPounds = Self.formatInput((weightKg * Self.poundsPerKilogram).rounded())
        dbp = Self.formatInput(example.dbp)
        sbp = Self.formatInput(example.sbp)
        age = Self.formatInput(example.age)
        sex = SexAtBirth(rawValue: example.sex) ?? .female
    }

    func validatedProfile() throws -> PatientProfile {
        let dbpValue = try requiredNonNegativeNumber(dbp, field: "DBP")
        let sbpValue = try requiredNonNegativeNumber(sbp, field: "SBP")
        guard dbpValue <= sbpValue else {
            throw PolicyError.diastolicGreaterThanSystolic
        }

        return PatientProfile(
            glucose: try optionalNonNegativeNumber(glucose, field: "Glucose"),
            bmi: try calculatedBMI(),
            dbp: dbpValue,
            sbp: sbpValue,
            age: try requiredNonNegativeNumber(age, field: "Age"),
            sex: sex
        )
    }

    mutating func convertHeight(from oldUnit: HeightUnit, to newUnit: HeightUnit) {
        guard oldUnit != newUnit, let heightCm = heightCentimetersValue(using: oldUnit) else { return }
        setHeightCentimetersValue(heightCm, for: newUnit)
    }

    mutating func convertWeight(from oldUnit: WeightUnit, to newUnit: WeightUnit) {
        guard oldUnit != newUnit, let weightKg = weightKilogramsValue(using: oldUnit) else { return }
        setWeightKilogramsValue(weightKg, for: newUnit)
    }

    static func formatInput(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func calculatedBMI() throws -> Double {
        let heightCm = try requiredHeightCentimeters()
        let weightKg = try requiredWeightKilograms()
        let heightMeters = heightCm / 100.0
        return weightKg / pow(heightMeters, 2)
    }

    private func requiredHeightCentimeters() throws -> Double {
        guard let heightCm = heightCentimetersValue(using: heightUnit), heightCm > 0 else {
            throw PolicyError.positiveNumericInput("Height")
        }
        return heightCm
    }

    private func requiredWeightKilograms() throws -> Double {
        guard let weightKg = weightKilogramsValue(using: weightUnit), weightKg > 0 else {
            throw PolicyError.positiveNumericInput("Weight")
        }
        return weightKg
    }

    private func heightCentimetersValue(using unit: HeightUnit) -> Double? {
        switch unit {
        case .centimeters:
            return try? requiredNumber(heightCentimeters, field: "Height")
        case .feetInches:
            let totalInches = Double(heightFeet * 12 + heightInches)
            return totalInches > 0 ? totalInches * 2.54 : nil
        }
    }

    private mutating func setHeightCentimetersValue(_ value: Double, for unit: HeightUnit) {
        switch unit {
        case .centimeters:
            heightCentimeters = Self.formatInput(value)
        case .feetInches:
            let totalInches = max(36, min(96, Int((value / 2.54).rounded())))
            heightFeet = totalInches / 12
            heightInches = totalInches % 12
        }
    }

    private func weightKilogramsValue(using unit: WeightUnit) -> Double? {
        switch unit {
        case .kilograms:
            return try? requiredNumber(weightKilograms, field: "Weight")
        case .pounds:
            guard let pounds = try? requiredNumber(weightPounds, field: "Weight") else { return nil }
            return pounds / Self.poundsPerKilogram
        }
    }

    private mutating func setWeightKilogramsValue(_ value: Double, for unit: WeightUnit) {
        switch unit {
        case .kilograms:
            weightKilograms = Self.formatInput(value)
        case .pounds:
            weightPounds = Self.formatInput(value * Self.poundsPerKilogram)
        }
    }

    private func optionalNumber(_ raw: String, field: String) throws -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed), value.isFinite else {
            throw PolicyError.invalidNumericInput(field)
        }
        return value
    }

    private func requiredNumber(_ raw: String, field: String) throws -> Double {
        guard let value = try optionalNumber(raw, field: field) else {
            throw PolicyError.missingRequiredField(field)
        }
        return value
    }

    private func optionalNonNegativeNumber(_ raw: String, field: String) throws -> Double? {
        guard let value = try optionalNumber(raw, field: field) else { return nil }
        guard value >= 0 else {
            throw PolicyError.negativeNumericInput(field)
        }
        return value
    }

    private func requiredNonNegativeNumber(_ raw: String, field: String) throws -> Double {
        let value = try requiredNumber(raw, field: field)
        guard value >= 0 else {
            throw PolicyError.negativeNumericInput(field)
        }
        return value
    }
}

private struct ProfileEditorPanel: View {
    let engine: PolicyEngine
    @Binding var form: ProfileFormState
    @Binding var result: PolicyResult
    let dismissAfterGenerate: Bool
    let showsHeader: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profile")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Edit inputs, then regenerate the recommendation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ProfileSection(title: "Metabolic") {
                PolicyTextField(
                    title: "Glucose",
                    text: $form.glucose,
                    placeholder: "Impute",
                    helper: "Fasting preferred, mg/dL"
                )
                HeightInput(form: $form)
                WeightInput(form: $form)
            }

            ProfileSection(title: "Blood Pressure") {
                PolicyTextField(
                    title: "DBP",
                    text: $form.dbp,
                    helper: "Bottom number, mmHg"
                )
                PolicyTextField(
                    title: "SBP",
                    text: $form.sbp,
                    helper: "Top number, mmHg"
                )
            }

            ProfileSection(title: "Demographics") {
                PolicyTextField(
                    title: "Age",
                    text: $form.age,
                    helper: "Years"
                )
                VStack(alignment: .leading, spacing: 7) {
                    Text("Sex at birth")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 28, alignment: .leading)
                    Picker("Sex at birth", selection: $form.sex) {
                        ForEach(SexAtBirth.allCases) { sex in
                            Text(sex.rawValue).tag(sex)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Years")
                        .font(.caption2)
                        .hidden()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button {
                    reset()
                } label: {
                    Label("Reset example", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("resetExampleButton")

                Button {
                    generate(source: "profile_editor")
                } label: {
                    Label("Generate Plan", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.green)
                .accessibilityIdentifier("generatePolicyButton")
                .accessibilityLabel("Generate 90-day plan")
            }
        }
        .onChange(of: form.heightUnit) { oldUnit, newUnit in
            form.convertHeight(from: oldUnit, to: newUnit)
        }
        .onChange(of: form.weightUnit) { oldUnit, newUnit in
            form.convertWeight(from: oldUnit, to: newUnit)
        }
    }

    private func generate(source: String) {
        do {
            result = try engine.evaluate(profile: form.validatedProfile())
            errorMessage = nil
            AnalyticsClient.shared.track("generate_plan", properties: ["source": source])
            if dismissAfterGenerate {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        form = ProfileFormState(example: engine.data.exampleRaw)
        AnalyticsClient.shared.track("reset_profile", properties: ["source": "profile_editor"])
        generate(source: "reset_example")
    }
}

private struct HeightInput: View {
    @Binding var form: ProfileFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabelWithUnit(title: "Height") {
                CompactUnitPicker(
                    selection: $form.heightUnit,
                    values: HeightUnit.allCases,
                    width: 112
                ) { unit in
                    unit.rawValue
                }
            }

            if form.heightUnit == .centimeters {
                TextField("170", text: $form.heightCentimeters)
                    .profileNumberField()
            } else {
                HStack(spacing: 8) {
                    InlineMenuPicker(title: "Feet", selection: $form.heightFeet, values: Array(3...8)) { value in
                        "\(value) ft"
                    }
                    InlineMenuPicker(title: "Inches", selection: $form.heightInches, values: Array(0...11)) { value in
                        "\(value) in"
                    }
                }
            }

            Text("Body height, cm or ft/in")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct WeightInput: View {
    @Binding var form: ProfileFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FieldLabelWithUnit(title: "Weight") {
                CompactUnitPicker(
                    selection: $form.weightUnit,
                    values: WeightUnit.allCases,
                    width: 102
                ) { unit in
                    unit.rawValue
                }
            }

            TextField(form.weightUnit == .kilograms ? "69" : "152", text: activeWeightBinding)
                .profileNumberField()

            Text("Body weight, kg or lbs")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var activeWeightBinding: Binding<String> {
        switch form.weightUnit {
        case .kilograms:
            return $form.weightKilograms
        case .pounds:
            return $form.weightPounds
        }
    }
}

private struct FieldLabelWithUnit<UnitContent: View>: View {
    let title: String
    @ViewBuilder let unit: UnitContent

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            unit
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}

private struct CompactUnitPicker<SelectionValue: Hashable>: View {
    @Binding var selection: SelectionValue
    let values: [SelectionValue]
    let width: CGFloat
    let label: (SelectionValue) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(values, id: \.self) { value in
                Text(label(value)).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: width, height: 28)
    }
}

private struct InlineMenuPicker<SelectionValue: Hashable>: View {
    let title: String
    @Binding var selection: SelectionValue
    let values: [SelectionValue]
    let label: (SelectionValue) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(values, id: \.self) { value in
                Text(label(value)).tag(value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(AppTheme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.line)
        )
        .accessibilityLabel(title)
    }
}

private struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.green)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                content
            }
        }
    }
}

private struct PolicyTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var helper: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(height: 28, alignment: .leading)
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 11)
                .frame(height: 42)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.line)
                )
            if let helper {
                Text(helper)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private enum HelpTopic: String, Identifiable {
    case averageDailySteps
    case mostFrequentLevel
    case lowActivityDay
    case highActivityDay
    case walkingPlan
    case primaryStepGoal
    case glucoseImputed
    case glucoseMeasured
    case densityFunction
    case quantileFunction
    case subgroupAverage
    case healthTracker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .averageDailySteps:
            return "90-day average"
        case .mostFrequentLevel:
            return "Most frequent level"
        case .lowActivityDay:
            return "Low-activity day"
        case .highActivityDay:
            return "High-activity day"
        case .walkingPlan:
            return "90-day walking plan"
        case .primaryStepGoal:
            return "Primary step goal"
        case .glucoseImputed:
            return "Glucose imputed"
        case .glucoseMeasured:
            return "Glucose"
        case .densityFunction:
            return "Density function"
        case .quantileFunction:
            return "Quantile function"
        case .subgroupAverage:
            return "Similar profiles"
        case .healthTracker:
            return "Health step tracker"
        }
    }

    var message: String {
        switch self {
        case .averageDailySteps:
            return "The recommended average number of steps per day across the next 90 days."
        case .mostFrequentLevel:
            return "The step count that appears most often in the recommended 90-day distribution. It is not the maximum steps in one day."
        case .lowActivityDay:
            return "A lower-activity day in the flexible 90-day plan. It is based on the lower third of the recommended daily-step distribution."
        case .highActivityDay:
            return "A higher-activity day threshold in the flexible 90-day plan. It is based on the upper third of the recommended daily-step distribution."
        case .walkingPlan:
            return "A flexible translation of the model curves into step goals for about 60, 45, and 30 days across the next 90 days."
        case .primaryStepGoal:
            return "The main daily step goal comes from the most concentrated point of the recommended 90-day distribution. It is not a strict daily minimum."
        case .glucoseImputed:
            return "Glucose was left blank, so the app estimated it from height, weight, blood pressure, age, and sex for this research calculation."
        case .glucoseMeasured:
            return "The glucose value entered in the profile and used by the recommendation model."
        case .densityFunction:
            return "This advanced curve shows which daily step levels appear more often in the recommended 90-day plan. Taller parts mean more days near that step level."
        case .quantileFunction:
            return "This advanced curve shows the recommended daily-step value across quantile levels from 0 to 1."
        case .subgroupAverage:
            return "The gray curve summarizes recommendations for profiles with similar glucose, age, BMI, blood pressure, sex, and glucose-source group."
        case .healthTracker:
            return "The iOS app can request HealthKit permission to read Apple Health step counts for the selected 90-day cycle. The Plan match score starts after at least 7 days of data."
        }
    }
}

private struct HelpButton: View {
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What does this mean?")
    }
}

private struct SummaryGrid: View {
    let result: PolicyResult
    @State private var activeHelp: HelpTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                SummaryHeroMetric(
                    title: "90-day average",
                    value: "≈ \(result.meanRounded)",
                    systemImage: "calendar",
                    helpTopic: .averageDailySteps,
                    activeHelp: $activeHelp
                )
                Divider()
                    .frame(height: 54)
                    .overlay(.white.opacity(0.28))
                SummaryHeroMetric(
                    title: "Most frequent",
                    value: result.peakCardText,
                    systemImage: "chart.line.uptrend.xyaxis",
                    helpTopic: .mostFrequentLevel,
                    activeHelp: $activeHelp
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.primaryGradient)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                CompactMetricChip(
                    title: "Low day",
                    value: "≈ \(result.q33Rounded)",
                    systemImage: "arrow.down.left",
                    helpTopic: .lowActivityDay,
                    activeHelp: $activeHelp
                )
                CompactMetricChip(
                    title: "High day",
                    value: "≈ \(result.q67Rounded)",
                    systemImage: "arrow.up.right",
                    helpTopic: .highActivityDay,
                    activeHelp: $activeHelp
                )
                CompactMetricChip(
                    title: result.glucoseImputed ? "Glucose est." : "Glucose",
                    value: String(format: "%.1f", result.glucoseRaw),
                    unit: "mg/dL",
                    systemImage: "drop.fill",
                    helpTopic: result.glucoseImputed ? .glucoseImputed : .glucoseMeasured,
                    activeHelp: $activeHelp
                )
            }
        }
        .accessibilityIdentifier("summaryGrid")
        .alert(item: $activeHelp) { topic in
            Alert(
                title: Text(topic.title),
                message: Text(topic.message),
                dismissButton: .default(Text("Got it"))
            )
        }
    }
}

private struct SummaryHeroMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let helpTopic: HelpTopic
    @Binding var activeHelp: HelpTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HelpButton(color: .white.opacity(0.76)) {
                    activeHelp = helpTopic
                }
            }
            .foregroundStyle(.white.opacity(0.76))

            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactMetricChip: View {
    let title: String
    let value: String
    var unit: String?
    let systemImage: String
    let helpTopic: HelpTopic
    @Binding var activeHelp: HelpTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.green)
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HelpButton(color: AppTheme.green) {
                    activeHelp = helpTopic
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                if let unit {
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.line)
        )
    }
}

private struct MainStepGoalCard: View {
    let result: PolicyResult
    @State private var activeHelp: HelpTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your main goal")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("Aim for this average across the next 90 days.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HelpButton(color: .white.opacity(0.86)) {
                    activeHelp = .averageDailySteps
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("≈ \(result.meanRounded)")
                    .font(.system(size: 42, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("steps/day")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)

            Text("You do not need to hit the same number every day.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.primaryGradient)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Main goal. Aim for about \(result.meanRounded) steps per day on average across the next 90 days.")
        .alert(item: $activeHelp) { topic in
            Alert(
                title: Text(topic.title),
                message: Text(topic.message),
                dismissButton: .default(Text("Got it"))
            )
        }
    }
}

private struct TodayPlanningGuideCard: View {
    let guide: TodayPlanningGuide

    var body: some View {
        ActionInfoCard(
            icon: "figure.walk",
            title: "Today's planning guide",
            headline: "\(guide.title): \(guide.rangeText)",
            detail: guide.detail
        )
    }
}

private struct FlexibleRangeSection: View {
    let result: PolicyResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your flexible range")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Use these targets to vary lighter, regular, and more active days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                FlexibleRangeRow(
                    icon: "leaf",
                    title: "Easy-day goal",
                    steps: result.q33Rounded,
                    detail: "On about 60 days, aim for at least"
                )
                FlexibleRangeRow(
                    icon: "calendar",
                    title: "Regular-day goal",
                    steps: result.q50Rounded,
                    detail: "On about 45 days, aim for at least"
                )
                FlexibleRangeRow(
                    icon: "figure.walk.motion",
                    title: "Active-day goal",
                    steps: result.q67Rounded,
                    detail: "On about 30 days, aim for at least"
                )
            }
        }
        .cardStyle()
        .accessibilityIdentifier("flexibleRange")
    }
}

private struct FlexibleRangeRow: View {
    let icon: String
    let title: String
    let steps: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.green)
                .frame(width: 30, height: 30)
                .background(AppTheme.green.opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("≈ \(steps)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("steps")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(11)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct MissedDayCard: View {
    var body: some View {
        ActionInfoCard(
            icon: "heart",
            title: "If you miss only a few days",
            headline: "That is okay.",
            detail: "This is a flexible 90-day distribution of recommended steps, not a perfect same-step daily goal."
        )
    }
}

private struct WhyThisPlanAboutCard: View {
    let result: PolicyResult

    var body: some View {
        let glucoseSource = result.glucoseImputed ? "estimated glucose" : "measured glucose"

        ActionInfoCard(
            icon: "person.text.rectangle",
            title: "Why this plan?",
            headline: "Based on your health profile.",
            detail: "The recommendation uses age, sex, height, weight, blood pressure, and \(glucoseSource)."
        )
    }
}

private struct ResearchModelCard: View {
    var body: some View {
        ActionInfoCard(
            icon: "point.3.connected.trianglepath.dotted",
            title: "Research model",
            headline: "Offline reinforcement learning.",
            detail: "The model learns functional actions that represent a 90-day distribution of daily steps."
        )
    }
}

private struct FeedbackContactCard: View {
    @Environment(\.openURL) private var openURL

    private let feedbackURL = URL(string: "https://forms.gle/fMpVgWgoDKoRNXG76")!
    private let contactURL = URL(string: "mailto:cardiosteprx@gmail.com")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.green.opacity(0.10))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Feedback")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Help improve CardioStepRx.")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Tell us what was confusing, useful, or missing. Your comments help improve the research prototype.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                AnalyticsClient.shared.track("open_feedback_form", properties: ["source": "about_card"])
                openURL(feedbackURL)
            } label: {
                Label("Give feedback", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.green)
            .accessibilityHint("Opens a Google Form in your browser")

            VStack(spacing: 8) {
                FeedbackInfoRow(
                    icon: "person.2",
                    title: "Maintainers",
                    detail: "Gefei Lin and Xiaoke Zhang"
                )
                Button {
                    AnalyticsClient.shared.track("open_contact_email", properties: ["source": "about_card"])
                    openURL(contactURL)
                } label: {
                    FeedbackInfoRow(
                        icon: "envelope",
                        title: "Contact",
                        detail: "cardiosteprx@gmail.com"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens an email draft")
            }
        }
        .cardStyle()
        .accessibilityIdentifier("feedbackContactCard")
    }
}

private struct CitationCard: View {
    @Environment(\.openURL) private var openURL

    private let paperURL = URL(string: "https://arxiv.org/abs/2605.19208")!
    private static let bibTeX = """
    @misc{lin2026precisionphysicalactivityprescription,
      title={Precision Physical Activity Prescription via Reinforcement Learning for Functional Actions},
      author={Gefei Lin and Rui Miao and Jennifer Sacheck and Xiaoke Zhang},
      year={2026},
      eprint={2605.19208},
      archivePrefix={arXiv},
      primaryClass={stat.AP},
      url={https://arxiv.org/abs/2605.19208},
    }
    """

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.green)
                .frame(width: 34, height: 34)
                .background(AppTheme.green.opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Citation")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Precision Physical Activity Prescription via Reinforcement Learning for Functional Actions.")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Gefei Lin, Rui Miao, Jennifer Sacheck, and Xiaoke Zhang. arXiv:2605.19208, 2026.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    AnalyticsClient.shared.track("open_citation_paper", properties: ["source": "about_card"])
                    openURL(paperURL)
                } label: {
                    Label("View paper on arXiv", systemImage: "arrow.up.forward.square")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.green)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the arXiv paper in your browser")

                DisclosureGroup {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(Self.bibTeX)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    }
                } label: {
                    Text("BibTeX")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
        .accessibilityIdentifier("citationCard")
    }
}

private struct FeedbackInfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.green)
                .frame(width: 24, height: 24)
                .background(AppTheme.green.opacity(0.08))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SafetyDisclaimerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Research prototype only", systemImage: "exclamationmark.shield")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text("Not intended for clinical decision making.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Stop exercising and seek medical advice if you experience chest pain, dizziness, unusual shortness of breath, or severe discomfort.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

private struct ActionInfoCard: View {
    let icon: String
    let title: String
    let headline: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.green)
                .frame(width: 34, height: 34)
                .background(AppTheme.green.opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

private struct WalkingPlanPanel: View {
    let result: PolicyResult
    @State private var activeHelp: HelpTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your 90-day walking plan")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Use the primary step goal as your everyday anchor, while allowing easier and more active days across the 90 days.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HelpButton(color: AppTheme.green) {
                    activeHelp = .walkingPlan
                }
            }

            VStack(spacing: 10) {
                WalkingPlanRow(
                    title: "Primary step goal",
                    detail: "Aim for around \(result.primaryStepRounded) steps as your primary daily step goal.",
                    systemImage: "target",
                    isPrimary: true,
                    helpTopic: .primaryStepGoal,
                    activeHelp: $activeHelp
                )
                WalkingPlanRow(
                    title: "Usual days",
                    detail: "On about 60 days, aim for at least \(result.q33Rounded) steps.",
                    systemImage: "calendar",
                    activeHelp: $activeHelp
                )
                WalkingPlanRow(
                    title: "Middle days",
                    detail: "On about 45 days, aim for at least \(result.q50Rounded) steps.",
                    systemImage: "chart.line.uptrend.xyaxis",
                    activeHelp: $activeHelp
                )
                WalkingPlanRow(
                    title: "More active days",
                    detail: "On about 30 days, aim for at least \(result.q67Rounded) steps.",
                    systemImage: "figure.walk",
                    activeHelp: $activeHelp
                )
                WalkingPlanRow(
                    title: "Average rhythm",
                    detail: "Aim for an average of around \(result.meanRounded) steps per day across 90 days.",
                    systemImage: "waveform.path.ecg",
                    activeHelp: $activeHelp
                )
            }
        }
        .cardStyle()
        .accessibilityIdentifier("walkingPlan")
        .alert(item: $activeHelp) { topic in
            Alert(
                title: Text(topic.title),
                message: Text(topic.message),
                dismissButton: .default(Text("Got it"))
            )
        }
    }
}

private struct WalkingPlanRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var isPrimary = false
    var helpTopic: HelpTopic? = nil
    @Binding var activeHelp: HelpTopic?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(isPrimary ? .white : AppTheme.green)
                .frame(width: 28, height: 28)
                .background(isPrimary ? AppTheme.green : AppTheme.green.opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    if let helpTopic {
                        HelpButton(color: AppTheme.green) {
                            activeHelp = helpTopic
                        }
                    }
                }

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(isPrimary ? AppTheme.green.opacity(0.08) : AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct HealthTrackerPanel: View {
    let engine: PolicyEngine
    let result: PolicyResult
    @ObservedObject var tracker: HealthStepTracker
    @State private var activeHelp: HelpTopic?

    private var metrics: StepTrackerMetrics {
        tracker.metrics(for: result, engine: engine)
    }

    var body: some View {
        let trackerMetrics = metrics

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Health 90-day tracker")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer(minLength: 8)
                HelpButton(color: AppTheme.green) {
                    activeHelp = .healthTracker
                }
            }

            VStack(spacing: 10) {
                DatePicker(
                    "Cycle start date",
                    selection: $tracker.cycleStartDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .datePickerStyle(.compact)
                .padding(10)
                .background(AppTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(alignment: .center, spacing: 10) {
                    Button {
                        AnalyticsClient.shared.track(
                            tracker.hasRequestedHealthAccess ? "refresh_health" : "connect_health",
                            properties: ["source": "health_tracker"]
                        )
                        Task {
                            await tracker.connectAndLoad()
                        }
                    } label: {
                        Label(
                            tracker.hasRequestedHealthAccess ? "Refresh Health" : "Connect Health",
                            systemImage: "heart.text.square"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.green)
                    .disabled(isLoading)

                    if isLoading {
                        ProgressView()
                            .tint(AppTheme.green)
                    }
                }

                Text(tracker.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(statusColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            TrackerScoreCard(metrics: trackerMetrics)
            TrackerAverageGrid(metrics: trackerMetrics)

            VStack(spacing: 10) {
                ForEach(trackerMetrics.goals) { goal in
                    TrackerGoalRow(goal: goal)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("healthTracker")
        .onChange(of: tracker.cycleStartDate) { _, _ in
            Task {
                await tracker.reloadIfConnected()
            }
        }
        .alert(item: $activeHelp) { topic in
            Alert(
                title: Text(topic.title),
                message: Text(topic.message),
                dismissButton: .default(Text("Got it"))
            )
        }
    }

    private var isLoading: Bool {
        if case .loading = tracker.state { return true }
        return false
    }

    private var statusColor: Color {
        switch tracker.state {
        case .failed, .unavailable:
            return .red
        default:
            return .secondary
        }
    }
}

private struct TrackerScoreCard: View {
    let metrics: StepTrackerMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Plan match score")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(metrics.scoreMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(metrics.score.map(String.init) ?? "--")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppTheme.green)
                        .lineLimit(1)
                    Text(metrics.scoreStage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.82))
                        .clipShape(Capsule())
                }
            }

            if metrics.score != nil {
                ScoreScale(progress: metrics.scoreProgress)
            }
        }
        .padding(12)
        .background(AppTheme.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ScoreScale: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let markerX = max(8, min(width - 8, width * progress))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.green.opacity(0.14),
                                    AppTheme.green.opacity(0.22),
                                    AppTheme.green.opacity(0.34),
                                    AppTheme.green.opacity(0.48)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 8)

                    Capsule()
                        .fill(AppTheme.green)
                        .frame(width: width * progress, height: 8)

                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(AppTheme.green, lineWidth: 3))
                        .shadow(color: AppTheme.ink.opacity(0.18), radius: 5, x: 0, y: 2)
                        .frame(width: 16, height: 16)
                        .offset(x: markerX - 8)
                }
            }
            .frame(height: 16)

            HStack(alignment: .top) {
                Text("Start")
                Spacer()
                Text("Needs attention")
                Spacer()
                Text("Close")
                Spacer()
                Text("On plan")
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }
}

private struct TrackerAverageGrid: View {
    let metrics: StepTrackerMetrics

    var body: some View {
        VStack(spacing: 10) {
            TrackerStatTile(title: "Current cycle", value: metrics.currentCycleLabel)
                .frame(maxWidth: .infinity)

            averageProgressCard
            dataCheckCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var averageProgressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("90-day average progress")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                trackerValueColumn(title: "So far", value: metrics.averageSoFar)
                Divider()
                trackerValueColumn(title: "Needed next", value: metrics.neededNext)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var dataCheckCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data check")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                trackerValueColumn(title: "Below 100", value: metrics.lowStepDays)
                Divider()
                trackerValueColumn(title: "Above 22,300", value: metrics.highStepDays)
                Divider()
                trackerValueColumn(title: "Missing days", value: metrics.missingStepDays)
            }

            Text(metrics.dataCheckNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func trackerValueColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrackerStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TrackerGoalRow: View {
    let goal: DayCountGoalProgress

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(goal.count) / \(goal.targetDays) days")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("At least \(goal.thresholdRounded) steps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(goal.status)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.green)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AppTheme.green.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(10)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ChartPanel: View {
    let engine: PolicyEngine
    let result: PolicyResult
    @Binding var mode: PolicyChartMode
    @Binding var selectedDensityStep: Double?
    @Binding var selectedQuantileLevel: Double?
    @State private var activeHelp: HelpTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Advanced details")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(mode == .density ? "Density function of daily steps" : "Quantile function of daily steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HelpButton(color: AppTheme.green) {
                    activeHelp = mode == .density ? .densityFunction : .quantileFunction
                }
            }

            Picker("Chart", selection: $mode) {
                ForEach(PolicyChartMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("chartModePicker")
            .onChange(of: mode) { _, newMode in
                AnalyticsClient.shared.track(
                    newMode == .density ? "switch_density_chart" : "switch_quantile_chart",
                    properties: [
                        "mode": newMode == .density ? "density" : "quantile",
                        "source": "chart_panel"
                    ]
                )
            }

            ChartLegendRow(
                primaryColor: mode == .density ? AppTheme.green : AppTheme.purple,
                mode: mode,
                activeHelp: $activeHelp
            )

            Group {
                if mode == .density {
                    DensityChart(
                        engine: engine,
                        result: result,
                        selectedStep: $selectedDensityStep
                    )
                } else {
                    QuantileChart(
                        engine: engine,
                        result: result,
                        selectedLevel: $selectedQuantileLevel
                    )
                }
            }
            .frame(height: 292)
        }
        .cardStyle()
        .alert(item: $activeHelp) { topic in
            Alert(
                title: Text(topic.title),
                message: Text(topic.message),
                dismissButton: .default(Text("Got it"))
            )
        }
    }
}

private struct ChartLegendRow: View {
    let primaryColor: Color
    let mode: PolicyChartMode
    @Binding var activeHelp: HelpTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 14) {
                ChartLegendItem(label: "Your plan", color: primaryColor, style: .solidLine)
                HStack(spacing: 4) {
                    ChartLegendItem(label: "Similar profiles", color: AppTheme.reference, style: .dashedLine)
                    HelpButton(color: AppTheme.reference) {
                        activeHelp = .subgroupAverage
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                ChartLegendItem(label: redMarkerLabel, color: AppTheme.red, style: .dot)
                ChartLegendItem(label: blueMarkerLabel, color: AppTheme.blue, style: .dot)
                Spacer(minLength: 0)
            }
        }
    }

    private var redMarkerLabel: String {
        mode == .density ? "Most common" : "Q33"
    }

    private var blueMarkerLabel: String {
        mode == .density ? "90-day average" : "Q67"
    }
}

private struct ChartLegendItem: View {
    enum Style {
        case solidLine
        case dashedLine
        case dot
    }

    let label: String
    let color: Color
    let style: Style

    var body: some View {
        HStack(spacing: 6) {
            symbol
                .frame(width: 24, height: 9)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch style {
        case .solidLine, .dashedLine:
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: style == .dashedLine ? [5, 4] : [])
                )
            }
        case .dot:
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }
}

private struct FunctionChartPoint: Identifiable {
    enum Series: String {
        case individual = "Individual"
        case subgroup = "Subgroup average"
    }

    let id: String
    let x: Double
    let y: Double
    let series: Series
}

private struct DensityMarker: Identifiable {
    enum Kind {
        case peak
        case average
    }

    let id: String
    let kind: Kind
    let step: Double
    let density: Double
    let label: String

    var color: Color {
        switch kind {
        case .peak:
            return AppTheme.red
        case .average:
            return AppTheme.blue
        }
    }
}

private struct QuantileMarker: Identifiable {
    let id: String
    let level: Double
    let steps: Double
    let label: String
    let color: Color
    let annotationPosition: AnnotationPosition
}

private let dailyStepChartMin = 100.0
private let dailyStepChartMax = 22_300.0

private struct DensityChart: View {
    let engine: PolicyEngine
    let result: PolicyResult
    @Binding var selectedStep: Double?
    @State private var selectedMarkerID: String?

    var body: some View {
        Chart {
            ForEach(densityPoints) { point in
                LineMark(
                    x: .value("Daily steps", point.x),
                    y: .value("Density", point.y),
                    series: .value("Function", point.series.rawValue)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(by: .value("Function", point.series.rawValue))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: point.series == .individual ? 3 : 2,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: point.series == .subgroup ? [6, 4] : []
                    )
                )
            }

            ForEach(densityMarkers) { marker in
                PointMark(
                    x: .value(marker.kind == .peak ? "Peak" : "Average", marker.step),
                    y: .value("Density", marker.density)
                )
                .foregroundStyle(marker.color)
                .symbolSize(selectedMarkerID == marker.id ? 110 : 72)
                .annotation(position: marker.kind == .peak ? .top : .bottom, alignment: annotationAlignment(for: marker.step)) {
                    if selectedMarkerID == marker.id {
                        ChartLabel(text: marker.label, color: marker.color)
                    }
                }
            }

            if let selectedStep {
                let selection = engine.nearestDensityPoint(in: result, step: selectedStep)
                RuleMark(x: .value("Selected step", selection.step))
                    .foregroundStyle(AppTheme.ink.opacity(0.28))
                    .annotation(position: .top, alignment: annotationAlignment(for: selection.step)) {
                        ChartLabel(text: "\(formatHundred(selection.step)) steps", color: AppTheme.ink)
                }
            }
        }
        .chartForegroundStyleScale([
            FunctionChartPoint.Series.individual.rawValue: AppTheme.green,
            FunctionChartPoint.Series.subgroup.rawValue: AppTheme.reference
        ])
        .chartLegend(.hidden)
        .chartXScale(domain: dailyStepChartMin...dailyStepChartMax)
        .chartYScale(domain: 0...densityYMax)
        .chartXAxis {
            AxisMarks(values: [100, 5_000, 10_000, 15_000, 22_300]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let steps = value.as(Double.self) {
                        Text(axisStepLabel(steps))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3))
        }
        .chartXAxisLabel("Daily steps (100-22.3k)")
        .chartYAxisLabel("Relative frequency")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geometry[plotFrame].origin
                                let x = value.location.x - origin.x
                                if let selected: Double = proxy.value(atX: x) {
                                    if let marker = nearestMarker(to: selected) {
                                        selectedMarkerID = marker.id
                                        selectedStep = nil
                                    } else {
                                        selectedMarkerID = nil
                                        selectedStep = selected
                                    }
                                }
                            }
                    )
            }
        }
    }

    private func formatHundred(_ value: Double) -> String {
        let rounded = (value / 100).rounded() * 100
        return integerFormatter.string(from: NSNumber(value: rounded)) ?? "\(Int(rounded))"
    }

    private var densityYMax: Double {
        let maxValue = max(result.density.max() ?? 0, result.referenceDensity.max() ?? 0)
        return max(maxValue * 1.22, 0.0001)
    }

    private func axisStepLabel(_ value: Double) -> String {
        if value == 100 { return "100" }
        if value == 22_300 { return "22.3k" }
        return "\(Int(value / 1000))k"
    }

    private func annotationAlignment(for step: Double) -> Alignment {
        let fraction = (step - dailyStepChartMin) / (dailyStepChartMax - dailyStepChartMin)
        if fraction < 0.18 { return .leading }
        if fraction > 0.82 { return .trailing }
        return .center
    }

    private var densityPoints: [FunctionChartPoint] {
        makeFunctionPoints(
            x: engine.data.supports.density,
            individual: result.density,
            subgroup: result.referenceDensity
        )
    }

    private var densityMarkers: [DensityMarker] {
        let peakMarkers = result.peaks.map { peak in
            DensityMarker(
                id: "peak-\(peak.index)",
                kind: .peak,
                step: peak.step,
                density: peak.density,
                label: "Most common ≈ \(formatHundred(peak.step)) steps"
            )
        }

        return peakMarkers + [
            DensityMarker(
                id: "average",
                kind: .average,
                step: result.meanSteps,
                density: result.meanDensity,
                label: "90-day average ≈ \(result.meanRounded) steps"
            )
        ]
    }

    private func nearestMarker(to step: Double) -> DensityMarker? {
        let tolerance = (dailyStepChartMax - dailyStepChartMin) * 0.045
        return densityMarkers
            .map { marker in (marker, abs(marker.step - step)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?
            .0
    }
}

private struct QuantileChart: View {
    let engine: PolicyEngine
    let result: PolicyResult
    @Binding var selectedLevel: Double?
    @State private var selectedMarkerID: String?

    var body: some View {
        Chart {
            ForEach(quantilePoints) { point in
                LineMark(
                    x: .value("Quantile level", point.x),
                    y: .value("Daily steps", point.y),
                    series: .value("Function", point.series.rawValue)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(by: .value("Function", point.series.rawValue))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: point.series == .individual ? 3 : 2,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: point.series == .subgroup ? [6, 4] : []
                    )
                )
            }

            ForEach(quantileMarkers) { marker in
                PointMark(
                    x: .value("Quantile level", marker.level),
                    y: .value("Daily steps", marker.steps)
                )
                .foregroundStyle(marker.color)
                .symbolSize(selectedMarkerID == marker.id ? 110 : 88)
                .annotation(position: marker.annotationPosition, alignment: annotationAlignment(for: marker.level)) {
                    if selectedMarkerID == marker.id {
                        ChartLabel(text: marker.label, color: marker.color)
                    }
                }
            }

            if let selectedLevel {
                let selection = engine.nearestQuantilePoint(in: result, level: selectedLevel)
                RuleMark(x: .value("Selected quantile", selection.level))
                    .foregroundStyle(AppTheme.ink.opacity(0.28))
                    .annotation(position: .top, alignment: annotationAlignment(for: selection.level)) {
                        ChartLabel(text: "Level \(String(format: "%.2f", selection.level))", color: AppTheme.ink)
                }
            }
        }
        .chartForegroundStyleScale([
            FunctionChartPoint.Series.individual.rawValue: AppTheme.purple,
            FunctionChartPoint.Series.subgroup.rawValue: AppTheme.reference
        ])
        .chartLegend(.hidden)
        .chartXScale(domain: 0...1)
        .chartYScale(domain: 0...quantileYMax)
        .chartXAxis {
            AxisMarks(values: [0, 0.33, 0.67, 1.0]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let level = value.as(Double.self) {
                        Text(axisQuantileLabel(level))
                    }
                }
            }
        }
        .chartXAxisLabel("Quantile level")
        .chartYAxisLabel("Daily steps")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geometry[plotFrame].origin
                                let x = value.location.x - origin.x
                                if let selected: Double = proxy.value(atX: x) {
                                    if let marker = nearestMarker(to: selected) {
                                        selectedMarkerID = marker.id
                                        selectedLevel = nil
                                    } else {
                                        selectedMarkerID = nil
                                        selectedLevel = selected
                                    }
                                }
                            }
                    )
            }
        }
    }

    private var quantilePoints: [FunctionChartPoint] {
        makeFunctionPoints(
            x: engine.data.supports.lqd,
            individual: result.quantile,
            subgroup: result.referenceQuantile
        )
    }

    private var quantileMarkers: [QuantileMarker] {
        [
            QuantileMarker(
                id: "q33",
                level: 0.33,
                steps: result.q33,
                label: "Q33 ≈ \(result.q33Rounded)",
                color: AppTheme.red,
                annotationPosition: .bottom
            ),
            QuantileMarker(
                id: "q67",
                level: 0.67,
                steps: result.q67,
                label: "Q67 ≈ \(result.q67Rounded)",
                color: AppTheme.blue,
                annotationPosition: .top
            )
        ]
    }

    private var quantileYMax: Double {
        let maxValue = max(result.quantile.max() ?? 0, result.referenceQuantile.max() ?? 0)
        let padded = maxValue * 1.18
        return max((padded / 5_000).rounded(.up) * 5_000, 10_000)
    }

    private func axisQuantileLabel(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value == 1 { return "1" }
        return String(format: "%.2f", value)
    }

    private func annotationAlignment(for level: Double) -> Alignment {
        if level < 0.16 { return .leading }
        if level > 0.84 { return .trailing }
        return .center
    }

    private func nearestMarker(to level: Double) -> QuantileMarker? {
        let tolerance = 0.045
        return quantileMarkers
            .map { marker in (marker, abs(marker.level - level)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?
            .0
    }
}

private func makeFunctionPoints(
    x: [Double],
    individual: [Double],
    subgroup: [Double]
) -> [FunctionChartPoint] {
    let count = min(x.count, individual.count, subgroup.count)
    let subgroupPoints = (0..<count).compactMap { index -> FunctionChartPoint? in
        guard x[index].isFinite, subgroup[index].isFinite else { return nil }
        return FunctionChartPoint(
            id: "\(FunctionChartPoint.Series.subgroup.rawValue)-\(index)",
            x: x[index],
            y: subgroup[index],
            series: .subgroup
        )
    }
    .sorted { $0.x < $1.x }

    let individualPoints = (0..<count).compactMap { index -> FunctionChartPoint? in
        guard x[index].isFinite, individual[index].isFinite else { return nil }
        return FunctionChartPoint(
            id: "\(FunctionChartPoint.Series.individual.rawValue)-\(index)",
            x: x[index],
            y: individual[index],
            series: .individual
        )
    }
    .sorted { $0.x < $1.x }

    return subgroupPoints + individualPoints
}

private struct ChartLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color.opacity(0.55))
            )
    }
}

private struct InsightPanel: View {
    let result: PolicyResult
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                let nextState = !isExpanded
                isExpanded = nextState
                if nextState {
                    AnalyticsClient.shared.track("expand_insight", properties: ["source": "insight_panel"])
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Using the plan")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("A plain-language explanation of how to use this 90-day plan.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Using the plan")

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    InsightItem(
                        icon: "target",
                        title: "Main goal",
                        detail: "Use the average daily steps as the main target across the full 90 days."
                    )
                    InsightItem(
                        icon: "calendar",
                        title: "Flexible days",
                        detail: "Some days can be lighter and some can be more active; the plan is not a strict daily minimum."
                    )
                }
            }
        }
        .cardStyle()
    }
}

private struct InsightItem: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.green.opacity(0.10))
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(AppTheme.green)
                    .offset(x: iconOffset.width, y: iconOffset.height)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var iconSize: CGFloat {
        icon == "target" ? 14.5 : 15.5
    }

    private var iconOffset: CGSize {
        switch icon {
        case "chart.xyaxis.line":
            CGSize(width: -0.5, height: -0.5)
        case "slider.horizontal.3":
            CGSize(width: -0.25, height: -0.25)
        default:
            .zero
        }
    }
}

private struct SubgroupPanel: View {
    let result: PolicyResult
    @State private var activeHelp: HelpTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Similar Profile Group")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                HelpButton(color: AppTheme.green) {
                    activeHelp = .subgroupAverage
                }
                Spacer()
            }

            Text("Your plan is compared with people in a similar cardiometabolic profile group.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                SubgroupPill(label: "Glucose", value: compactBucketLabel(result.subgroup.glucose, removing: ["glucose"]))
                SubgroupPill(label: "Age", value: compactBucketLabel(result.subgroup.age, removing: ["age"]))
                SubgroupPill(label: "BMI", value: compactBucketLabel(result.subgroup.bmi, removing: ["BMI"]))
                SubgroupPill(label: "Blood pressure", value: compactBucketLabel(result.subgroup.bp, removing: ["blood pressure"]))
                SubgroupPill(label: "Sex", value: result.subgroup.sex.rawValue)
                SubgroupPill(label: "Glucose source", value: result.subgroup.glucoseImputed ? "Imputed" : "Measured")
            }
        }
        .cardStyle()
        .alert(item: $activeHelp) { topic in
            Alert(
                title: Text(topic.title),
                message: Text(topic.message),
                dismissButton: .default(Text("Got it"))
            )
        }
    }

    private func compactBucketLabel(_ bucket: SubgroupProfile.Bucket, removing words: [String]) -> String {
        words.reduce(bucket.label) { label, word in
            label
                .replacingOccurrences(of: " \(word)", with: "", options: [.caseInsensitive])
                .replacingOccurrences(of: "\(word) ", with: "", options: [.caseInsensitive])
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SubgroupPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(AppTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension View {
    func profileNumberField() -> some View {
        self
            .keyboardType(.decimalPad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 11)
            .frame(height: 42)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.line)
            )
    }

    func cardStyle() -> some View {
        self
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.line)
            )
    }
}

private enum AppTheme {
    static let background = Color(red: 0.961, green: 0.980, blue: 0.984)
    static let ink = Color(red: 0.027, green: 0.122, blue: 0.200)
    static let line = Color(red: 0.847, green: 0.910, blue: 0.922)
    static let green = Color(red: 0.043, green: 0.471, blue: 0.463)
    static let blue = Color(red: 0.059, green: 0.388, blue: 0.533)
    static let purple = Color(red: 0.071, green: 0.227, blue: 0.380)
    static let reference = Color(red: 0.498, green: 0.553, blue: 0.596)
    static let red = Color(red: 0.780, green: 0.396, blue: 0.349)

    static let primaryGradient = LinearGradient(
        colors: [green, blue, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private let integerFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    return formatter
}()

#Preview {
    if let data = try? PolicyModelData.load() {
        PolicyDashboardView(engine: PolicyEngine(data: data))
    }
}
