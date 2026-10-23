import SwiftUI

@MainActor
struct F1LiveTimingPanel: View {
    @ObservedObject private var store: F1LiveTimingStore

    init(store: F1LiveTimingStore? = nil) {
        _store = ObservedObject(wrappedValue: store ?? .shared)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("F1 timing", systemImage: "flag.checkered").font(.headline)
                Spacer()
                if store.isLoading { ProgressView().controlSize(.mini) }
                Button { Task { await store.refresh(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.isLoading)
                .accessibilityLabel("Refresh Formula 1 timing")
            }
            if let snapshot = store.snapshot {
                timing(snapshot)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "flag.checkered").font(.title)
                    Text(store.isLoading ? "Loading the race weekend…" : "No timing available.")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 140)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("ESPN · latest reported timing").font(.caption2).foregroundStyle(.secondary)
        }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func timing(_ snapshot: F1LiveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.title).font(.subheadline.weight(.semibold))
            HStack {
                Text(snapshot.sessionTitle).font(.caption)
                Text(snapshot.isStale ? "Connection lost · saved timing" : snapshot.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isLive && !snapshot.isStale ? Color.green : Color.secondary)
                Spacer(minLength: 4)
                Text(Self.lapText(snapshot.lap, total: snapshot.totalLaps))
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            if snapshot.drivers.isEmpty {
                Text("The starting list and positions will appear when the provider publishes them.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                HStack {
                    Text("POS").frame(width: 28, alignment: .leading)
                    Text("DRIVER").frame(maxWidth: .infinity, alignment: .leading)
                    Text("LAPS").frame(width: 40, alignment: .trailing)
                }
                .font(.caption2).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.drivers) { driver in
                            driverRow(driver)
                            Divider().opacity(0.45)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
            HStack {
                Text("Received \(snapshot.fetchedAt, style: .time)")
                Spacer()
                if let url = snapshot.sourceURL { Link("Race details", destination: url) }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func driverRow(_ driver: F1LiveDriver) -> some View {
        HStack(spacing: 7) {
            Text(driver.position.map(String.init) ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(driver.name).font(.caption.weight(.semibold)).lineLimit(1)
                if let constructor = driver.constructorName {
                    Text(constructor).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if driver.isRetired {
                Text("OUT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Button { store.toggleFavorite(driver: driver) } label: {
                Image(systemName: store.favoriteDriverIDs.contains(driver.id) ? "star.fill" : "star")
                    .foregroundStyle(store.favoriteDriverIDs.contains(driver.id) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Follow \(driver.name)")
            .accessibilityLabel("\(store.favoriteDriverIDs.contains(driver.id) ? "Unfollow" : "Follow") \(driver.name)")
            Text(driver.laps.map(String.init) ?? "—")
                .font(.caption.monospacedDigit()).frame(width: 33, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .background(store.isFavorite(driver: driver) ? Color.accentColor.opacity(0.08) : .clear)
    }

    static func lapText(_ lap: Int?, total: Int?) -> String {
        let current = lap.map(String.init) ?? "—"
        return total.map { "Lap \(current) / \($0)" } ?? "Lap \(current)"
    }
}

@MainActor
struct F1FollowSettingsView: View {
    @ObservedObject private var store = F1LiveTimingStore.shared
    @AppStorage("F1NotchFocusedDriverID") private var focusedDriver = ""

    private struct Constructor: Identifiable {
        let id: String
        let name: String
    }

    private var constructors: [Constructor] {
        var values: [String: String] = [:]
        for driver in store.availableDrivers {
            if let id = driver.constructorID, let name = driver.constructorName { values[id] = name }
        }
        return values.map { Constructor(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Formula 1 in the notch").font(.headline)
            Toggle("Show live positions and lap count", isOn: $store.isNotchEnabled)
            Picker("Driver in the notch", selection: $focusedDriver) {
                Text("Automatic · followed driver or race leader").tag("")
                ForEach(store.availableDrivers) { driver in
                    Text(driver.name).tag(driver.id)
                }
            }
            .pickerStyle(.menu)
            Text("Follow drivers and constructors. During a live session, the collapsed notch shows the lap count and selected driver's position; click it for the full standings.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.availableDrivers.isEmpty {
                Text("Loading the entry list…").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Drivers").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)]) {
                    ForEach(store.availableDrivers) { driver in
                        followButton(driver.name, selected: store.favoriteDriverIDs.contains(driver.id)) {
                            store.toggleFavorite(driver: driver)
                        }
                    }
                }
                Text("Constructors").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)]) {
                    ForEach(constructors) { constructor in
                        followButton(constructor.name, selected: store.favoriteConstructorIDs.contains(constructor.id)) {
                            store.toggleFavoriteConstructor(id: constructor.id)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .task { await store.refresh() }
    }

    private func followButton(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name).font(.caption).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: selected ? "star.fill" : "star")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(selected ? "Unfollow" : "Follow") \(name)")
    }
}
