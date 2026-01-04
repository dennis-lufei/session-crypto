// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct MomentLike: Codable, Sendable, Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "momentLike" }
    internal static let momentForeignKey = ForeignKey([Columns.momentId], to: [Moment.Columns.id])
    internal static let profileForeignKey = ForeignKey([Columns.authorId], to: [Profile.Columns.id])
    private static let moment = belongsTo(Moment.self, using: momentForeignKey)
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case momentId
        case authorId
        case timestampMs
    }
    
    /// The id for the moment this like belongs to
    public let momentId: Int64
    
    /// The id for the user who liked this moment
    public let authorId: String
    
    /// When the like was created in milliseconds since epoch
    public let timestampMs: Int64
    
    public var id: String {
        "\(momentId)_\(authorId)"
    }
    
    // MARK: - Relationships
    
    public var moment: QueryInterfaceRequest<Moment> {
        request(for: MomentLike.moment)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: MomentLike.profile)
    }
    
    // MARK: - Initialization
    
    public init(
        momentId: Int64,
        authorId: String,
        timestampMs: Int64
    ) {
        self.momentId = momentId
        self.authorId = authorId
        self.timestampMs = timestampMs
    }
}

