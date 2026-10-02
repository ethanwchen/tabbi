import Charts
import SwiftUI
import NotchDeckCore

/// Three equal cards (CPU, GPU, Memory), each with a headline figure, a
/// 60-second sparkline and a one-line footer. Sampling only runs while the
/// panel is on screen.
struct SystemPanel: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            cpuCard
            gpuCard
            memoryCard
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private var cpuCard: some View {
        MetricCard(
            title: "CPU", symbol: "cpu",
            value: SystemFormat.percent(monitor.cpu?.total),
            history: monitor.cpuHistory.elements,
            help: "Total CPU usage across all cores, last 60 seconds"
        ) {
            if monitor.thermal.needsAttention {
                ThermalChip(level: monitor.thermal)
            } else if let cores = monitor.cpu?.perCore.count {
                Text("\(cores) cores")
            }
        } footer: {
            CoreStrip(perCore: monitor.cpu?.perCore ?? [])
        }
    }

    private var gpuCard: some View {
        let series = HistorySeries(monitor.gpuHistory.elements, capacity: SystemMonitor.historyCapacity)
        return MetricCard(
            title: "GPU", symbol: "square.stack.3d.up",
            value: SystemFormat.percent(monitor.gpu),
            history: monitor.gpuHistory.elements,
            help: "GPU utilization, last 60 seconds"
        ) {
            EmptyView()
        } footer: {
            if monitor.gpu == nil && series.isEmpty {
                FooterCaption("Not reported by this Mac")
            } else {
                FooterCaption("Peak \(SystemFormat.percent(series.peak))  ·  Avg \(SystemFormat.percent(series.average))")
            }
        }
    }

    private var memoryCard: some View {
        let memory = monitor.memory
        return MetricCard(
            title: "Memory", symbol: "memorychip",
            value: memory.map { SystemFormat.gigabytes($0.usedBytes) } ?? SystemFormat.unavailable,
            unit: memory == nil ? nil : "GB",
            history: monitor.memoryHistory.elements,
            help: "Memory in use and memory pressure"
        ) {
            if let memory { Text("of \(SystemFormat.gigabytes(memory.totalBytes)) GB") }
        } footer: {
            PressureBar(memory: memory)
        }
    }
}

/// Shared card layout so the three cards line up row for row.
private struct MetricCard<Accessory: View, Footer: View>: View {
    let title: String
    let symbol: String
    let value: String
    var unit: String?
    let history: [Double]
    let help: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var footer: Footer

    private let accent = Theme.Palette.accent(for: .system)

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: symbol)
                        .foregroundStyle(accent)
                    Text(title)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Spacer(minLength: Theme.Spacing.xs)
                    accessory
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                }
                .font(Theme.Typography.caption)
                .frame(height: 16)

                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                    Text(value)
                        .font(Theme.Typography.metric)
                        .foregroundStyle(value == SystemFormat.unavailable
                                         ? Theme.Palette.tertiaryText : Theme.Palette.primaryText)
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit)
                            .font(Theme.Typography.bodyEmphasis)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                }
                .animation(Theme.Motion.snappy, value: value)

                Sparkline(series: HistorySeries(history, capacity: SystemMonitor.historyCapacity))
                    .frame(maxHeight: .infinity)

                footer
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .help(help)
    }
}

/// Area + line chart on a fixed 0–100% scale so cards compare at a glance.
/// Empty history draws a dashed baseline instead of a blank gap.
private struct Sparkline: View {
    let series: HistorySeries
    private let accent = Theme.Palette.accent(for: .system)

    var body: some View {
        if series.points.count < 2 {
            VStack {
                Spacer()
                Line()
                    .stroke(Theme.Palette.tertiaryText, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(height: 1)
            }
            .overlay {
                Text("Measuring…")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
        } else {
            Chart {
                // Faint 50% rule gives low readings a sense of scale.
                RuleMark(y: .value("Half", 0.5))
                    .foregroundStyle(Theme.Palette.stroke)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                ForEach(series.points, id: \.x) { point in
                    AreaMark(x: .value("Time", point.x), y: .value("Usage", point.y))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(
                            colors: [accent.opacity(0.32), accent.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    LineMark(x: .value("Time", point.x), y: .value("Usage", point.y))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .chartXScale(domain: 0...(series.capacity - 1))
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { $0.clipped() }
            .animation(Theme.Motion.content, value: series)
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// One tiny bar per core, filled bottom-up with that core's load.
private struct CoreStrip: View {
    let perCore: [Double]
    private let accent = Theme.Palette.accent(for: .system)

    var body: some View {
        if perCore.isEmpty {
            FooterCaption("Per-core load appears shortly")
        } else {
            HStack(alignment: .bottom, spacing: Theme.Spacing.xxs) {
                ForEach(perCore.indices, id: \.self) { index in
                    let load = min(max(perCore[index], 0), 1)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(accent.opacity(0.16))
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(accent.opacity(0.55 + 0.45 * load))
                                .frame(height: max(2, 14 * load))
                        }
                        .frame(maxWidth: .infinity)
                }
            }
            .animation(Theme.Motion.snappy, value: perCore)
        }
    }
}

/// Used-memory bar colored by kernel memory pressure.
private struct PressureBar: View {
    let memory: MemoryStats?

    var body: some View {
        if let memory {
            let color = color(for: memory.pressure)
            HStack(spacing: Theme.Spacing.s) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Palette.surfaceHover)
                        Capsule().fill(color)
                            .frame(width: proxy.size.width * memory.usedFraction)
                    }
                }
                .frame(height: 4)
                Text(memory.pressure.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(color)
                    .fixedSize()
            }
            .animation(Theme.Motion.snappy, value: memory)
            .help("Memory pressure: \(memory.pressure.title)")
        } else {
            FooterCaption("Memory stats unavailable")
        }
    }

    private func color(for pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: Theme.Palette.success
        case .warning: Theme.Palette.warning
        case .critical: Theme.Palette.danger
        }
    }
}

/// Shown in the CPU card header only when the Mac is running warm.
private struct ThermalChip: View {
    let level: ThermalLevel

    var body: some View {
        let color = level == .critical ? Theme.Palette.danger : Theme.Palette.warning
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: "thermometer.medium")
            Text(level.title)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Spacing.xs + Theme.Spacing.xxs)
        .frame(height: 16)
        .background(Capsule().fill(color.opacity(0.16)))
        .help("Thermal state: \(level.title)")
    }
}

private struct FooterCaption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.tertiaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}
