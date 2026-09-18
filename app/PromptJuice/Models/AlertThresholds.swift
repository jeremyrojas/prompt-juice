import Foundation

enum LimitCadence: String, CaseIterable, Sendable {
    case fiveHour
    case weekly

    init(kind: LimitWindow.Kind) {
        self = kind.cadenceIsWeekly ? .weekly : .fiveHour
    }
}

struct AlertThresholds: Equatable {
    var remainingMinutes: Int
    var remainingPercent: Int

    static let `default` = AlertThresholds(
        remainingMinutes: 60,
        remainingPercent: 40
    )

    static let weeklyDefault = AlertThresholds(
        remainingMinutes: 1_440,
        remainingPercent: 40
    )
}
