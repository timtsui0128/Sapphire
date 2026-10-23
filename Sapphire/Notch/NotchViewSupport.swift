//
//  NotchViewSupport.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-02

import SwiftUI
import AppKit

/// Measure the content once, keeping the same view graph when its display changes.
/// Oversized rows scroll inside the panel instead of widening the panel off screen.
struct NotchPanelViewport<Content: View>: View {
    let maximumSize: CGSize
    let content: Content
    var onHorizontalOverflow: ((Bool) -> Void)? = nil
    @State private var idealSize: CGSize = .zero

    private var viewportSize: CGSize {
        CGSize(
            width: min(max(1, idealSize.width), max(1, maximumSize.width)),
            height: min(max(1, idealSize.height), max(1, maximumSize.height))
        )
    }

    var body: some View {
        let overflows = idealSize.width > viewportSize.width + 0.5 || idealSize.height > viewportSize.height + 0.5
        ScrollView([.horizontal, .vertical]) {
            content
                .measureIdealSize(into: $idealSize, sizeIsProposalIndependent: true)
        }
        .scrollIndicators(overflows ? .visible : .hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: viewportSize.width, height: viewportSize.height)
        .clipped()
        .onChange(of: idealSize.width > viewportSize.width + 0.5, initial: true) { _, overflows in
            onHorizontalOverflow?(overflows)
        }
    }
}

struct IdealSizeReader: Layout {
    final class Cache {
        var ideal: CGSize = .zero
        var reported: CGSize?
        var reportGeneration = 0
    }

    let epsilon: CGFloat
    let sizeIsProposalIndependent: Bool
    var reportGeneration = 0
    let onChange: (CGSize) -> Void

    func makeCache(subviews: Subviews) -> Cache {
        let cache = Cache()
        cache.ideal = Self.idealSize(of: subviews)
        cache.reportGeneration = reportGeneration
        return cache
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.ideal = Self.idealSize(of: subviews)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        report(cache.ideal, cache: cache)
        if sizeIsProposalIndependent || proposal == .unspecified { return cache.ideal }
        guard let subview = subviews.first else { return .zero }
        return subview.sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard let subview = subviews.first else { return }
        subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: proposal)
    }

    private static func idealSize(of subviews: Subviews) -> CGSize {
        subviews.first?.sizeThatFits(.unspecified) ?? .zero
    }

    private func report(_ size: CGSize, cache: Cache) {
        if cache.reportGeneration != reportGeneration {
            cache.reportGeneration = reportGeneration
            cache.reported = nil
        }
        if let reported = cache.reported,
           abs(reported.width - size.width) <= epsilon,
           abs(reported.height - size.height) <= epsilon {
            return
        }
        cache.reported = size
        let onChange = self.onChange
        DispatchQueue.main.async { onChange(size) }
    }
}

extension View {
    func measureIdealSize(
        into binding: Binding<CGSize>,
        epsilon: CGFloat = 0.5,
        sizeIsProposalIndependent: Bool = false,
        reportGeneration: Int = 0
    ) -> some View {
        let reader = IdealSizeReader(
            epsilon: epsilon,
            sizeIsProposalIndependent: sizeIsProposalIndependent,
            reportGeneration: reportGeneration
        ) { newValue in
            guard abs(newValue.width - binding.wrappedValue.width) > epsilon
                || abs(newValue.height - binding.wrappedValue.height) > epsilon else { return }
            binding.wrappedValue = newValue
        }
        return reader { self }
    }

    func measureIdealWidth(into binding: Binding<CGFloat>, epsilon: CGFloat = 0.5) -> some View {
        let reader = IdealSizeReader(
            epsilon: epsilon,
            sizeIsProposalIndependent: false
        ) { newValue in
            guard abs(newValue.width - binding.wrappedValue) > epsilon else { return }
            binding.wrappedValue = newValue.width
        }
        return reader { self }
    }
}

struct SubtleIconButton: View {
    let systemName: String
    let action: () -> Void
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    var isSelected: Bool = false

    @State private var isHovering = false

    init(systemName: String, action: @escaping () -> Void, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 6, isSelected: Bool = false) {
        self.systemName = systemName
        self.action = action
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.isSelected = isSelected
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(isHovering ? 1.0 : 0.7))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .scaleEffect(isHovering ? 1.1 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isHovering)
    }
}

/// Shared by the attached notch, floating island and pinned detail headers.
struct NotchPinButton: View {
    @Binding var isPinned: Bool
    var isFloatingIsland = false
    let onPin: (Bool) -> Void

    var body: some View {
        Group {
            if isFloatingIsland {
                NotchIslandBarButton(systemName: isPinned ? "pin.fill" : "pin",
                                     isSelected: isPinned,
                                     activeTint: isPinned ? .accentColor : nil,
                                     help: help, action: toggle)
            } else {
                SubtleIconButton(systemName: isPinned ? "pin.fill" : "pin", action: toggle,
                                 horizontalPadding: 6, isSelected: isPinned)
            }
        }
        .help(help)
        .accessibilityIdentifier("notch-pin")
        .accessibilityLabel("Keep panel open")
        .accessibilityValue(isPinned ? "Pinned" : "Unpinned")
        .accessibilityAddTraits(isPinned ? .isSelected : [])
    }

    private var help: String { isPinned ? "Unpin (Esc to close)" : "Pin Open" }

    private func toggle() {
        isPinned.toggle()
        onPin(isPinned)
    }
}

struct BatteryInfoView: View {
    @Environment(\.colorScheme) private var colorScheme
    let level: Int
    let isCharging: Bool
    let timeRemaining: String?

    private var batteryColor: Color {
        if isCharging { return .green }
        if level <= 10 { return .red }
        if level <= 20 { return .yellow }
        return .primary
    }

    private var contentColor: Color {
        return colorScheme == .light && !(isCharging && level >= 50) ? .white : .black
    }

    var body: some View {
        HStack(spacing: NotchConfiguration.batteryHStackSpacing) {
            if let timeString = timeRemaining {
                Text(timeString)
                    .font(.system(size: NotchConfiguration.batteryTextFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .transition(.opacity.animation(.easeInOut))
                    .padding(.trailing, NotchConfiguration.batteryTextTrailingPadding)
            }
            ZStack {
                Image(systemName: "battery.100")
                    .font(.system(size: NotchConfiguration.batteryIconSize, weight: .light))
                    .foregroundStyle(Color.primary.opacity(0.7))

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(batteryColor)
                        .frame(width: 35 * (CGFloat(level) / 100.0))
                    Spacer(minLength: 0)
                }
                .padding(.leading, NotchConfiguration.batteryIconPadding)
                .padding(.vertical, NotchConfiguration.batteryIconPadding)
                .mask {
                    Image(systemName: "battery.100")
                        .font(.system(size: NotchConfiguration.batteryIconSize, weight: .light))
                }

                if isCharging {
                    HStack(spacing: 0) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: NotchConfiguration.batteryBoltIconSize, weight: .bold))
                        Text("\(level)")
                            .font(.system(size: NotchConfiguration.batteryValueFontSize, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(level > 10 ? contentColor : .white)
                } else {
                    Text("\(level)")
                        .font(.system(size: NotchConfiguration.batteryValueFontSize, weight: .medium, design: .rounded))
                        .foregroundColor(level > 10 ? contentColor : .white)
                }
            }
            .frame(width: NotchConfiguration.batteryFrameWidth, height: NotchConfiguration.batteryFrameHeight)
        }
    }
}
