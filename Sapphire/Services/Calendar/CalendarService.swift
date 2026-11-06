//
//  CalendarService.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-06-28.
//

import Foundation
import EventKit
import AppKit
import Combine

struct CalendarSourceGroup: Identifiable, Equatable {
    struct Entry: Identifiable, Equatable {
        let id: String
        let title: String
        let color: NSColor?
        let visibleInCalendar: Bool
    }

    let id: String
    let title: String
    let calendars: [Entry]
}

class CalendarService: ObservableObject {
    private let eventStore = SharedEventStore.store
    private static let selectionKey = "TopLetSelectedCalendarIdentifiers"

    @Published private(set) var calendarAuthorization = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var calendarSources: [CalendarSourceGroup]?
    @Published private(set) var selectedCalendarIdentifiers: Set<String>? =
        UserDefaults.standard.stringArray(forKey: CalendarService.selectionKey).map { Set($0) }

    @Published var eventsForSelectedDate: [EKEvent] = []
    @Published var remindersForSelectedDate: [EKReminder] = []

    @Published var upcomingEvents: [EKEvent] = []
    @Published var upcomingReminders: [EKReminder] = []

    private var currentlyTrackedDate: Date = Date()

    private let workQueue = DispatchQueue(label: "com.sapphire.calendarQueue", qos: .userInitiated)
    private var selectedEventsGeneration = 0
    private var upcomingEventsGeneration = 0
    private var selectedRemindersGeneration = 0
    private var upcomingRemindersGeneration = 0
    private var sourcesGeneration = 0
    private var eventStoreRefreshWorkItem: DispatchWorkItem?
    private var boundaryTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventStoreChanged),
            name: .EKEventStoreChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(timeContextChanged),
                name: name,
                object: nil
            )
        }
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.timeContextChanged()
        })
        DispatchQueue.main.async { [weak self] in self?.refreshSchedule() }
    }

    deinit {
        eventStoreRefreshWorkItem?.cancel()
        boundaryTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    @objc private func timeContextChanged() {
        eventStoreChanged()
    }

    private func scheduleBoundaryRefresh(for events: [EKEvent]) {
        dispatchPrecondition(condition: .onQueue(.main))
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        let now = Date()
        let intervals = events.compactMap { event -> (start: Date, end: Date)? in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            return (start, end)
        }
        let boundary = CalendarSchedule.nextRefreshBoundary(now: now, events: intervals)
        let delay = max(1, boundary.timeIntervalSince(now) + 1)
        boundaryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.boundaryTimer = nil
            self.fetchEvents(for: self.currentlyTrackedDate)
            self.fetchAllUpcomingEvents()
            self.fetchAllUpcomingReminders()
        }
        boundaryTimer?.tolerance = min(5, delay * 0.05)
    }

    func setSelectedCalendars(_ identifiers: Set<String>?) {
        guard selectedCalendarIdentifiers != identifiers else { return }
        selectedCalendarIdentifiers = identifiers
        if let identifiers {
            UserDefaults.standard.set(identifiers.sorted(), forKey: Self.selectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectionKey)
        }
        // Don't keep displaying a just-hidden calendar while its new query runs.
        eventsForSelectedDate = []
        upcomingEvents = []
        fetchEvents(for: currentlyTrackedDate)
        fetchAllUpcomingEvents()
    }

    func refreshSchedule(syncSources: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refreshSchedule(syncSources: syncSources) }
            return
        }
        let authorization = EKEventStore.authorizationStatus(for: .event)
        if calendarAuthorization != authorization { calendarAuthorization = authorization }
        sourcesGeneration &+= 1
        let generation = sourcesGeneration
        if authorization == .fullAccess {
            workQueue.async { [weak self] in
                guard let self else { return }
                if syncSources { self.eventStore.refreshSourcesIfNecessary() }
                let sources = self.readCalendarSources()
                DispatchQueue.main.async {
                    guard self.sourcesGeneration == generation else { return }
                    if self.calendarSources != sources { self.calendarSources = sources }
                }
            }
        } else if calendarSources != nil {
            calendarSources = nil
        }
        fetchEvents(for: currentlyTrackedDate)
        fetchAllUpcomingEvents()
        fetchReminders(for: currentlyTrackedDate)
        fetchAllUpcomingReminders()
    }

    @objc private func eventStoreChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.eventStoreRefreshWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.refreshSchedule()
            }
            self.eventStoreRefreshWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        }
    }

    @objc private func applicationDidBecomeActive() {
        refreshSchedule()
    }

    private func calendarPreferences() -> [String: Any]? {
        UserDefaults.standard.persistentDomain(
            forName: CalendarVisibilityFilter.calendarPreferencesDomain
        )
    }

    private func readCalendarSources() -> [CalendarSourceGroup] {
        let preferences = calendarPreferences()
        let groups = Dictionary(grouping: eventStore.calendars(for: .event)) { $0.source.sourceIdentifier }
        return groups.compactMap { id, calendars -> CalendarSourceGroup? in
            guard let source = calendars.first?.source else { return nil }
            let entries = calendars.map { calendar in
                CalendarSourceGroup.Entry(
                    id: calendar.calendarIdentifier, title: calendar.title, color: calendar.color,
                    visibleInCalendar: CalendarVisibilityFilter.isVisible(
                        calendarIdentifier: calendar.calendarIdentifier, calendarPreferences: preferences
                    )
                )
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return CalendarSourceGroup(id: id, title: source.title, calendars: entries)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func visibleEventCalendars(selection: Set<String>?) -> [EKCalendar] {
        let preferences = calendarPreferences()
        return eventStore.calendars(for: .event).filter {
            CalendarVisibilityFilter.isVisible(
                calendarIdentifier: $0.calendarIdentifier,
                calendarPreferences: preferences,
                selectedIdentifiers: selection
            )
        }
    }

    func fetchEvents(for date: Date) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchEvents(for: date) }
            return
        }

        self.currentlyTrackedDate = date
        selectedEventsGeneration &+= 1
        let generation = selectedEventsGeneration
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            if !eventsForSelectedDate.isEmpty { eventsForSelectedDate = [] }
            return
        }
        let selection = selectedCalendarIdentifiers

        workQueue.async { [weak self] in
            guard let self = self else { return }

            let calendars = self.visibleEventCalendars(selection: selection)
            let calendar = Calendar.current
            let startDate = calendar.startOfDay(for: date)
            guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { return }

            let fetchedEvents = self.events(from: startDate, to: endDate, calendars: calendars)
                .sorted {
                    if $0.isAllDay && !$1.isAllDay {
                        return true
                    }
                    if !$0.isAllDay && $1.isAllDay {
                        return false
                    }
                    return $0.startDate < $1.startDate
                }

            DispatchQueue.main.async {
                guard self.selectedEventsGeneration == generation else { return }
                self.eventsForSelectedDate = fetchedEvents
            }
        }
    }

    private func fetchAllUpcomingEvents() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchAllUpcomingEvents() }
            return
        }

        upcomingEventsGeneration &+= 1
        let generation = upcomingEventsGeneration
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            if !upcomingEvents.isEmpty { upcomingEvents = [] }
            boundaryTimer?.invalidate()
            boundaryTimer = nil
            return
        }
        let selection = selectedCalendarIdentifiers
        workQueue.async { [weak self] in
            guard let self = self else { return }

            let calendars = self.visibleEventCalendars(selection: selection)
            let now = Date()
            guard let twoDaysFromNow = Calendar.current.date(byAdding: .hour, value: 48, to: now) else { return }

            let fetchedEvents = self.events(from: now, to: twoDaysFromNow, calendars: calendars)
                .filter { !$0.isAllDay }
                .sorted { $0.startDate < $1.startDate }

            DispatchQueue.main.async {
                guard self.upcomingEventsGeneration == generation else { return }
                self.upcomingEvents = fetchedEvents
                self.scheduleBoundaryRefresh(for: fetchedEvents)
            }
        }
    }

    private func events(from start: Date, to end: Date, calendars: [EKCalendar]) -> [EKEvent] {
        guard !calendars.isEmpty, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return eventStore.events(matching: eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars))
    }

    func fetchReminders(for date: Date) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchReminders(for: date) }
            return
        }

        currentlyTrackedDate = date
        selectedRemindersGeneration &+= 1
        let generation = selectedRemindersGeneration
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            if !remindersForSelectedDate.isEmpty { remindersForSelectedDate = [] }
            return
        }
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { return }

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: startDate, ending: endDate, calendars: nil)

        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let self = self else { return }

            self.workQueue.async {
                let sortedReminders = reminders?.sorted(by: {
                    let date1 = $0.dueDateComponents?.date ?? .distantFuture
                    let date2 = $1.dueDateComponents?.date ?? .distantFuture
                    return date1 < date2
                }) ?? []

                DispatchQueue.main.async {
                    guard self.selectedRemindersGeneration == generation else { return }
                    self.remindersForSelectedDate = sortedReminders
                }
            }
        }
    }

    private func fetchAllUpcomingReminders() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.fetchAllUpcomingReminders() }
            return
        }

        upcomingRemindersGeneration &+= 1
        let generation = upcomingRemindersGeneration
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            if !upcomingReminders.isEmpty { upcomingReminders = [] }
            return
        }
        let now = Date()
        guard let twoDaysFromNow = Calendar.current.date(byAdding: .hour, value: 48, to: now) else { return }

        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: now, ending: twoDaysFromNow, calendars: nil)

        eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
            guard let self = self else { return }

            self.workQueue.async {
                let sortedReminders = reminders?.sorted(by: {
                    let date1 = $0.dueDateComponents?.date ?? .distantFuture
                    let date2 = $1.dueDateComponents?.date ?? .distantFuture
                    return date1 < date2
                }) ?? []

                DispatchQueue.main.async {
                    guard self.upcomingRemindersGeneration == generation else { return }
                    self.upcomingReminders = sortedReminders
                }
            }
        }
    }
}
