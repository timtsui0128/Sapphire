//
//  PublicBuildCompatibility.swift
//  Sapphire
//
// Shared value types used by public features whose private transport/UI is omitted.

#if !SAPPHIRE_FULL_BUILD
import Foundation
import OSLog

enum ContinuityBluetoothAddress {
    static func normalize(_ address: String?) -> String? {
        guard let address else { return nil }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits: String
        if trimmed.count == 12 && trimmed.utf8.allSatisfy(isHexDigit) {
            digits = trimmed
        } else {
            // CoreAudio Bluetooth UIDs can append a transport suffix to a MAC address.
            let pattern = #"(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])"#
            guard let range = trimmed.range(of: pattern, options: .regularExpression) else { return nil }
            digits = trimmed[range].filter { $0 != ":" && $0 != "-" }
        }
        let characters = Array(digits.uppercased())
        return stride(from: 0, to: characters.count, by: 2)
            .map { String(characters[$0...($0 + 1)]) }
            .joined(separator: ":")
    }

    static func dashed(_ address: String?) -> String? {
        normalize(address)?.replacingOccurrences(of: ":", with: "-")
    }

    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalize(lhs), let rhs = normalize(rhs) else { return false }
        return lhs == rhs
    }

    private static func isHexDigit(_ value: UInt8) -> Bool {
        (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value)
    }
}

enum ContinuityLog {
    private static let logger = Logger(subsystem: "com.cshariq.sapphire", category: "Earbuds")

    static func f(_ message: String) { logger.debug("\(message, privacy: .private)") }
    static func fErr(_ message: String) { logger.error("\(message, privacy: .private)") }
}

struct ContinuityEarbudCommand: Codable, Equatable, Sendable {
    let action: String
    var stringValue: String? = nil
    var boolValue: Bool? = nil
    var intValue: Int? = nil
}

struct ContinuityEarbudStatus: Codable, Equatable, Sendable {
    var vendor: String
    var name: String
    var address: String?
    var connected: Bool
    var ownedLocally: Bool
    var noiseMode: String
    var ancHigh: Bool
    var eqPreset: String
    var batteryLeft: Int
    var batteryRight: Int
    var batteryCase: Int
    var batteryMain: Int
    var dsee: Bool
    var seamless: Bool
    var detectConversations: Bool
    var ambientLevel: Int
    var supportsANC: Bool
    var supportsAdaptive: Bool
    var supportsEQ: Bool
    var supportsDSEE: Bool
    var supportsSeamless: Bool
    var supportsFind: Bool
    var supportsCustomEQ: Bool
    var customEQBands: [Int]
    var gamingMode: Bool
    var spatialAudio: Bool
    var touchpadLocked: Bool
    var touchLeft: Int
    var touchRight: Int
    var speakSeamlessly: Bool
    var ancOneEarbud: Bool
    var autoSwitchAudio: Bool
    var pauseOnOneBudRemoved: Bool
    var sidetone: Bool
    var extraHighAmbient: Bool
    var amplifyAmbient: Bool
    var inBandRingtone: Bool
    var callPathControl: Bool
    var ambientDuringCall: Bool
    var detectConversationsDuration: Int
    var outsideDoubleTap: Bool
    var muteLeft: Bool
    var muteRight: Bool
    var wearingLeft: Bool
    var wearingRight: Bool
    var fitTesting: Bool
    var fitLeftGood: Bool
    var fitRightGood: Bool
    var supportsGaming: Bool
    var supportsSpatial: Bool
    var supportsTouchLock: Bool
    var supportsFitTest: Bool
    var supportsAmbientExtras: Bool
    var supportsCallExtras: Bool
    var supportsDetectConversations: Bool
    var supportsExtraClearCall: Bool
    var supportsPassthrough: Bool
    var supportsOutsideDoubleTap: Bool
    var extraClearCall: Bool
    var passthrough: Bool
}

enum ContinuityMessageKind {
    case earbudCommand
    case earbudStatus
}

extension ContinuityPeer {
    func send<Payload: Encodable>(_ kind: ContinuityMessageKind, _ payload: Payload) {
        // The public Continuity manager has no connected peers or private transport.
        // Local Bluetooth controls still execute through the real earbud managers.
    }
}

/// Keeps the public storage model's real scan data without depending on its private map view.
struct StorageSpaceMapSnapshot: Sendable {
    let entries: [StorageEntry]
    let used: Int64
    let total: Int64
    let deepScanEnabled: Bool

    static func make(
        from entries: [StorageEntry],
        maximumItems: Int,
        used: Int64,
        total: Int64,
        deepScanEnabled: Bool,
        entriesSortedBySize: Bool
    ) -> StorageSpaceMapSnapshot {
        let ordered = entriesSortedBySize ? entries : entries.sorted { $0.size > $1.size }
        return StorageSpaceMapSnapshot(
            entries: Array(ordered.prefix(max(0, maximumItems))),
            used: max(0, used),
            total: max(0, total),
            deepScanEnabled: deepScanEnabled
        )
    }
}
#endif
