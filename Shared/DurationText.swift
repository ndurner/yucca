import Foundation

enum DurationText {
    static func compact(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours) hours, \(minutes) minutes"
    }
}
