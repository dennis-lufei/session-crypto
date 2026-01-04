// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import SessionMessagingKit
import SessionUtilitiesKit

public class MomentsViewModel: ObservableObject {
    public let dependencies: Dependencies
    private let userSessionId: SessionId
    private var observationCancellable: DatabaseCancellable?
    
    @Published public var moments: [MomentWithProfile] = []
    @Published public var isLoading: Bool = true
    
    public struct MomentWithProfile: Identifiable, Hashable {
        public let moment: Moment
        public let profile: Profile
        public let isLikedByCurrentUser: Bool
        public let likes: [MomentLikeWithProfile]
        public let comments: [MomentCommentWithProfile]
        public let imageAttachmentIds: [String]
        
        public var id: Int64 { moment.id ?? -1 }
        
        public init(
            moment: Moment,
            profile: Profile,
            isLikedByCurrentUser: Bool,
            likes: [MomentLikeWithProfile],
            comments: [MomentCommentWithProfile],
            imageAttachmentIds: [String]
        ) {
            self.moment = moment
            self.profile = profile
            self.isLikedByCurrentUser = isLikedByCurrentUser
            self.likes = likes
            self.comments = comments
            self.imageAttachmentIds = imageAttachmentIds
        }
    }
    
    public struct MomentLikeWithProfile: Identifiable, Hashable {
        public let like: MomentLike
        public let profile: Profile
        
        public var id: String { like.id }
        
        public init(like: MomentLike, profile: Profile) {
            self.like = like
            self.profile = profile
        }
    }
    
    public struct MomentCommentWithProfile: Identifiable, Hashable {
        public let comment: MomentComment
        public let profile: Profile
        
        public var id: Int64 { comment.id ?? -1 }
        
        public init(comment: MomentComment, profile: Profile) {
            self.comment = comment
            self.profile = profile
        }
    }
    
    // MARK: - Initialization
    
    public init(using dependencies: Dependencies) {
        self.dependencies = dependencies
        self.userSessionId = dependencies[cache: .general].sessionId
        
        observeMoments()
    }
    
    // MARK: - Observation
    
    private func observeMoments() {
        let observation = ValueObservation.trackingConstantRegion { [userSessionId, dependencies] db -> [MomentWithProfile] in
            let currentUserId = userSessionId.hexString
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            
            // Get approved contacts (friends) - all contacts we've added (isApproved = true)
            let friendIds = try Contact
                .filter(contact[.isApproved] == true)
                .filter(contact[.isBlocked] == false)
                .select(.id)
                .asRequest(of: String.self)
                .fetchAll(db)
            
            // Also include contacts who have sent us moments (even if not explicitly approved)
            // This ensures we show moments from contacts who have sent us messages
            let momentAuthorIds = try Moment
                .select(Moment.Columns.authorId)
                .distinct()
                .asRequest(of: String.self)
                .fetchAll(db)
            
            // Include current user's moments as well
            let allowedAuthorIds = Set(friendIds + momentAuthorIds + [currentUserId])
            
            // Fetch moments from friends and current user only
            let moments: [Moment] = try Moment
                .filter(allowedAuthorIds.contains(Moment.Columns.authorId))
                .order(Moment.Columns.timestampMs.desc)
                .fetchAll(db)
            
            var result: [MomentWithProfile] = []
            
            for moment in moments {
                // Fetch profile
                guard let profile: Profile = try? Profile
                    .filter(Profile.Columns.id == moment.authorId)
                    .fetchOne(db)
                else { continue }
                
                // Check if current user liked this moment
                let likeCount = (try? MomentLike
                    .filter(MomentLike.Columns.momentId == (moment.id ?? -1))
                    .filter(MomentLike.Columns.authorId == currentUserId)
                    .fetchCount(db)) ?? 0
                let isLikedByCurrentUser = likeCount > 0
                
                // Fetch likes with profiles
                let likes: [MomentLike] = try MomentLike
                    .filter(MomentLike.Columns.momentId == (moment.id ?? -1))
                    .order(MomentLike.Columns.timestampMs.asc)
                    .fetchAll(db)
                
                let likesWithProfiles: [MomentLikeWithProfile] = try likes.compactMap { like in
                    guard let likeProfile: Profile = try? Profile
                        .filter(Profile.Columns.id == like.authorId)
                        .fetchOne(db)
                    else { return nil }
                    return MomentLikeWithProfile(like: like, profile: likeProfile)
                }
                
                // Fetch comments with profiles
                let comments: [MomentComment] = try MomentComment
                    .filter(MomentComment.Columns.momentId == (moment.id ?? -1))
                    .order(MomentComment.Columns.timestampMs.asc)
                    .fetchAll(db)
                
                let commentsWithProfiles: [MomentCommentWithProfile] = try comments.compactMap { comment in
                    guard let commentProfile: Profile = try? Profile
                        .filter(Profile.Columns.id == comment.authorId)
                        .fetchOne(db)
                    else { return nil }
                    return MomentCommentWithProfile(comment: comment, profile: commentProfile)
                }
                
                // Parse image attachment IDs
                let imageAttachmentIds: [String] = (moment.imageAttachmentIds ?? "")
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                result.append(MomentWithProfile(
                    moment: moment,
                    profile: profile,
                    isLikedByCurrentUser: isLikedByCurrentUser,
                    likes: likesWithProfiles,
                    comments: commentsWithProfiles,
                    imageAttachmentIds: imageAttachmentIds
                ))
            }
            
            return result
        }
        
        observationCancellable = dependencies[singleton: .storage].start(
            observation,
            scheduling: .async(onQueue: .main),
            onError: { error in
                Log.error("[MomentsViewModel] Observation failed: \(error)")
            },
            onChange: { [weak self] moments in
                self?.moments = moments
                self?.isLoading = false
            }
        )
    }
    
    // MARK: - Actions
    
    public func createMoment(content: String?, imageAttachmentIds: [String]) throws {
        let currentUserId = userSessionId.hexString
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        let attachmentIdsString = imageAttachmentIds.isEmpty ? nil : imageAttachmentIds.joined(separator: ",")
        
        // Save to local database first
        try dependencies[singleton: .storage].write { db in
            var moment = Moment(
                authorId: currentUserId,
                content: content,
                imageAttachmentIds: attachmentIdsString,
                timestampMs: timestampMs
            )
            
            try moment.insert(db)
        }
        
        // Send to all approved contacts
        try self.dependencies[singleton: .storage].write { db in
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            
            // Get all approved contacts (excluding current user)
            let contactIds = try Contact
                .filter(contact[.isApproved] == true)
                .filter(contact[.isBlocked] == false)
                .filter(contact[.id] != currentUserId)
                .select(.id)
                .asRequest(of: String.self)
                .fetchAll(db)
            
            // Create JSON data for moment
            let momentData: [String: Any] = [
                "content": content ?? NSNull(),
                "imageAttachmentIds": attachmentIdsString ?? NSNull(),
                "timestampMs": timestampMs
            ]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: momentData),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            
            let momentText = "__MOMENT__:\(jsonString)"
            
            // Send to each contact
            for contactId in contactIds {
                do {
                    try MessageSender.send(
                        db,
                        message: VisibleMessage(text: momentText),
                        interactionId: nil,
                        threadId: contactId,
                        threadVariant: .contact,
                        using: self.dependencies
                    )
                } catch {
                    Log.error("[MomentsViewModel] Failed to send moment to \(contactId): \(error)")
                }
            }
        }
    }
    
    public func toggleLike(momentId: Int64) throws {
        let currentUserId = userSessionId.hexString
        try dependencies[singleton: .storage].write { db in
            let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
            
            // Check if already liked
            let existingLike = try? MomentLike
                .filter(MomentLike.Columns.momentId == momentId)
                .filter(MomentLike.Columns.authorId == currentUserId)
                .fetchOne(db)
            
            if let existingLike = existingLike {
                // Unlike
                try existingLike.delete(db)
                
                // Update moment like count
                try db.execute(sql: """
                    UPDATE moment
                    SET likeCount = likeCount - 1
                    WHERE id = ?
                """, arguments: [momentId])
            } else {
                // Like
                let like = MomentLike(
                    momentId: momentId,
                    authorId: currentUserId,
                    timestampMs: timestampMs
                )
                try like.insert(db)
                
                // Update moment like count
                try db.execute(sql: """
                    UPDATE moment
                    SET likeCount = likeCount + 1
                    WHERE id = ?
                """, arguments: [momentId])
            }
        }
    }
    
    public func addComment(momentId: Int64, content: String) throws {
        let currentUserId = userSessionId.hexString
        try dependencies[singleton: .storage].write { db in
            let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
            
            var comment = MomentComment(
                momentId: momentId,
                authorId: currentUserId,
                content: content,
                timestampMs: timestampMs
            )
            
            try comment.insert(db)
            
            // Update moment comment count
            try db.execute(sql: """
                UPDATE moment
                SET commentCount = commentCount + 1
                WHERE id = ?
            """, arguments: [momentId])
        }
    }
    
    public func deleteMoment(momentId: Int64) throws {
        try dependencies[singleton: .storage].write { db in
            try Moment.filter(Moment.Columns.id == momentId).deleteAll(db)
        }
    }
}

