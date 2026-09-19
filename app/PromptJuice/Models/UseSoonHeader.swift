import AppKit
import Foundation

struct AlertingLimit: Equatable {
    let provider: UsageProvider
    let kind: LimitWindow.Kind
    let remainingPercent: Int
    let resetAt: Date
    let rowOrder: Int

    var shortLabel: String {
        switch kind {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        case .weeklyModel(let name): name
        case .other: kind.label.replacingOccurrences(of: " limit", with: "")
        }
    }
}

/// One sentence for every orange window, shared by the panel and notification.
struct UseSoonHeader: Equatable {
    let title: String
    let subtitle: String

    static func make(
        alerts: [AlertingLimit],
        now: Date,
        maxSubtitleWidth: CGFloat = 272
    ) -> UseSoonHeader? {
        guard !alerts.isEmpty else { return nil }
        let ranked = alerts.sorted { first, second in
            if first.resetAt != second.resetAt { return first.resetAt < second.resetAt }
            if first.remainingPercent != second.remainingPercent {
                return first.remainingPercent > second.remainingPercent
            }
            if first.provider.sortIndex != second.provider.sortIndex {
                return first.provider.sortIndex < second.provider.sortIndex
            }
            return first.rowOrder < second.rowOrder
        }

        if ranked.count == 1, let one = ranked.first {
            let name: String = switch one.kind {
            case .weeklyModel: one.shortLabel
            default: "\(one.provider.rawValue) \(one.shortLabel)"
            }
            return UseSoonHeader(
                title: "Use your \(name) juice",
                subtitle: "\(one.remainingPercent)% left · "
                    + ResetFormatter.text(until: one.resetAt, now: now)
            )
        }

        let providers = Set(ranked.map(\.provider))
        let title = providers.count == 1
            ? "Use your \(ranked[0].provider.rawValue) juice"
            : "Use your juice"

        var groups: [[AlertingLimit]] = []
        for alert in ranked {
            if let index = groups.firstIndex(where: { $0[0].resetAt == alert.resetAt }) {
                groups[index].append(alert)
            } else {
                groups.append([alert])
            }
        }

        func groupText(_ group: [AlertingLimit], forceProvider: Bool = false) -> String {
            let labels = group.sorted {
                if $0.provider.sortIndex != $1.provider.sortIndex {
                    return $0.provider.sortIndex < $1.provider.sortIndex
                }
                return $0.rowOrder < $1.rowOrder
            }.map { alert in
                (providers.count > 1 || forceProvider ? "\(alert.provider.rawValue) " : "")
                    + alert.shortLabel
            }
            let verb = group.count == 1 ? "resets" : "reset"
            return "\(labels.joined(separator: " & ")) \(verb) in "
                + ResetFormatter.duration(until: group[0].resetAt, now: now)
        }

        let enumeration = groups.map { groupText($0) }.joined(separator: " · ")
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let width = (enumeration as NSString).size(withAttributes: [.font: font]).width
        var subtitle = if groups.count > 2 || width > maxSubtitleWidth {
            "\(ranked.count) limits reset soon · \(groupText(groups[0], forceProvider: true))"
        } else {
            enumeration
        }
        if (subtitle as NSString).size(withAttributes: [.font: font]).width > maxSubtitleWidth {
            subtitle = "\(ranked.count) limits reset soon · "
                + groupText([ranked[0]], forceProvider: true)
        }
        return UseSoonHeader(title: title, subtitle: subtitle)
    }
}
