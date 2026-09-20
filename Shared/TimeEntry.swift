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

struct TimeEntry: Codable, Identifiable, Equatable, Sendable {
    let id: Int
    let ownerId: Int
    let unit: Int
    let startsAt: String
    let duration: String
    let endsAt: String?
    let archivedAt: String?
    let creationSource: Int?

    var durationSeconds: TimeInterval {
        TimesheetMath.seconds(fromLuccaDuration: duration)
    }

    func startsAtDate(calendar: Calendar = .current) -> Date? {
        LuccaDateCodec.date(from: startsAt, calendar: calendar)
    }
}

struct LuccaUser: Codable, Equatable, Sendable {
    let id: Int
    let firstName: String?
    let lastName: String?

    var displayName: String {
        [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct DashboardSnapshot: Codable, Equatable, Sendable {
    var todaySeconds: TimeInterval
    var weekSeconds: TimeInterval
    var isClockedIn: Bool
    var activeStart: Date?
    var updatedAt: Date

    static let empty = DashboardSnapshot(
        todaySeconds: 0,
        weekSeconds: 0,
        isClockedIn: false,
        activeStart: nil,
        updatedAt: .now
    )
}

enum LuccaDateCodec {
    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    static func date(from value: String, calendar: Calendar = .current) -> Date? {
        let base = String(value.prefix(19))
        let scanner = Scanner(string: base)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "-T:")
        var year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0
        guard scanner.scanInt(&year), scanner.scanInt(&month), scanner.scanInt(&day),
              scanner.scanInt(&hour), scanner.scanInt(&minute), scanner.scanInt(&second)
        else { return nil }
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        ))
    }
}

