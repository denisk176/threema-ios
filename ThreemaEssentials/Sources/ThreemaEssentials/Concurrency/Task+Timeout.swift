//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2023-2025 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import Foundation

extension Task where Success == Never, Failure == Never {
    public enum TimeoutResult<Result: Sendable>: Sendable {
        case timeout
        case result(Result)
        case error(Error?)
    }
    
    public static func timeout<Output>(
        _ task: Task<Output, Error>,
        _ seconds: TimeInterval
    ) async throws -> TimeoutResult<Output> {
        try await withThrowingTaskGroup(of: TimeoutResult<Output>.self, body: { taskGroup -> TimeoutResult<Output> in
            defer { taskGroup.cancelAll() }
            
            taskGroup.addTask {
                try await .result(task.value)
            }
            taskGroup.addTask {
                try await Task.sleep(seconds: seconds)
                return .timeout
            }
            
            guard let firstResult = try await taskGroup.next() else {
                return .error(nil)
            }
            
            return firstResult
        })
    }
}
