// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Moment: Codable, Sendable, Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "moment" }
    internal static let profileForeignKey = ForeignKey([Columns.authorId], to: [Profile.Columns.id])
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case id
        case authorId
        case content
        case imageAttachmentIds
        case timestampMs
        case likeCount
        case commentCount
    }
    
    /// Unique identifier for the moment
    public let id: Int64?
    
    /// The id for the user who created this moment
    public let authorId: String
    
    /// The text content of the moment
    public let content: String?
    
    /// Comma-separated attachment IDs for images
    public let imageAttachmentIds: String?
    
    /// When the moment was created in milliseconds since epoch
    public let timestampMs: Int64
    
    /// Number of likes
    public let likeCount: Int64
    
    /// Number of comments
    public let commentCount: Int64
    
    // MARK: - Relationships
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: Moment.profile)
    }
    
    // MARK: - Initialization
    
    public init(
        id: Int64? = nil,
        authorId: String,
        content: String?,
        imageAttachmentIds: String?,
        timestampMs: Int64,
        likeCount: Int64 = 0,
        commentCount: Int64 = 0
    ) {
        self.id = id
        self.authorId = authorId
        self.content = content
        self.imageAttachmentIds = imageAttachmentIds
        self.timestampMs = timestampMs
        self.likeCount = likeCount
        self.commentCount = commentCount
    }
}

