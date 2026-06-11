import Foundation

struct AlertThresholds: Equatable {
    var remainingMinutes: Int
    var remainingPercent: Int

    static let `default` = AlertThresholds(
        remainingMinutes: 60,
        remainingPercent: 40
    )
}
