import AppKit
import EventKit
import SwiftUI

struct CalendarSourcesSettingsSection: View {
    @EnvironmentObject private var calendarService: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Calendar Sources", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                if calendarService.calendarAuthorization == .fullAccess {
                    Button {
                        calendarService.refreshSchedule(syncSources: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Calendars")
                    .accessibilityLabel("Refresh Calendars")
                }
            }
            Text("Show your iCloud, school, and subscribed calendars from the Mac Calendar app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch calendarService.calendarAuthorization {
            case .fullAccess:
                if let groups = calendarService.calendarSources {
                    if groups.isEmpty {
                        Text("Add your iCloud or school calendar in Apple Calendar first.")
                            .foregroundStyle(.secondary)
                        Button("Open Apple Calendar") { openCalendar() }
                    } else {
                        calendarPicker(groups: groups)
                    }
                } else {
                    ProgressView("Loading Calendars…").controlSize(.small)
                }
            case .notDetermined, .writeOnly:
                Button("Allow Calendar Access") {
                    PermissionsManager.shared.requestPermission(.calendar)
                }
                .buttonStyle(.borderedProminent)
            default:
                Text("Allow TopLet in System Settings → Privacy & Security → Calendars to show your schedule.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Calendar Privacy Settings") { SystemPreferencesPane.calendars.open() }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsContainerModifier())
        .onAppear { calendarService.refreshSchedule() }
    }

    private func calendarPicker(groups: [CalendarSourceGroup]) -> some View {
        let calendars = groups.flatMap(\.calendars)
        let selection = calendarService.selectedCalendarIdentifiers
        return VStack(alignment: .leading, spacing: 10) {
            Picker("Show Calendars", selection: Binding(
                get: { calendarService.selectedCalendarIdentifiers != nil },
                set: { choose in
                    calendarService.setSelectedCalendars(choose ? Set(calendars.filter(\.visibleInCalendar).map(\.id)) : nil)
                }
            )) {
                Text("Follow Apple Calendar").tag(false)
                Text("Choose Calendars").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selection != nil {
                HStack(spacing: 12) {
                    Button("Select All") { calendarService.setSelectedCalendars(Set(calendars.map(\.id))) }
                    Button("Deselect All") { calendarService.setSelectedCalendars([]) }
                }
                .buttonStyle(.link)
                if selection?.isDisjoint(with: calendars.map(\.id)) == true {
                    Text("No calendars selected. Select your timetable below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(groups) { group in
                Divider()
                Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(group.calendars) { calendar in
                    if selection == nil {
                        calendarLabel(calendar)
                            .foregroundStyle(calendar.visibleInCalendar ? .primary : .secondary)
                    } else {
                        Toggle(isOn: Binding(
                            get: { calendarService.selectedCalendarIdentifiers?.contains(calendar.id) == true },
                            set: { included in
                                var current = calendarService.selectedCalendarIdentifiers ?? []
                                if included { current.insert(calendar.id) } else { current.remove(calendar.id) }
                                calendarService.setSelectedCalendars(current)
                            }
                        )) { calendarLabel(calendar) }
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private func calendarLabel(_ calendar: CalendarSourceGroup.Entry) -> some View {
        Label {
            Text(calendar.title).lineLimit(1)
        } icon: {
            Circle()
                .fill(calendar.color.map(Color.init(nsColor:)) ?? .accentColor)
                .frame(width: 8, height: 8)
        }
        .help(calendar.title)
    }

    private func openCalendar() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.open(url)
    }
}
