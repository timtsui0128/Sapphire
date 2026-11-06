//
//  CalendarDetailView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-
//

import SwiftUI
import EventKit

private struct Weekday: Identifiable {
    let id: Int
    let symbol: String
}

struct CalendarDetailView: View {
    @ObservedSettings var settings: SettingsObserver
    @EnvironmentObject private var calendarService: CalendarService
    @StateObject private var viewModel: InteractiveCalendarViewModel

    @State private var isMonthlyView: Bool = false
    @Namespace private var calendarAnimation

    init() {
        _viewModel = StateObject(wrappedValue: InteractiveCalendarViewModel())
    }

    init(viewModel: InteractiveCalendarViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var weekdayHeaders: [Weekday] {
        settings.settings.calendarStartOfWeek.weekdayHeaders.enumerated().map {
            Weekday(id: $0.offset, symbol: String($0.element.prefix(1)))
        }
    }

    private var combinedScheduleItems: [ScheduleItem] {
        ScheduleItem.agenda(events: calendarService.eventsForSelectedDate,
                            reminders: calendarService.remindersForSelectedDate,
                            showAllDayEvents: settings.settings.calendarShowAllDayEvents)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if isMonthlyView {
                monthlyGridView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 15)
            } else {
                modernWeeklyView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 15)
            }

            scheduleListView
                .padding(.horizontal, 20)
                .padding(.bottom, 15)
                .frame(maxHeight: isMonthlyView ? 0 : .infinity)
                .opacity(isMonthlyView ? 0 : 1)
        }
        .frame(width: 580, height: 320)
        .foregroundColor(.primary)
        .onAppear {
            viewModel.updateStartOfWeek(settings.settings.calendarStartOfWeek)
            calendarService.fetchEvents(for: viewModel.selectedDate)
            calendarService.fetchReminders(for: viewModel.selectedDate)
        }
        .onChange(of: viewModel.selectedDate) {
            calendarService.fetchEvents(for: viewModel.selectedDate)
            calendarService.fetchReminders(for: viewModel.selectedDate)
        }
        .onChange(of: settings.settings.calendarStartOfWeek) { _, startOfWeek in
            viewModel.updateStartOfWeek(startOfWeek)
        }
    }

    private var headerView: some View {
        let cal = viewModel.calendarStartOfWeek.configuredCalendar

        return HStack(alignment: .center) {
            HStack(spacing: 0) {
                Text(viewModel.selectedDate.format(as: "d"))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.selectedDate.format(as: "EEE").uppercased())
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .opacity(0.7)
                    Text(viewModel.selectedDate.format(as: "MMMM yyyy"))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .opacity(0.9)
                }
                .padding(.leading, 8)
            }

            Spacer()

            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isMonthlyView.toggle() }
                }) {
                    Image(systemName: isMonthlyView ? "calendar" : "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10)
                }
                Divider().frame(height: 14)
                Button(action: {
                    let amount = isMonthlyView ? -1 : -7
                    if let newDate = cal.date(byAdding: .day, value: amount, to: viewModel.selectedDate) {
                        withAnimation(.spring()) { viewModel.selectDate(newDate) }
                    }
                }) {
                    Image(systemName: "chevron.left").padding(.horizontal, 10)
                }
                Divider().frame(height: 14)
                Button(action: { withAnimation(.spring()) { viewModel.selectDate(Date()) } }) {
                    Text("Today").font(.system(size: 13, weight: .semibold, design: .rounded)).padding(.horizontal, 10)
                }
                Divider().frame(height: 14)
                Button(action: {
                    let amount = isMonthlyView ? 1 : 7
                    if let newDate = cal.date(byAdding: .day, value: amount, to: viewModel.selectedDate) {
                        withAnimation(.spring()) { viewModel.selectDate(newDate) }
                    }
                }) {
                    Image(systemName: "chevron.right").padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
            .buttonStyle(.plain)
        }
    }

    private var modernWeeklyView: some View {
        HStack {
            ForEach(viewModel.datesInWeek(for: viewModel.selectedDate), id: \.self) { date in
                let isSelected = date.isSameDay(as: viewModel.selectedDate)
                VStack(spacing: 6) {
                    Text(date.format(as: "EEE").uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .opacity(isSelected ? 1 : 0.5)

                    Text(date.format(as: "d"))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue)
                            .matchedGeometryEffect(id: "selected_day_background", in: calendarAnimation)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { viewModel.selectDate(date) }
                }
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private var monthlyGridView: some View {
        let gridColumns = Array(repeating: GridItem(.flexible()), count: 7)

        return VStack {
            HStack {
                ForEach(weekdayHeaders) { day in
                    Text(day.symbol)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .opacity(0.6)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(viewModel.monthGrid, id: \.id) { item in
                    let isSelected = item.date.isSameDay(as: viewModel.selectedDate)
                    Text(item.date.format(as: "d"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .opacity(item.isCurrentMonth ? 1.0 : 0.3)
                        .background {
                            if isSelected {
                                Circle()
                                    .fill(Color.blue)
                                    .matchedGeometryEffect(id: "selected_day_background", in: calendarAnimation)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                viewModel.selectDate(item.date)
                                isMonthlyView = false
                            }
                        }
                }
            }
        }
        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
    }

    private var scheduleListView: some View {
        let scheduleItems = combinedScheduleItems

        return VStack {
            if scheduleItems.isEmpty && calendarService.calendarAuthorization != .fullAccess {
                VStack(spacing: 8) {
                    Label("Calendar Access Needed", systemImage: "calendar.badge.exclamationmark")
                        .font(.headline)
                    if calendarService.calendarAuthorization == .notDetermined || calendarService.calendarAuthorization == .writeOnly {
                        Button("Allow Calendar Access") { PermissionsManager.shared.requestPermission(.calendar) }
                    } else {
                        Button("Open Calendar Privacy Settings") { SystemPreferencesPane.calendars.open() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scheduleItems.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.green)
                    VStack {
                        if calendarService.selectedCalendarIdentifiers?.isEmpty == true {
                            Text("No Calendars Selected").font(.title3.weight(.bold))
                            Text("Select your timetable in TopLet Settings → Calendar.").foregroundStyle(.secondary)
                        } else {
                            Text("All Clear").font(.title3.weight(.bold))
                            Text("You have no events or reminders scheduled.").foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(scheduleItems) { item in
                            DetailedScheduleItemRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

struct DetailedScheduleItemRow: View {
    let item: ScheduleItem

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(item.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    Image(systemName: item.type == .event ? "calendar" : "checklist")
                    if let calendarTitle = item.calendarTitle {
                        Text(calendarTitle)
                    } else {
                        Text(item.type == .event ? "Event" : "Reminder")
                    }
                    if let location = item.location, !location.isEmpty {
                        Text(verbatim: "·")
                        Text(location)
                    }
                }.font(.system(size: 11, weight: .medium)).opacity(0.6)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if item.hasTime {
                    HStack(spacing: 3) {
                        Text(item.date, style: .time)
                        if let end = item.endDate, end > item.date, end.isSameDay(as: item.date) {
                            Text(verbatim: "–")
                            Text(end, style: .time)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .fixedSize()
                } else {
                    Text("All-Day").font(.system(size: 13, weight: .semibold, design: .rounded)).opacity(0.8)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.08))
        .cornerRadius(8)
    }
}
