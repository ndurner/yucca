// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Nils Durner
//
// This file is part of Yucca.
//
// Yucca is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Yucca is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Yucca. If not, see <https://www.gnu.org/licenses/>.

import Foundation

enum TimesheetMath {
    static func seconds(fromLuccaDuration value: String) -> TimeInterval {
        let dayAndTime = value.split(separator: ".", maxSplits: 1).map(String.init)
        let days: Double
        let time: String
        if dayAndTime.count == 2 {
            days = Double(dayAndTime[0]) ?? 0
            time = dayAndTime[1]
        } else {
            days = 0
            time = dayAndTime[0]
        }
        let parts = time.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return 0 }
        return days * 86_400 + parts[0] * 3_600 + parts[1] * 60 + parts[2]
    }

    static func luccaDuration(from seconds: TimeInterval) -> String {
        let total = max(0, min(Int(seconds.rounded(.down)), 86_400))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainder = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
    }

    static func weekInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        var isoCalendar = calendar
        isoCalendar.firstWeekday = 2
        isoCalendar.minimumDaysInFirstWeek = 4
        let start = isoCalendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? isoCalendar.startOfDay(for: date)
        return DateInterval(start: start, end: isoCalendar.date(byAdding: .day, value: 7, to: start)!)
    }

    static func activeEntry(
        in entries: [TimeEntry],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> TimeEntry? {
        entries
            .filter {
                $0.archivedAt == nil &&
                $0.durationSeconds == 0 &&
                $0.unit == 2 &&
                $0.startsAtDate(calendar: calendar).map { calendar.isDate($0, inSameDayAs: today) } == true
            }
            .max { lhs, rhs in
                (lhs.startsAtDate(calendar: calendar) ?? .distantPast) <
                (rhs.startsAtDate(calendar: calendar) ?? .distantPast)
            }
    }

    static func snapshot(
        entries: [TimeEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DashboardSnapshot {
        let week = weekInterval(containing: now, calendar: calendar)
        var todaySeconds: TimeInterval = 0
        var weekSeconds: TimeInterval = 0
        let active = activeEntry(in: entries, today: now, calendar: calendar)

        for entry in entries where entry.archivedAt == nil {
            guard let start = entry.startsAtDate(calendar: calendar), start <= now else { continue }
            var duration = entry.durationSeconds
            if entry.id == active?.id {
                duration = max(0, now.timeIntervalSince(start))
            }
            if calendar.isDate(start, inSameDayAs: now) { todaySeconds += duration }
            if week.contains(start) { weekSeconds += duration }
        }

        return DashboardSnapshot(
            todaySeconds: todaySeconds,
            weekSeconds: weekSeconds,
            isClockedIn: active != nil,
            activeStart: active?.startsAtDate(calendar: calendar),
            updatedAt: now
        )
    }
}
