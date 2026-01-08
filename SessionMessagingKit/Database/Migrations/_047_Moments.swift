// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

enum _047_Moments: Migration {
    static let identifier: String = "messagingKit.Moments"
    static let minExpectedRunDuration: TimeInterval = 0.1
    static var createdTables: [(FetchableRecord & TableRecord).Type] = [
        Moment.self
    ]
    
    static func migrate(_ db: ObservingDatabase, using dependencies: Dependencies) throws {
        // Create moment table
        try db.create(table: "moment") { t in
            t.column("id", .integer)
                .notNull()
                .primaryKey(autoincrement: true)
            t.column("authorId", .text)
                .notNull()
                .indexed()
                .references("profile", onDelete: .cascade)
            t.column("content", .text)
            t.column("imageAttachmentIds", .text)
            t.column("timestampMs", .integer)
                .notNull()
                .indexed()
        }
        
        MigrationExecution.updateProgress(1)
    }
}

