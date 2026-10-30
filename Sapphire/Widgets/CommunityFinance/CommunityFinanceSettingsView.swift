import SwiftUI

@MainActor
struct CommunityFinanceSettingsView: View {
    @EditingSettings private var settings: SettingsEditingSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Finance").font(.largeTitle.bold())
                Text("Follow your favorite stocks from TopLet.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show Stocks widget in the notch", isOn: $settings.settings.financeWidgetEnabled)
                    Toggle("Show selected stock as a live activity", isOn: $settings.settings.financeLiveActivityEnabled)
                    if settings.settings.financeLiveActivityEnabled {
                        Toggle("Only show during regular market hours", isOn: $settings.settings.financeLiveActivityActiveHoursOnly)
                    }
                }
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                CommunityFinanceBoardView(width: nil)
                Text("Choose a row to select the stock shown in the live activity. Add US symbols, Hong Kong symbols ending in .HK, or London symbols ending in .L. London GBp prices are in pence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }
}
