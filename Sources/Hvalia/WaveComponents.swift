import SwiftUI
import HvaliaCore

struct WaveWelcome: View {
    @EnvironmentObject private var m: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var headingFocused: Bool
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hvalia").font(.system(size: 60, weight: .bold)).tracking(-2)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                Text(m.t("Включение 5G на iPhone в Беларуси", "Enable 5G on iPhone in Belarus"))
                    .font(.system(size: 18, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.blue)
                .frame(width: 120, height: 120)
                .background {
                    if !reduceTransparency {
                        RadialGradient(colors: [Color.blue.opacity(0.13), Color.blue.opacity(0)], center: .center, startRadius: 0, endRadius: 60)
                    }
                }
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .onAppear { headingFocused = true }
    }
}

struct WaveActionContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder func waveButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }
}

struct WaveHeading: View {
    @EnvironmentObject private var m: AppModel
    @AccessibilityFocusState private var headingFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: Layout.related) {
            Text(m.presentation.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            Text(m.presentation.subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { headingFocused = true }
    }
}

struct WaveStepper: View {
    @EnvironmentObject private var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let current = m.routeIndex {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(m.flowTitle).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(m.stepLabel).font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(m.routeTitles.enumerated()), id: \.offset) { index, title in
                        let number = index + 1
                        HStack(spacing: 8) {
                            Image(systemName: m.routeSymbol(at: index))
                                .font(.system(size: 15, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(number == current ? Color.white : (number < current ? .blue : .secondary))
                                .background(number == current ? Color.blue : Color(nsColor: .controlBackgroundColor), in: Circle())
                                .overlay(Circle().stroke(number <= current ? Color.blue : Color.secondary.opacity(0.35), lineWidth: 1))
                                .accessibilityHidden(true)
                            Text(title).font(.system(size: 12, weight: number == current ? .semibold : .regular))
                                .foregroundStyle(number == current ? Color.primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(number == current ? Color.blue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(title)
                        .accessibilityValue(number == current ? m.stepLabel + ", " + m.t("Текущий шаг", "Current step") : "")
                        if number < m.routeCount {
                            HStack(spacing: 0) {
                                Rectangle().fill(number < current ? Color.blue.opacity(0.65) : Color.secondary.opacity(0.25))
                                    .frame(width: 1, height: 8).frame(width: 28)
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 8).accessibilityHidden(true)
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12).padding(.vertical, 20)
            .frame(width: 176)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(m.t("Этапы", "Steps"))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: current)
        }
    }
}

struct WaveNotice: View {
    let text: String
    var blocking = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Label(text, systemImage: blocking ? "exclamationmark.octagon" : "exclamationmark.triangle")
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : (blocking ? Color.red : .orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(contrast == .increased ? Color.primary : (blocking ? Color.red : .orange).opacity(0.4)))
    }
}

struct WaveFact: View {
    let title: String
    let value: String
    let confirmed: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(confirmed ? Color.green : .secondary).accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.font(.callout).accessibilityElement(children: .combine)
    }
}

struct WaveOperationStages: View {
    @EnvironmentObject private var m: AppModel
    var body: some View {
        let phases: [TransactionProgress] = [.saving, m.flow.mode == .restore || m.transactionProgress == .restoring ? .restoring : .applying, .finishing]
        let current = m.transactionProgress.flatMap { phases.firstIndex(of: $0) }
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                HStack(spacing: 10) {
                    Image(systemName: current == index ? "circle.inset.filled" : (current.map { index < $0 } == true ? "checkmark.circle" : "circle"))
                        .foregroundStyle(current == index ? Color.blue : .secondary).accessibilityHidden(true)
                    Text(label(phase)).foregroundStyle(current == index ? .primary : .secondary)
                }.accessibilityElement(children: .combine)
                    .accessibilityValue(current == index ? m.t("Выполняется", "In progress") : (current.map { index < $0 } == true ? m.t("Пройдено", "Passed") : m.t("Далее", "Next")))
            }
        }.font(.callout)
    }
    private func label(_ phase: TransactionProgress) -> String {
        switch phase {
        case .saving: m.t("Сохраняем настройки", "Saving settings")
        case .applying: m.t("Включаем 5G", "Enabling 5G")
        case .restoring: m.t("Возвращаем оригинал", "Restoring the original")
        case .finishing: m.t("Завершаем", "Finishing")
        }
    }
}
