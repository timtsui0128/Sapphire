//
//  CalendarWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-27.
//

import SwiftUI
import EventKit

struct ScheduleItem: Identifiable {
    enum ItemType { case event, reminder }

    let id: String
    let type: ItemType
    let title: String
    let date: Date
    let color: Color
    let hasTime: Bool
    let endDate: Date?
    let calendarTitle: String?
    let location: String?

    init?(event: EKEvent) {
        guard let title = event.title, !title.isEmpty, let start = event.startDate else { return nil }
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        id = "event:\(identifier):\(start.timeIntervalSinceReferenceDate)"
        type = .event
        self.title = title
        date = start
        color = (event.calendar?.color).map(Color.init(nsColor:)) ?? .accentColor
        hasTime = !event.isAllDay
        endDate = event.endDate
        calendarTitle = event.calendar?.title
        location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(reminder: EKReminder) {
        guard let title = reminder.title, !title.isEmpty,
              let components = reminder.dueDateComponents,
              let dueDate = Calendar.current.date(from: components) else { return nil }
        id = "reminder:\(reminder.calendarItemIdentifier)"
        type = .reminder
        self.title = title
        date = dueDate
        color = (reminder.calendar?.color).map(Color.init(nsColor:)) ?? .accentColor
        hasTime = components.hour != nil && components.minute != nil
        endDate = nil
        calendarTitle = nil
        location = nil
    }

    static func agenda(events: [EKEvent], reminders: [EKReminder], showAllDayEvents: Bool) -> [Self] {
        (events.filter { showAllDayEvents || !$0.isAllDay }.compactMap(Self.init(event:))
            + reminders.compactMap(Self.init(reminder:)))
            .sorted { $0.date < $1.date }
    }
}

struct CalendarWidgetView: View {
    @Environment(\.navigationStack) var navigationStack
    @ObservedObject var viewModel: InteractiveCalendarViewModel
    @EnvironmentObject var calendarService: CalendarService
    @ObservedSettings var settings: SettingsObserver

    @State private var hasScrolledInitially = false
    @State private var centeredDate: Date?

    private var combinedScheduleItems: [ScheduleItem] {
        ScheduleItem.agenda(events: calendarService.eventsForSelectedDate,
                            reminders: calendarService.remindersForSelectedDate,
                            showAllDayEvents: settings.settings.calendarShowAllDayEvents)
    }

    init(viewModel: InteractiveCalendarViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 10) {
                Text(viewModel.selectedMonthAbbreviated)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 55, alignment: .leading)
                    .padding(.top, 2)
                    .id("Month-\(viewModel.selectedMonthAbbreviated)")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -10)),
                        removal: .opacity.combined(with: .offset(y: 10))
                    ))

                interactiveCalendar()
            }

            scheduleView
        }
        .padding(.top, 10)
        .frame(width: 240, height: 100)
        .foregroundColor(.primary)
        .environmentObject(viewModel)
        .onChange(of: viewModel.selectedDate) {
            calendarService.fetchEvents(for: viewModel.selectedDate)
            calendarService.fetchReminders(for: viewModel.selectedDate)
        }
        .onAppear {
            viewModel.updateStartOfWeek(settings.settings.calendarStartOfWeek)
            calendarService.fetchEvents(for: viewModel.selectedDate)
            calendarService.fetchReminders(for: viewModel.selectedDate)
        }
        .onChange(of: settings.settings.calendarStartOfWeek) { _, startOfWeek in
            viewModel.updateStartOfWeek(startOfWeek)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                navigationStack.wrappedValue.append(.calendarPlayer)
            }
        }
    }

    private func interactiveCalendar() -> some View {
        GeometryReader { containerProxy in
            let itemWidth: CGFloat = 28
            let itemSpacing: CGFloat = 10
            let horizontalPadding = (containerProxy.size.width / 2) - (itemWidth / 2)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: itemSpacing) {
                    ForEach(viewModel.dates, id: \.self) { date in
                        DynamicDayView(
                            date: date,
                            containerWidth: containerProxy.size.width
                        )
                        .id(date)
                        .onTapGesture {
                            HapticManager.shared.perform(HapticFeedbackType.medium)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                viewModel.selectDate(date)
                                centeredDate = date
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, horizontalPadding)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centeredDate, anchor: .center)
            .onAppear {
                DispatchQueue.main.async {
                    centeredDate = viewModel.today
                    hasScrolledInitially = true
                }
            }
            .onChange(of: centeredDate) { _, newDate in
                guard hasScrolledInitially, let newDate,
                      !newDate.isSameDay(as: viewModel.selectedDate) else { return }
                HapticManager.shared.perform(HapticFeedbackType.weak)
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.selectDate(newDate)
                }
            }
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var scheduleView: some View {
        let now = Date()
        let upcomingItems = combinedScheduleItems.filter { item in
            if Calendar.current.isDateInToday(viewModel.selectedDate) {
                return !item.hasTime || (item.endDate ?? item.date) > now
            }
            return true
        }

        if upcomingItems.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Text(LocalizedStringKey(calendarService.calendarAuthorization != .fullAccess ? "Calendar Access Needed"
                    : calendarService.selectedCalendarIdentifiers?.isEmpty == true ? "No Calendars Selected"
                    : Calendar.current.isDateInToday(viewModel.selectedDate) ? "No more items today" : "No items scheduled"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            let scrollView = ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(upcomingItems) { item in
                        ScheduleItemRowView(item: item)
                    }
                }
            }

            if upcomingItems.count >= 3 {
                scrollView
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.8),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                scrollView
            }
        }
    }
}

struct ScheduleItemRowView: View {
    let item: ScheduleItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.type == .event ? "circle.fill" : "circle")
                .font(.system(size: 6))
                .foregroundColor(item.color)
            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer()
            if item.hasTime {
                Text(item.date, style: .time)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                Text("All-Day")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DynamicDayView: View {
    let date: Date
    let containerWidth: CGFloat

    @EnvironmentObject private var viewModel: InteractiveCalendarViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isSelected = date.isSameDay(as: viewModel.selectedDate)
        let dayName = date.format(as: isSelected ? "EEE" : "EEEEE").uppercased()
        let numberBase = opaque(date.isWeekend ? Color.red.opacity(0.8) : Color.primary.opacity(0.8))
        let letterBase = opaque(.gray)
        let focus = opaque(.blue)
        let centerX = containerWidth / 2

        VStack(spacing: 3) {
            tinted(Text(dayName).font(.system(size: 10, weight: .semibold, design: .rounded)),
                   base: letterBase, focus: focus, centerX: centerX)
                .id(dayName)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 10).combined(with: .opacity),
                        removal: .offset(y: -10).combined(with: .opacity)
                    )
                )

            tinted(Text(date.format(as: "d")).font(.system(size: 13, weight: .bold, design: .rounded)),
                   base: numberBase, focus: focus, centerX: centerX)
        }
        .visualEffect { content, proxy in
            let factor = Self.focusFactor(proxy, centerX: centerX)
            return content
                .scaleEffect(0.7 + factor * 0.7)
                .opacity(0.5 + factor * 0.5)
        }
        .frame(width: 28)
        .frame(maxHeight: .infinity)
    }

    private func tinted(_ text: Text, base: Color, focus: Color, centerX: CGFloat) -> some View {
        text.foregroundColor(base)
            .overlay {
                text.foregroundColor(focus)
                    .visualEffect { content, proxy in
                        content.opacity(Self.focusFactor(proxy, centerX: centerX))
                    }
            }
    }

    private func opaque(_ color: Color) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        let resolved = color.resolve(in: environment)
        return Color(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
    }

    private static func focusFactor(_ proxy: GeometryProxy, centerX: CGFloat) -> CGFloat {
        let distance = proxy.frame(in: .scrollView(axis: .horizontal)).midX - centerX
        return max(0, 1 - (abs(distance) / 80))
    }

}
