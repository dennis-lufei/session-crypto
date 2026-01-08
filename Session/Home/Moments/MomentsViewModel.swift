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
        public let imageAttachmentIds: [String]
        
        public var id: Int64 { moment.id ?? -1 }
        
        public init(
            moment: Moment,
            profile: Profile,
            imageAttachmentIds: [String]
        ) {
            self.moment = moment
            self.profile = profile
            self.imageAttachmentIds = imageAttachmentIds
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
            
            // Batch fetch all profiles for moment authors
            let authorIds = Set(moments.map { $0.authorId })
            let profiles: [Profile] = try Profile
                .filter(authorIds.contains(Profile.Columns.id))
                .fetchAll(db)
            let profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            
            // Build result
            var result: [MomentWithProfile] = []
            
            for moment in moments {
                guard let profile = profilesById[moment.authorId] else { continue }
                
                // Parse image attachment IDs
                let imageAttachmentIds: [String] = (moment.imageAttachmentIds ?? "")
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                result.append(MomentWithProfile(
                    moment: moment,
                    profile: profile,
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
                print("🟢 [MomentsViewModel] Moments updated: \(moments.count) moments")
                Log.info("[MomentsViewModel] Moments updated: \(moments.count) moments")
                self?.moments = moments
                self?.isLoading = false
            }
        )
    }
    
    // MARK: - Actions
    
    public func createMomentWithImages(content: String?, images: [UIImage]) async throws {
        let deps = dependencies
        let storage = deps[singleton: .storage]
        var uploadedAttachments: [Attachment] = []
        
        // Upload images to server
        for image in images {
            // First, save UIImage to a temporary file
            let tempFilePath = deps[singleton: .fileManager].temporaryFilePath()
            
            // Convert UIImage to JPEG data and save to temp file
            guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                Log.error("[MomentsViewModel] Failed to convert UIImage to JPEG data")
                throw MomentsError.networkError(NSError(domain: "MomentsViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法处理图片"]))
            }
            
            try deps[singleton: .fileManager].write(data: imageData, toPath: tempFilePath)
            
            // Create PendingAttachment from file URL
            let tempFileURL = URL(fileURLWithPath: tempFilePath)
            let pendingAttachment = PendingAttachment(
                source: .media(.url(tempFileURL)),
                using: deps
            )
            
            // Prepare attachment (strip metadata, convert format)
            let preparedAttachment = try await pendingAttachment.prepare(
                operations: [
                    .stripImageMetadata,
                    .convert(to: .webPLossy(
                        maxDimension: 2048,
                        cropRect: nil,
                        resizeMode: .fit,
                        compressionQuality: 0.8
                    ))
                ],
                storeAtPendingAttachmentUploadPath: true,
                using: deps
            )
            
            // Clean up temp file
            try? deps[singleton: .fileManager].removeItem(atPath: tempFilePath)
            
            // Get authentication method for contact thread (use current user's thread for auth)
            let currentUserId = userSessionId.hexString
            let authMethod: AuthenticationMethod = try await storage.readAsync { db in
                return try Authentication.with(
                    db,
                    threadId: currentUserId,
                    threadVariant: .contact,
                    using: deps
                )
            }
            
            // Upload attachment
            Log.info("[MomentsViewModel] Starting upload for attachment: \(preparedAttachment.attachment.id)")
            Log.info("[MomentsViewModel] Prepared attachment state: \(preparedAttachment.attachment.state)")
            Log.info("[MomentsViewModel] Prepared attachment downloadUrl: \(preparedAttachment.attachment.downloadUrl ?? "nil")")
            
            let (uploadedAttachment, uploadResponse) = try await AttachmentUploadJob.upload(
                attachment: preparedAttachment.attachment,
                threadId: currentUserId,
                interactionId: nil,
                messageSendJobId: nil,
                authMethod: authMethod,
                onEvent: AttachmentUploadJob.standardEventHandling(using: deps),
                using: deps
            )
            
            Log.info("[MomentsViewModel] Upload completed for attachment: \(uploadedAttachment.id)")
            Log.info("[MomentsViewModel] Uploaded attachment state: \(uploadedAttachment.state)")
            Log.info("[MomentsViewModel] Uploaded attachment downloadUrl: \(uploadedAttachment.downloadUrl ?? "nil")")
            Log.info("[MomentsViewModel] Upload response fileId: \(uploadResponse.id)")
            
            // Save uploaded attachment to database
            try await storage.writeAsync { db in
                try uploadedAttachment.upsert(db)
            }
            
            uploadedAttachments.append(uploadedAttachment)
        }
        
        // Extract attachment IDs and download URLs
        let attachmentIds = uploadedAttachments.map { $0.id }
        let downloadUrls = uploadedAttachments.compactMap { $0.downloadUrl }
        
        // Extract encryption keys, digests, and byteCounts (for decryption on receiver side)
        var encryptionKeys: [String?] = []
        var digests: [String?] = []
        var byteCounts: [UInt] = []
        for attachment in uploadedAttachments {
            encryptionKeys.append(attachment.encryptionKey?.toHexString())
            digests.append(attachment.digest?.toHexString())
            byteCounts.append(attachment.byteCount)
        }
        
        print("🔵 [MomentsViewModel] ========== UPLOAD SUMMARY ==========")
        print("🔵 [MomentsViewModel] Uploaded \(uploadedAttachments.count) attachments")
        print("🔵 [MomentsViewModel] Attachment IDs: \(attachmentIds)")
        print("🔵 [MomentsViewModel] Download URLs count: \(downloadUrls.count)")
        for (index, url) in downloadUrls.enumerated() {
            print("🔵 [MomentsViewModel] Download URL[\(index)]: \(url)")
            print("🔵 [MomentsViewModel] EncryptionKey[\(index)]: \(encryptionKeys[index] ?? "nil")")
            print("🔵 [MomentsViewModel] Digest[\(index)]: \(digests[index] ?? "nil")")
            print("🔵 [MomentsViewModel] ByteCount[\(index)]: \(byteCounts[index])")
        }
        for (index, attachment) in uploadedAttachments.enumerated() {
            print("🔵 [MomentsViewModel] Attachment[\(index)]: id=\(attachment.id), downloadUrl=\(attachment.downloadUrl ?? "nil"), state=\(attachment.state), byteCount=\(attachment.byteCount), hasEncryptionKey=\(attachment.encryptionKey != nil), hasDigest=\(attachment.digest != nil)")
        }
        print("🔵 [MomentsViewModel] =====================================")
        
        Log.info("[MomentsViewModel] Uploaded \(uploadedAttachments.count) attachments")
        Log.info("[MomentsViewModel] Attachment IDs: \(attachmentIds)")
        Log.info("[MomentsViewModel] Download URLs: \(downloadUrls)")
        
        // Validate that we have download URLs
        guard !downloadUrls.isEmpty else {
            print("❌ [MomentsViewModel] ERROR: No download URLs after upload!")
            Log.error("[MomentsViewModel] No download URLs after upload!")
            for attachment in uploadedAttachments {
                Log.error("[MomentsViewModel] Attachment \(attachment.id): downloadUrl=\(attachment.downloadUrl ?? "nil"), state=\(attachment.state)")
            }
            throw MomentsError.networkError(NSError(domain: "MomentsViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "上传失败：未获取到下载链接"]))
        }
        
        // Extract encryption keys, digests, and byteCounts as non-optional strings
        let encryptionKeysStrings = encryptionKeys.map { $0 ?? "" }
        let digestsStrings = digests.map { $0 ?? "" }
        let byteCountsStrings = byteCounts.map { String($0) }
        
        // Create moment with attachment IDs and download URLs
        try createMoment(
            content: content,
            imageAttachmentIds: attachmentIds,
            imageDownloadUrls: downloadUrls,
            imageEncryptionKeys: encryptionKeysStrings,
            imageDigests: digestsStrings,
            imageByteCounts: byteCountsStrings
        )
    }
    
    public func createMoment(
        content: String?,
        imageAttachmentIds: [String],
        imageDownloadUrls: [String] = [],
        imageEncryptionKeys: [String] = [],
        imageDigests: [String] = [],
        imageByteCounts: [String] = []
    ) throws {
        let currentUserId = userSessionId.hexString
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        let attachmentIdsString = imageAttachmentIds.isEmpty ? nil : imageAttachmentIds.joined(separator: ",")
        let downloadUrlsString = imageDownloadUrls.isEmpty ? nil : imageDownloadUrls.joined(separator: ",")
        
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
        storage.writeAsync { [weak self] db in
            guard let self = self else { return }
            
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
            
            // Create JSON data for moment (include both attachmentIds and downloadUrls)
            var momentData: [String: Any] = [
                "content": content ?? NSNull(),
                "timestampMs": timestampMs
            ]
            
            // Include attachmentIds for backward compatibility
            if let attachmentIdsString = attachmentIdsString {
                momentData["imageAttachmentIds"] = attachmentIdsString
            }
            
            // Include downloadUrls for new clients to download images
            if let downloadUrlsString = downloadUrlsString {
                momentData["imageDownloadUrls"] = downloadUrlsString
                print("🔵 [MomentsViewModel] Including downloadUrls in message: \(downloadUrlsString)")
                Log.info("[MomentsViewModel] Including downloadUrls in message: \(downloadUrlsString)")
            } else {
                print("⚠️ [MomentsViewModel] WARNING: No downloadUrls to include in message!")
                Log.warn("[MomentsViewModel] No downloadUrls to include in message!")
            }
            
            // Include encryption keys, digests, and byteCounts if available (for decryption)
            let encryptionKeysString = imageEncryptionKeys.joined(separator: ",")
            let digestsString = imageDigests.joined(separator: ",")
            let byteCountsString = imageByteCounts.joined(separator: ",")
            if !encryptionKeysString.isEmpty && encryptionKeysString != String(repeating: ",", count: max(0, imageEncryptionKeys.count - 1)) {
                momentData["imageEncryptionKeys"] = encryptionKeysString
                print("🔵 [MomentsViewModel] Including encryptionKeys in message: \(encryptionKeysString.prefix(50))...")
            }
            if !digestsString.isEmpty && digestsString != String(repeating: ",", count: max(0, imageDigests.count - 1)) {
                momentData["imageDigests"] = digestsString
                print("🔵 [MomentsViewModel] Including digests in message: \(digestsString.prefix(50))...")
            }
            if !byteCountsString.isEmpty && byteCountsString != String(repeating: ",", count: max(0, imageByteCounts.count - 1)) {
                momentData["imageByteCounts"] = byteCountsString
                print("🔵 [MomentsViewModel] Including byteCounts in message: \(byteCountsString)")
            }
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: momentData),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("❌ [MomentsViewModel] ERROR: Failed to serialize moment data")
                Log.error("[MomentsViewModel] Failed to serialize moment data")
                return
            }
            
            let momentText = "__MOMENT__:\(jsonString)"
            print("🔵 [MomentsViewModel] Sending moment message to \(contactIds.count) contacts")
            print("🔵 [MomentsViewModel] Message preview: \(String(momentText.prefix(200)))...")
            Log.info("[MomentsViewModel] Sending moment message to \(contactIds.count) contacts")
            
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
    
    public func deleteMoment(momentId: Int64) throws {
        let currentUserId = userSessionId.hexString
        let storage = dependencies[singleton: .storage]
        
        // Get moment info before deleting (to send notification)
        var momentTimestampMs: Int64?
        try storage.read { db in
            if let moment = try? Moment.fetchOne(db, id: momentId) {
                momentTimestampMs = moment.timestampMs
            }
        }
        
        // Delete from local database
        do {
            var deletedCount: Int = 0
            try storage.write { db in
                deletedCount = try Moment.filter(Moment.Columns.id == momentId).deleteAll(db)
                print("🔵 [MomentsViewModel] Deleted \(deletedCount) moment(s) with id \(momentId) from local database")
                Log.info("[MomentsViewModel] Deleted \(deletedCount) moment(s) with id \(momentId) from local database")
                
                // Verify deletion
                if let stillExists = try? Moment.fetchOne(db, id: momentId) {
                    print("⚠️ [MomentsViewModel] WARNING: Moment \(momentId) still exists after deletion!")
                    Log.warn("[MomentsViewModel] Moment \(momentId) still exists after deletion!")
                } else {
                    print("✅ [MomentsViewModel] Verified: Moment \(momentId) successfully deleted from local database")
                    Log.info("[MomentsViewModel] Verified: Moment \(momentId) successfully deleted from local database")
                }
            }
            
            guard deletedCount > 0 else {
                print("⚠️ [MomentsViewModel] WARNING: No moments were deleted (momentId: \(momentId))")
                Log.warn("[MomentsViewModel] No moments were deleted (momentId: \(momentId))")
                throw MomentsError.momentNotFound
            }
        } catch {
            print("❌ [MomentsViewModel] ERROR: Failed to delete moment \(momentId): \(error)")
            Log.error("[MomentsViewModel] Failed to delete moment: \(error)")
            throw MomentsError.databaseError(error)
        }
        
        // Send delete notification to all approved contacts
        if let timestampMs = momentTimestampMs {
            storage.writeAsync { [weak self] db in
                guard let self = self else { return }
                
                let deleteData: [String: Any] = [
                    "type": "delete",
                    "momentId": momentId,
                    "authorId": currentUserId,
                    "timestampMs": timestampMs
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: deleteData),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    Log.error("[MomentsViewModel] Failed to serialize delete message data")
                    return
                }
                
                let deleteText = "__MOMENT_DELETE__:\(jsonString)"
                
                print("🔵 [MomentsViewModel] Delete message text: \(deleteText)")
                print("🔵 [MomentsViewModel] Delete message JSON: \(jsonString)")

                // Get all approved contacts (excluding current user)
                let contact: TypedTableAlias<Contact> = TypedTableAlias()
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
                    print("❌ [MomentsViewModel] Failed to fetch contacts for delete notification: \(error)")
                    Log.error("[MomentsViewModel] Failed to fetch contacts for delete notification: \(error)")
                    return
                }

                guard !contactIds.isEmpty else {
                    print("⚠️ [MomentsViewModel] No contacts to send delete notification to")
                    return
                }
                
                print("🔵 [MomentsViewModel] Sending delete notification to \(contactIds.count) contacts")

                // Send to all approved contacts
                for contactId in contactIds {
                    do {
                        try MessageSender.send(
                            db,
                            message: VisibleMessage(text: deleteText),
                            interactionId: nil,
                            threadId: contactId,
                            threadVariant: .contact,
                            using: self.dependencies
                        )
                        print("✅ [MomentsViewModel] Successfully sent delete notification to \(contactId)")
                    } catch {
                        print("❌ [MomentsViewModel] Failed to send delete notification to \(contactId): \(error)")
                        Log.error("[MomentsViewModel] Failed to send delete notification to \(contactId): \(error)")
                    }
                }
                
                print("🔵 [MomentsViewModel] Sent delete notification to \(contactIds.count) contacts for moment \(momentId)")
                Log.info("[MomentsViewModel] Sent delete notification to \(contactIds.count) contacts for moment \(momentId)")
            }
        }
    }
}

// MARK: - Errors

public enum MomentsError: LocalizedError {
    case emptyContent
    case databaseError(Error)
    case networkError(Error)
    case momentNotFound
    
    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            return NSLocalizedString("动态内容不能为空", comment: "Moment content cannot be empty")
        case .databaseError(let error):
            return NSLocalizedString("数据库错误: \(error.localizedDescription)", comment: "Database error")
        case .networkError(let error):
            return NSLocalizedString("网络错误: \(error.localizedDescription)", comment: "Network error")
        case .momentNotFound:
            return NSLocalizedString("朋友圈不存在", comment: "Moment not found")
        }
    }
}
