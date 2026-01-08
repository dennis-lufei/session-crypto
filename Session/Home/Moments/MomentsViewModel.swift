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
        let storage = dependencies[singleton: .storage]
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
            
            guard !moments.isEmpty else { return [] }
            
            let momentIds = moments.compactMap { $0.id }
            
            // Batch fetch all profiles for moment authors
            let authorIds = Set(moments.map { $0.authorId })
            let profiles: [Profile] = try Profile
                .filter(authorIds.contains(Profile.Columns.id))
                .fetchAll(db)
            let profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            
            // Batch fetch all likes for these moments
            let allLikes: [MomentLike] = try MomentLike
                .filter(momentIds.contains(MomentLike.Columns.momentId))
                .order(MomentLike.Columns.timestampMs.asc)
                .fetchAll(db)
            
            // Batch fetch all profiles for like authors
            let likeAuthorIds = Set(allLikes.map { $0.authorId })
            let likeProfiles: [Profile] = try Profile
                .filter(likeAuthorIds.contains(Profile.Columns.id))
                .fetchAll(db)
            let likeProfilesById = Dictionary(uniqueKeysWithValues: likeProfiles.map { ($0.id, $0) })
            
            // Group likes by momentId
            let likesByMomentId = Dictionary(grouping: allLikes) { $0.momentId }
            
            // Batch fetch all comments for these moments
            let allComments: [MomentComment] = try MomentComment
                .filter(momentIds.contains(MomentComment.Columns.momentId))
                .order(MomentComment.Columns.timestampMs.asc)
                .fetchAll(db)
            
            // Batch fetch all profiles for comment authors
            let commentAuthorIds = Set(allComments.map { $0.authorId })
            let commentProfiles: [Profile] = try Profile
                .filter(commentAuthorIds.contains(Profile.Columns.id))
                .fetchAll(db)
            let commentProfilesById = Dictionary(uniqueKeysWithValues: commentProfiles.map { ($0.id, $0) })
            
            // Group comments by momentId
            let commentsByMomentId = Dictionary(grouping: allComments) { $0.momentId }
            
            // Build result
            var result: [MomentWithProfile] = []
            
            for moment in moments {
                guard let profile = profilesById[moment.authorId] else { continue }
                
                // Check if current user liked this moment
                let momentLikes = likesByMomentId[moment.id ?? -1] ?? []
                let isLikedByCurrentUser = momentLikes.contains { $0.authorId == currentUserId }
                
                // Build likes with profiles
                let likesWithProfiles: [MomentLikeWithProfile] = momentLikes.compactMap { like in
                    guard let likeProfile = likeProfilesById[like.authorId] else { return nil }
                    return MomentLikeWithProfile(like: like, profile: likeProfile)
                }
                
                // Build comments with profiles
                let momentComments = commentsByMomentId[moment.id ?? -1] ?? []
                let commentsWithProfiles: [MomentCommentWithProfile] = momentComments.compactMap { comment in
                    guard let commentProfile = commentProfilesById[comment.authorId] else { return nil }
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
        
        observationCancellable = storage.start(
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
        
        // Validate that we have either content or images
        guard content?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false || !imageAttachmentIds.isEmpty else {
            throw MomentsError.emptyContent
        }
        
        // Save to local database first
        let storage = dependencies[singleton: .storage]
        do {
            try storage.write { db in
                var moment = Moment(
                    authorId: currentUserId,
                    content: content,
                    imageAttachmentIds: attachmentIdsString,
                    timestampMs: timestampMs
                )
                
                try moment.insert(db)
            }
        } catch {
            Log.error("[MomentsViewModel] Failed to save moment: \(error)")
            throw MomentsError.databaseError(error)
        }
        
        // Send to all approved contacts (non-blocking, errors are logged but don't fail the operation)
        storage.writeAsync { db in
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            
            // Get all approved contacts (excluding current user)
            let contactIds: [String]
            do {
                contactIds = try Contact
                    .filter(contact[.isApproved] == true)
                    .filter(contact[.isBlocked] == false)
                    .filter(contact[.id] != currentUserId)
                    .select(.id)
                    .asRequest(of: String.self)
                    .fetchAll(db)
            } catch {
                Log.error("[MomentsViewModel] Failed to fetch contacts: \(error)")
                return
            }
            
            guard !contactIds.isEmpty else { return }
            
            // Create JSON data for moment
            let momentData: [String: Any] = [
                "content": content ?? NSNull(),
                "imageAttachmentIds": attachmentIdsString ?? NSNull(),
                "timestampMs": timestampMs
            ]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: momentData),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                Log.error("[MomentsViewModel] Failed to serialize moment data")
                return
            }
            
            let momentText = "__MOMENT__:\(jsonString)"
            
            // Send to each contact
            var successCount = 0
            var failureCount = 0
            
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
                    successCount += 1
                } catch {
                    failureCount += 1
                    Log.error("[MomentsViewModel] Failed to send moment to \(contactId): \(error)")
                }
            }
            
            if failureCount > 0 {
                Log.warn("[MomentsViewModel] Sent moment to \(successCount)/\(contactIds.count) contacts")
            }
        }
    }
    
    public func toggleLike(momentId: Int64) throws {
        let currentUserId = userSessionId.hexString
        let storage = dependencies[singleton: .storage]
        try storage.write { db in
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
        let storage = dependencies[singleton: .storage]
        try storage.write { db in
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
        let storage = dependencies[singleton: .storage]
        do {
            try storage.write { db in
                try Moment.filter(Moment.Columns.id == momentId).deleteAll(db)
            }
        } catch {
            Log.error("[MomentsViewModel] Failed to delete moment: \(error)")
            throw MomentsError.databaseError(error)
        }
    }
}

// MARK: - Errors

public enum MomentsError: LocalizedError {
    case emptyContent
    case databaseError(Error)
    case networkError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            return NSLocalizedString("动态内容不能为空", comment: "Moment content cannot be empty")
        case .databaseError(let error):
            return NSLocalizedString("数据库错误: \(error.localizedDescription)", comment: "Database error")
        case .networkError(let error):
            return NSLocalizedString("网络错误: \(error.localizedDescription)", comment: "Network error")
        }
    }
}

