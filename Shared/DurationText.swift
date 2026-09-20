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

enum DurationText {
    static func compact(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours) hours, \(minutes) minutes"
    }
}
