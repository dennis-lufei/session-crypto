// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct MomentComment: Codable, Sendable, Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "momentComment" }
    internal static let momentForeignKey = ForeignKey([Columns.momentId], to: [Moment.Columns.id])
    internal static let profileForeignKey = ForeignKey([Columns.authorId], to: [Profile.Columns.id])
    private static let moment = belongsTo(Moment.self, using: momentForeignKey)
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case momentId
        case authorId
        case content
        case timestampMs
    }
    
    /// Unique identifier for the comment
    public let id: Int64?
    
    /// The id for the moment this comment belongs to
    public let momentId: Int64
    
    /// The id for the user who wrote this comment
    public let authorId: String
    
    /// The text content of the comment
    public let content: String
    
    /// When the comment was created in milliseconds since epoch
    public let timestampMs: Int64
    
    // MARK: - Relationships
    
    public var moment: QueryInterfaceRequest<Moment> {
        request(for: MomentComment.moment)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: MomentComment.profile)
    }
    
    // MARK: - Initialization
    
    public init(
        id: Int64? = nil,
        momentId: Int64,
        authorId: String,
        content: String,
        timestampMs: Int64
    ) {
        self.id = id
        self.momentId = momentId
        self.authorId = authorId
        self.content = content
        self.timestampMs = timestampMs
    }
}

