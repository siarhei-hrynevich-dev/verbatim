import SwiftUI

/// The selected summary model's settings. They stay hidden behind one switch: off, the model's recommended preset is
/// used and nothing needs choosing; on, each value can be adjusted, and Reset returns to the preset.
struct SummarySettingsSection: View {
    @Bindable var viewModel: SummarySettingsViewModel

    var body: some View {
        if let model = viewModel.model, let settings = viewModel.settings {
            SettingsSection(title: "Summary Settings", footnote: footnote(for: model)) {
                SettingsToggleRow(
                    title: "Customize Settings",
                    detail: viewModel.isCustomized
                        ? String(localized: "Your own values for \(model.name).")
                        : String(localized: "Using the recommended values for \(model.name)."),
                    isOn: $viewModel.isCustomized
                )
                if viewModel.isCustomized {
                    GroupedDivider(leadingInset: 12)
                    lengthRows(settings)
                    GroupedDivider(leadingInset: 12)
                    samplingRows(settings)
                    GroupedDivider(leadingInset: 12)
                    resetRow
                }
            }
        }
    }

    private func footnote(for model: LanguageModel) -> String {
        String(
            localized: """
                Batches are measured in tokens, about three quarters of a word each. Larger batches need fewer passes \
                and more memory; \(model.name) reads up to \(model.contextTokens.formatted()) tokens at once.
                """
        )
    }

    @ViewBuilder
    private func lengthRows(_ settings: SummarySettings) -> some View {
        stepperRow(
            IntegerSetting(
                title: "Batch Size",
                detail: String(localized: "Transcript tokens summarized at a time."),
                range: SummarySettings.batchTokenRange.lowerBound...viewModel.batchTokenLimit,
                step: 500,
                keyPath: \.batchTokens
            ),
            value: settings.batchTokens
        )
        GroupedDivider(leadingInset: 12)
        stepperRow(
            IntegerSetting(
                title: "Notes per Batch",
                detail: String(localized: "The longest the notes on one batch may be, in tokens."),
                range: SummarySettings.batchNoteTokenRange,
                step: 50,
                keyPath: \.batchNoteTokens
            ),
            value: settings.batchNoteTokens
        )
        GroupedDivider(leadingInset: 12)
        stepperRow(
            IntegerSetting(
                title: "Summary Length",
                detail: String(localized: "The longest the final summary may be, in tokens."),
                range: SummarySettings.summaryTokenRange,
                step: 50,
                keyPath: \.summaryTokens
            ),
            value: settings.summaryTokens
        )
    }

    @ViewBuilder
    private func samplingRows(_ settings: SummarySettings) -> some View {
        sliderRow(
            DecimalSetting(
                title: "Temperature",
                detail: String(localized: "Lower stays closer to what was said."),
                range: SummarySettings.temperatureRange,
                step: 0.05,
                keyPath: \.temperature
            ),
            value: settings.temperature
        )
        GroupedDivider(leadingInset: 12)
        sliderRow(
            DecimalSetting(
                title: "Top P",
                detail: String(localized: "Considers only the likeliest words making up this share."),
                range: SummarySettings.topPRange,
                step: 0.05,
                keyPath: \.topP
            ),
            value: settings.topP
        )
        GroupedDivider(leadingInset: 12)
        stepperRow(
            IntegerSetting(
                title: "Top K",
                detail: String(localized: "Considers only this many of the likeliest words. 0 turns it off."),
                range: SummarySettings.topKRange,
                step: 5,
                keyPath: \.topK
            ),
            value: settings.topK
        )
        GroupedDivider(leadingInset: 12)
        sliderRow(
            DecimalSetting(
                title: "Repetition Penalty",
                detail: String(localized: "Discourages repeating the same words. 1 turns it off."),
                range: SummarySettings.repetitionPenaltyRange,
                step: 0.05,
                keyPath: \.repetitionPenalty
            ),
            value: settings.repetitionPenalty
        )
    }

    private var resetRow: some View {
        SettingsRow(title: "Recommended Settings", isCompact: true) {
            Button("Reset to Recommended", action: viewModel.resetToPreset)
                .buttonStyle(.verbatim(.secondary, size: .inline))
                .disabled(!viewModel.differsFromPreset)
        }
    }

    private func stepperRow(_ setting: IntegerSetting, value: Int) -> some View {
        SettingsRow(title: setting.title, detail: setting.detail) {
            Text(value.formatted())
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(VerbatimColor.secondaryText)
            Stepper(
                setting.title,
                value: Binding(get: { value }, set: { viewModel.set(setting.keyPath, to: $0) }),
                in: setting.range,
                step: setting.step
            )
            .labelsHidden()
        }
    }

    private func sliderRow(_ setting: DecimalSetting, value: Double) -> some View {
        let step = setting.step
        return SettingsRow(title: setting.title, detail: setting.detail) {
            Slider(
                value: Binding(
                    get: { value },
                    set: { viewModel.set(setting.keyPath, to: ($0 / step).rounded() * step) }
                ),
                in: setting.range
            ) {
                Text(setting.title)
            }
            .labelsHidden()
            .frame(width: 140)
            Text(value.formatted(.number.precision(.fractionLength(2))))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(VerbatimColor.secondaryText)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// A whole-number setting and how it is edited.
private struct IntegerSetting {
    let title: LocalizedStringKey
    let detail: String
    let range: ClosedRange<Int>
    let step: Int
    let keyPath: WritableKeyPath<SummarySettings, Int>
}

/// A fractional setting and how it is edited.
private struct DecimalSetting {
    let title: LocalizedStringKey
    let detail: String
    let range: ClosedRange<Double>
    let step: Double
    let keyPath: WritableKeyPath<SummarySettings, Double>
}
