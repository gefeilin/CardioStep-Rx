import Charts
import SwiftUI

enum PolicyChartMode: String, CaseIterable, Identifiable {
    case density = "Density"
    case quantile = "Quantile"

    var id: String { rawValue }
}

struct PolicyDashboardView: View {
    let engine: PolicyEngine

    @State private var form: ProfileFormState
    @State private var result: PolicyResult
    @State private var chartMode: PolicyChartMode = .density
    @State private var isShowingProfileEditor = false
    @State private var profileEditorDetent: PresentationDetent = .height(470)
    @State private var isInsightExpanded = false
    @State private var selectedDensityStep: Double?
    @State private var selectedQuantileLevel: Double?

    init(engine: PolicyEngine) {
        self.engine = engine
        let initialForm = ProfileFormState(example: engine.data.exampleRaw)
        _form = State(initialValue: initialForm)
        do {
            _result = State(initialValue: try engine.evaluate(profile: initialForm.validatedProfile()))
        } catch {
            let fallback = PatientProfile(glucose: nil, bmi: 29.21, dbp: 74.59, sbp: 123.87, age: 55.46, sex: .female)
            _result = State(initialValue: try! engine.evaluate(profile: fallback))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 820
            ScrollView {
                if isWide {
                    HStack(alignment: .top, spacing: 16) {
                        profileCard(isEmbedded: true)
                            .frame(width: min(360, proxy.size.width * 0.36))
                        resultsColumn(isWide: isWide)
                    }
                    .padding(18)
                } else {
                    resultsColumn(isWide: isWide)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .overlay(alignment: .top) {
                AppTheme.background
                    .frame(height: proxy.safeAreaInsets.top + 6)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .sheet(isPresented: $isShowingProfileEditor) {
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
                .presentationDetents([.height(470), .large], selection: $profileEditorDetent)
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func resultsColumn(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(isWide: isWide)
            SummaryGrid(result: result)
            ChartPanel(
                engine: engine,
                result: result,
                mode: $chartMode,
                selectedDensityStep: $selectedDensityStep,
                selectedQuantileLevel: $selectedQuantileLevel
            )
            InsightPanel(result: result, isExpanded: $isInsightExpanded)
            SubgroupPanel(result: result)
            Text("Research use only, not clinical decision making.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .frame(maxWidth: isWide ? .infinity : nil, alignment: .topLeading)
    }

    private func header(isWide: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CardioStep Rx")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.green)
                    .lineLimit(1)
                Text("Precision Physical Activity Prescription")
                    .font(.system(size: 27, weight: .bold, design: .default))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier("appTitle")
                Text("Recommended 90-day distribution of daily steps for cardiometabolic risk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            if !isWide {
                Button {
                    profileEditorDetent = .height(470)
                    isShowingProfileEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.line))
                }
                .accessibilityLabel("Edit Profile")
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

struct ProfileFormState: Equatable {
    var glucose: String
    var bmi: String
    var dbp: String
    var sbp: String
    var age: String
    var sex: SexAtBirth

    init(example: PolicyModelData.ExampleRaw) {
        glucose = example.glucose
        bmi = Self.formatInput(example.bmi)
        dbp = Self.formatInput(example.dbp)
        sbp = Self.formatInput(example.sbp)
        age = Self.formatInput(example.age)
        sex = SexAtBirth(rawValue: example.sex) ?? .female
    }

    func validatedProfile() throws -> PatientProfile {
        PatientProfile(
            glucose: try optionalNumber(glucose, field: "glucose"),
            bmi: try requiredNumber(bmi, field: "bmi"),
            dbp: try requiredNumber(dbp, field: "dbp"),
            sbp: try requiredNumber(sbp, field: "sbp"),
            age: try requiredNumber(age, field: "age"),
            sex: sex
        )
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
        VStack(alignment: .leading, spacing: 14) {
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
                PolicyTextField(title: "Glucose (mg/dL)", text: $form.glucose, placeholder: "Impute")
                PolicyTextField(title: "BMI (kg/m2)", text: $form.bmi)
            }

            ProfileSection(title: "Blood Pressure") {
                PolicyTextField(title: "DBP (mmHg)", text: $form.dbp)
                PolicyTextField(title: "SBP (mmHg)", text: $form.sbp)
            }

            ProfileSection(title: "Demographics") {
                PolicyTextField(title: "Age (years)", text: $form.age)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Sex at birth")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Sex at birth", selection: $form.sex) {
                        ForEach(SexAtBirth.allCases) { sex in
                            Text(sex.rawValue).tag(sex)
                        }
                    }
                    .pickerStyle(.segmented)
                }
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
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    generate()
                } label: {
                    Label("Generate", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.green)
                .accessibilityIdentifier("generatePolicyButton")
            }
        }
    }

    private func generate() {
        do {
            result = try engine.evaluate(profile: form.validatedProfile())
            errorMessage = nil
            if dismissAfterGenerate {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        form = ProfileFormState(example: engine.data.exampleRaw)
        generate()
    }
}

private struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.green)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                content
            }
        }
    }
}

private struct PolicyTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
        }
    }
}

private enum HelpTopic: String, Identifiable {
    case averageDailySteps
    case mostFrequentLevel
    case lowActivityDay
    case highActivityDay
    case glucoseImputed
    case glucoseMeasured
    case densityFunction
    case quantileFunction
    case subgroupAverage

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
        case .glucoseImputed:
            return "Glucose imputed"
        case .glucoseMeasured:
            return "Glucose"
        case .densityFunction:
            return "Density function"
        case .quantileFunction:
            return "Quantile function"
        case .subgroupAverage:
            return "Subgroup average"
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
        case .glucoseImputed:
            return "Glucose was left blank, so the app estimated it from BMI, blood pressure, age, and sex for this research calculation."
        case .glucoseMeasured:
            return "The glucose value entered in the profile and used by the recommendation model."
        case .densityFunction:
            return "This curve shows which daily step levels are more or less likely in the recommended 90-day plan. Taller parts mean more days near that step level."
        case .quantileFunction:
            return "This curve maps a percentile of days to a daily step level. For example, lower percentiles represent lower-activity days."
        case .subgroupAverage:
            return "The gray curve averages recommendations for similar profiles with the same glucose, age, BMI, blood pressure, sex, and glucose-source group."
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
            .background(AppTheme.green)
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
                    Text("Recommended")
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
                ChartLegendItem(label: "Individual policy", color: primaryColor, style: .solidLine)
                HStack(spacing: 4) {
                    ChartLegendItem(label: "Subgroup average", color: AppTheme.reference, style: .dashedLine)
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
        mode == .density ? "Most frequent" : "Q0.33"
    }

    private var blueMarkerLabel: String {
        mode == .density ? "90-day average" : "Q0.67"
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
        .chartYAxisLabel("Density")
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
                label: "Most frequent ≈ \(formatHundred(peak.step)) steps"
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
                        ChartLabel(text: "Q \(String(format: "%.2f", selection.level))", color: AppTheme.ink)
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
                label: "Q0.33 ≈ \(result.q33Rounded)",
                color: AppTheme.red,
                annotationPosition: .bottom
            ),
            QuantileMarker(
                id: "q67",
                level: 0.67,
                steps: result.q67,
                label: "Q0.67 ≈ \(result.q67Rounded)",
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
                isExpanded.toggle()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insight")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("90-day target: \(result.meanRounded) average steps/day. Most frequent level: \(result.peakCardText).")
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
            .accessibilityLabel("Insight")

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    InsightItem(
                        icon: "target",
                        title: "Main target",
                        detail: "Average about \(result.meanRounded) steps per day across the next 90 days."
                    )
                    InsightItem(
                        icon: "chart.xyaxis.line",
                        title: "Typical high-frequency day",
                        detail: "More days should cluster near \(result.peakCardText) steps. This is the distribution peak, not a one-day maximum."
                    )
                    InsightItem(
                        icon: "slider.horizontal.3",
                        title: "Flexible range",
                        detail: "Lower-activity days can be around \(result.q33Rounded) steps, while higher-activity days can reach \(result.q67Rounded) steps or more."
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
    static let background = Color(red: 0.945, green: 0.976, blue: 0.992)
    static let ink = Color(red: 0.035, green: 0.102, blue: 0.205)
    static let line = Color(red: 0.765, green: 0.867, blue: 0.932)
    static let green = Color(red: 0.000, green: 0.515, blue: 0.675)
    static let blue = Color(red: 0.070, green: 0.455, blue: 0.890)
    static let purple = Color(red: 0.015, green: 0.235, blue: 0.545)
    static let reference = Color(red: 0.535, green: 0.592, blue: 0.660)
    static let red = Color(red: 0.925, green: 0.255, blue: 0.250)
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
