//
//  CalendarVisibilityFilter.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

import Foundation

enum CalendarVisibilityFilter {
    static let calendarPreferencesDomain = "com.apple.iCal"

    static func isVisible(
        calendarIdentifier: String,
        calendarPreferences: [String: Any]?,
        selectedIdentifiers: Set<String>? = nil
    ) -> Bool {
        // nil follows Apple Calendar; an explicit empty set displays no events.
        if let selectedIdentifiers { return selectedIdentifiers.contains(calendarIdentifier) }
        guard let disabledCalendars = calendarPreferences?["DisabledCalendars"] as? [String: Any],
              let disabledIdentifiers = disabledCalendars["MainWindow"] as? [String] else {
            return true
        }

        return !disabledIdentifiers.contains(calendarIdentifier)
    }
}
