// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUIKit
import SessionUtilitiesKit
import SessionNetworkingKit

// MARK: - Log.Category

public extension Log.Category {
    static let messageReceiver: Log.Category = .create("MessageReceiver", defaultLevel: .info)
}

// MARK: - MessageReceiver

public enum MessageReceiver {
    private static var lastEncryptionKeyPairRequest: [String: Date] = [:]
    
    public static func parse(
        data: Data,
        origin: Message.Origin,
        using dependencies: Dependencies
    ) throws -> ProcessedMessage {
        let userSessionId: SessionId = dependencies[cache: .general].sessionId
        let uniqueIdentifier: String
        var plaintext: Data
        var customProto: SNProtoContent? = nil
        var customMessage: Message? = nil
        let sender: String
        let sentTimestampMs: UInt64?
        let serverHash: String?
        let openGroupServerMessageId: UInt64?
        let openGroupWhisper: Bool
        let openGroupWhisperMods: Bool
        let openGroupWhisperTo: String?
        let threadVariant: SessionThread.Variant
        let threadIdGenerator: (Message) throws -> String
        
        switch (origin.isConfigNamespace, origin) {
            // Config messages are custom-handled via 'libSession' so just return the data directly
            case (true, .swarm(let publicKey, let namespace, let serverHash, let serverTimestampMs, _)):
                return .config(
                    publicKey: publicKey,
                    namespace: namespace,
                    serverHash: serverHash,
                    serverTimestampMs: serverTimestampMs,
                    data: data,
                    uniqueIdentifier: serverHash
                )
                
            case (_, .community(let openGroupId, let messageSender, let timestamp, let messageServerId, let messageWhisper, let messageWhisperMods, let messageWhisperTo)):
                uniqueIdentifier = "\(messageServerId)"
                plaintext = data.removePadding()   // Remove the padding
                sender = messageSender
                sentTimestampMs = timestamp.map { UInt64(floor($0 * 1000)) } // Convert to ms for database consistency
                serverHash = nil
                openGroupServerMessageId = UInt64(messageServerId)
                openGroupWhisper = messageWhisper
                openGroupWhisperMods = messageWhisperMods
                openGroupWhisperTo = messageWhisperTo
                threadVariant = .community
                threadIdGenerator = { message in
                    // Guard against control messages in open groups
                    guard message is VisibleMessage else { throw MessageReceiverError.invalidMessage }
                    
                    return openGroupId
                }
                
            case (_, .openGroupInbox(let timestamp, let messageServerId, let serverPublicKey, let senderId, let recipientId)):
                (plaintext, sender) = try dependencies[singleton: .crypto].tryGenerate(
                    .plaintextWithSessionBlindingProtocol(
                        ciphertext: data,
                        senderId: senderId,
                        recipientId: recipientId,
                        serverPublicKey: serverPublicKey
                    )
                )
                
                uniqueIdentifier = "\(messageServerId)"
                plaintext = plaintext.removePadding()   // Remove the padding
                sentTimestampMs = UInt64(floor(timestamp * 1000)) // Convert to ms for database consistency
                serverHash = nil
                openGroupServerMessageId = UInt64(messageServerId)
                openGroupWhisper = false
                openGroupWhisperMods = false
                openGroupWhisperTo = nil
                threadVariant = .contact
                threadIdGenerator = { _ in sender }
                
            case (_, .swarm(let publicKey, let namespace, let swarmServerHash, _, _)):
                uniqueIdentifier = swarmServerHash
                serverHash = swarmServerHash
                
                switch namespace {
                    case .default:
                        let envelope: SNProtoEnvelope = try Result(
                            catching: { try MessageWrapper.unwrap(data: data, namespace: namespace) })
                            .onFailure { error in Log.warn(.messageReceiver, "\(error)") }
                            .mapError { _ in MessageReceiverError.invalidMessage }
                            .successOrThrow()
                        let ciphertext: Data = try Result(
                            catching: { try envelope.content ?? { throw MessageReceiverError.noData }() })
                            .onFailure { error in Log.warn(.messageReceiver, "Failed to unwrap message from '\(namespace)' namespace due to error: \(error).") }
                            .mapError { _ in MessageReceiverError.invalidMessage }
                            .successOrThrow()
                        
                        (plaintext, sender) = try dependencies[singleton: .crypto].tryGenerate(
                            .plaintextWithSessionProtocol(ciphertext: ciphertext)
                        )
                        plaintext = plaintext.removePadding()   // Remove the padding
                        sentTimestampMs = envelope.timestamp
                        openGroupServerMessageId = nil
                        openGroupWhisper = false
                        openGroupWhisperMods = false
                        openGroupWhisperTo = nil
                        threadVariant = .contact
                        threadIdGenerator = { message in
                            Message.threadId(forMessage: message, destination: .contact(publicKey: sender), using: dependencies)
                        }
                        
                    case .groupMessages:
                        let plaintextEnvelope: Data
                        (plaintextEnvelope, sender) = try dependencies[singleton: .crypto].tryGenerate(
                            .plaintextForGroupMessage(
                                groupSessionId: SessionId(.group, hex: publicKey),
                                ciphertext: Array(data)
                            )
                        )
                        
                        let envelope: SNProtoEnvelope = try Result(catching: {
                            try MessageWrapper.unwrap(
                                data: plaintextEnvelope,
                                namespace: namespace,
                                includesWebSocketMessage: false
                            )
                        })
                        .onFailure { error in Log.warn(.messageReceiver, "\(error)") }
                        .mapError { _ in MessageReceiverError.invalidMessage }
                        .successOrThrow()
                        let envelopeContent: Data = try Result(
                            catching: { try envelope.content ?? { throw MessageReceiverError.noData }() })
                            .onFailure { error in Log.warn(.messageReceiver, "Failed to unwrap message from '\(namespace)' namespace due to error: \(error).") }
                            .mapError { _ in MessageReceiverError.invalidMessage }
                            .successOrThrow()
                        
                        plaintext = envelopeContent // Padding already removed for updated groups
                        sentTimestampMs = envelope.timestamp
                        openGroupServerMessageId = nil
                        openGroupWhisper = false
                        openGroupWhisperMods = false
                        openGroupWhisperTo = nil
                        threadVariant = .group
                        threadIdGenerator = { _ in publicKey }
                        
                    case .revokedRetrievableGroupMessages:
                        plaintext = Data()  // Requires custom decryption
                        
                        let contentProto: SNProtoContent.SNProtoContentBuilder = SNProtoContent.builder()
                        contentProto.setSigTimestamp(0)
                        customProto = try contentProto.build()
                        customMessage = LibSessionMessage(ciphertext: data)
                        sender = publicKey  // The "group" sends these messages
                        sentTimestampMs = 0
                        openGroupServerMessageId = nil
                        openGroupWhisper = false
                        openGroupWhisperMods = false
                        openGroupWhisperTo = nil
                        threadVariant = .group
                        threadIdGenerator = { _ in publicKey }
                        
                    case .configUserProfile, .configContacts, .configConvoInfoVolatile, .configUserGroups:
                        throw MessageReceiverError.invalidConfigMessageHandling
                        
                    case .configGroupInfo, .configGroupMembers, .configGroupKeys:
                        throw MessageReceiverError.invalidConfigMessageHandling
                    
                    case .legacyClosedGroup: throw MessageReceiverError.deprecatedMessage
                    case .configLocal, .all, .unknown:
                        Log.warn(.messageReceiver, "Couldn't process message due to invalid namespace.")
                        throw MessageReceiverError.unknownMessage(nil)
                }
        }
        
        let proto: SNProtoContent = try (customProto ?? Result(catching: { try SNProtoContent.parseData(plaintext) })
            .onFailure { Log.error(.messageReceiver, "Couldn't parse proto due to error: \($0).") }
            .successOrThrow())
        let message: Message = try (customMessage ?? Message.createMessageFrom(proto, sender: sender, using: dependencies))
        message.sender = sender
        message.serverHash = serverHash
        message.sentTimestampMs = sentTimestampMs
        message.sigTimestampMs = (proto.hasSigTimestamp ? proto.sigTimestamp : nil)
        message.receivedTimestampMs = dependencies[cache: .snodeAPI].currentOffsetTimestampMs()
        message.openGroupServerMessageId = openGroupServerMessageId
        message.openGroupWhisper = openGroupWhisper
        message.openGroupWhisperMods = openGroupWhisperMods
        message.openGroupWhisperTo = openGroupWhisperTo
        
        // Ignore disappearing message settings in communities (in case of modified clients)
        if threadVariant != .community {
            message.attachDisappearingMessagesConfiguration(from: proto)
        }
        
        // Don't process the envelope any further if the sender is blocked
        guard
            dependencies.mutate(cache: .libSession, { cache in
                !cache.isContactBlocked(contactId: sender)
            }) ||
            message.processWithBlockedSender
        else { throw MessageReceiverError.senderBlocked }
        
        // Ignore self sends if needed
        guard message.isSelfSendValid || sender != userSessionId.hexString else {
            throw MessageReceiverError.selfSend
        }
        
        // Guard against control messages in open groups
        guard !origin.isCommunity || message is VisibleMessage else {
            throw MessageReceiverError.invalidMessage
        }
        
        // Validate
        guard message.isValid(isSending: false) else {
            throw MessageReceiverError.invalidMessage
        }
        
        return .standard(
            threadId: try threadIdGenerator(message),
            threadVariant: threadVariant,
            proto: proto,
            messageInfo: try MessageReceiveJob.Details.MessageInfo(
                message: message,
                variant: try Message.Variant(from: message) ?? {
                    throw MessageReceiverError.invalidMessage
                }(),
                threadVariant: threadVariant,
                serverExpirationTimestamp: origin.serverExpirationTimestamp,
                proto: proto
            ),
            uniqueIdentifier: uniqueIdentifier
        )
    }
    
    // MARK: - Handling
    
    public static func handle(
        _ db: ObservingDatabase,
        threadId: String,
        threadVariant: SessionThread.Variant,
        message: Message,
        serverExpirationTimestamp: TimeInterval?,
        associatedWithProto proto: SNProtoContent,
        suppressNotifications: Bool,
        using dependencies: Dependencies
    ) throws -> InsertedInteractionInfo? {
        /// Throw if the message is outdated and shouldn't be processed (this is based on pretty flaky logic which checks if the config
        /// has been updated since the message was sent - this should be reworked to be less edge-case prone in the future)
        try throwIfMessageOutdated(
            message: message,
            threadId: threadId,
            threadVariant: threadVariant,
            openGroupUrlInfo: (threadVariant != .community ? nil :
                try? LibSession.OpenGroupUrlInfo.fetchOne(db, id: threadId)
            ),
            using: dependencies
        )
        
        MessageReceiver.updateContactDisappearingMessagesVersionIfNeeded(
            db,
            messageVariant: .init(from: message),
            contactId: message.sender,
            version: ((!proto.hasExpirationType && !proto.hasExpirationTimer) ?
                .legacyDisappearingMessages :
                .newDisappearingMessages
            ),
            using: dependencies
        )
        
        // Handle moment messages (朋友圈消息) before processing as VisibleMessage
        if let visibleMessage = message as? VisibleMessage,
           let text = visibleMessage.text,
           let sender = message.sender {
            // Update profile if needed (want to do this regardless of whether the message exists or
            // not to ensure the profile info gets sync between a users devices at every chance)
            if let profile = visibleMessage.profile {
                try Profile.updateIfNeeded(
                    db,
                    publicKey: sender,
                    displayNameUpdate: .contactUpdate(profile.displayName),
                    displayPictureUpdate: .from(profile, fallback: .contactRemove, using: dependencies),
                    blocksCommunityMessageRequests: .set(to: profile.blocksCommunityMessageRequests),
                    profileUpdateTimestamp: profile.updateTimestampSeconds,
                    using: dependencies
                )
            }
            
            // Handle moment post
            if text.hasPrefix("__MOMENT__:") {
                try handleMomentMessage(
                    db,
                    sender: sender,
                    text: text,
                    messageSentTimestampMs: message.sentTimestampMs ?? 0,
                    using: dependencies
                )
                // Return nil to skip creating Interaction for moment messages
                return nil
            }
            
        }
        
        let interactionInfo: InsertedInteractionInfo?
        switch message {
            case let message as ReadReceipt:
                interactionInfo = nil
                try MessageReceiver.handleReadReceipt(
                    db,
                    message: message,
                    serverExpirationTimestamp: serverExpirationTimestamp,
                    using: dependencies
                )
                
            case let message as TypingIndicator:
                interactionInfo = nil
                try MessageReceiver.handleTypingIndicator(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    message: message,
                    using: dependencies
                )
                
            case is GroupUpdateInviteMessage, is GroupUpdateInfoChangeMessage,
                is GroupUpdateMemberChangeMessage, is GroupUpdatePromoteMessage, is GroupUpdateMemberLeftMessage,
                is GroupUpdateMemberLeftNotificationMessage, is GroupUpdateInviteResponseMessage,
                is GroupUpdateDeleteMemberContentMessage:
                interactionInfo = try MessageReceiver.handleGroupUpdateMessage(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    message: message,
                    serverExpirationTimestamp: serverExpirationTimestamp,
                    suppressNotifications: suppressNotifications,
                    using: dependencies
                )
                
            case let message as DataExtractionNotification:
                interactionInfo = try MessageReceiver.handleDataExtractionNotification(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    message: message,
                    serverExpirationTimestamp: serverExpirationTimestamp,
                    using: dependencies
                )
                
            case let message as ExpirationTimerUpdate:
                interactionInfo = try MessageReceiver.handleExpirationTimerUpdate(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    message: message,
                    serverExpirationTimestamp: serverExpirationTimestamp,
                    proto: proto,
                    using: dependencies
                )
                
            case let message as UnsendRequest:
                interactionInfo = nil
                try MessageReceiver.handleUnsendRequest(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    message: message,
                    using: dependencies
                )
                
            case let message as CallMessage:
                interactionInfo = try MessageReceiver.handleCallMessage(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    message: message,
                    suppressNotifications: suppressNotifications,
                    using: dependencies
                )
                
            case let message as MessageRequestResponse:
                interactionInfo = try MessageReceiver.handleMessageRequestResponse(
                    db,
                    message: message,
                    using: dependencies
                )
                
            case let message as VisibleMessage:
                interactionInfo = try MessageReceiver.handleVisibleMessage(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    message: message,
                    serverExpirationTimestamp: serverExpirationTimestamp,
                    associatedWithProto: proto,
                    suppressNotifications: suppressNotifications,
                    using: dependencies
                )
            
            case let message as LibSessionMessage:
                interactionInfo = nil
                try MessageReceiver.handleLibSessionMessage(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    message: message,
                    using: dependencies
                )
            
            default: throw MessageReceiverError.unknownMessage(proto)
        }
        
        // Perform any required post-handling logic
        try MessageReceiver.postHandleMessage(
            db,
            threadId: threadId,
            threadVariant: threadVariant,
            message: message,
            insertedInteractionInfo: interactionInfo,
            using: dependencies
        )
        
        return interactionInfo
    }
    
    public static func postHandleMessage(
        _ db: ObservingDatabase,
        threadId: String,
        threadVariant: SessionThread.Variant,
        message: Message,
        insertedInteractionInfo: InsertedInteractionInfo?,
        using dependencies: Dependencies
    ) throws {
        // When handling any message type which has related UI we want to make sure the thread becomes
        // visible (the only other spot this flag gets set is when sending messages)
        let shouldBecomeVisible: Bool = {
            switch message {
                case is ReadReceipt: return false
                case is TypingIndicator: return false
                case is UnsendRequest: return false
                case is CallMessage: return (threadId != dependencies[cache: .general].sessionId.hexString)
                    
                /// These are sent to the one-to-one conversation so they shouldn't make that visible
                case is GroupUpdateInviteMessage, is GroupUpdatePromoteMessage:
                    return false
                    
                /// These are sent to the group conversation but we have logic so you can only ever "leave" a group, you can't "hide" it
                /// so that it re-appears when a new message is received so the thread shouldn't become visible for any of them
                case is GroupUpdateInfoChangeMessage, is GroupUpdateMemberChangeMessage,
                    is GroupUpdateMemberLeftMessage, is GroupUpdateMemberLeftNotificationMessage,
                    is GroupUpdateInviteResponseMessage, is GroupUpdateDeleteMemberContentMessage:
                    return false
            
                /// Currently this is just for handling the `groupKicked` message which is sent to a group so the same rules as above apply
                case is LibSessionMessage: return false
                    
                default: return true
            }
        }()
        
        // Start the disappearing messages timer if needed
        // For disappear after send, this is necessary so the message will disappear even if it is not read
        if threadVariant != .community {
            db.afterCommit(dedupeId: "PostInsertDisappearingMessagesJob") {  // stringlint:ignore
                dependencies[singleton: .storage].writeAsync { db in
                    dependencies[singleton: .jobRunner].upsert(
                        db,
                        job: DisappearingMessagesJob.updateNextRunIfNeeded(db, using: dependencies),
                        canStartJob: true
                    )
                }
            }
        }
        
        // Only check the current visibility state if we should become visible for this message type
        guard shouldBecomeVisible else { return }
        
        // Only update the `shouldBeVisible` flag if the thread is currently not visible
        // as we don't want to trigger a config update if not needed
        let isCurrentlyVisible: Bool = try SessionThread
            .filter(id: threadId)
            .select(.shouldBeVisible)
            .asRequest(of: Bool.self)
            .fetchOne(db)
            .defaulting(to: false)

        guard !isCurrentlyVisible else { return }
        
        try SessionThread.updateVisibility(
            db,
            threadId: threadId,
            isVisible: true,
            additionalChanges: [SessionThread.Columns.isDraft.set(to: false)],
            using: dependencies
        )
    }
    
    public static func handleOpenGroupReactions(
        _ db: ObservingDatabase,
        threadId: String,
        openGroupMessageServerId: Int64,
        openGroupReactions: [Reaction]
    ) throws {
        struct Info: Decodable, FetchableRecord {
            let id: Int64
            let variant: Interaction.Variant
        }
        
        guard let interactionInfo: Info = try? Interaction
            .select(.id, .variant)
            .filter(Interaction.Columns.threadId == threadId)
            .filter(Interaction.Columns.openGroupServerMessageId == openGroupMessageServerId)
            .asRequest(of: Info.self)
            .fetchOne(db)
        else { throw MessageReceiverError.invalidMessage }
        
        // If the user locally deleted the message then we don't want to process reactions for it
        guard !interactionInfo.variant.isDeletedMessage else { return }
        
        _ = try Reaction
            .filter(Reaction.Columns.interactionId == interactionInfo.id)
            .deleteAll(db)
        
        for reaction in openGroupReactions {
            try reaction.with(interactionId: interactionInfo.id).insert(db)
        }
    }
    
    public static func throwIfMessageOutdated(
        message: Message,
        threadId: String,
        threadVariant: SessionThread.Variant,
        openGroupUrlInfo: LibSession.OpenGroupUrlInfo?,
        using dependencies: Dependencies
    ) throws {
        // TODO: [Database Relocation] Need the "deleted_contacts" logic to handle the 'throwIfMessageOutdated' case
        // TODO: [Database Relocation] Need a way to detect _when_ the NTS conversation was hidden (so an old message won't re-show it)
        switch (threadVariant, message) {
            case (_, is ReadReceipt): return /// No visible artifact created so better to keep for more reliable read states
            case (_, is UnsendRequest): return /// We should always process the removal of messages just in case
            
            /// These group update messages update the group state so should be processed even if they were old
            case (.group, is GroupUpdateInviteResponseMessage): return
            case (.group, is GroupUpdateDeleteMemberContentMessage): return
            case (.group, is GroupUpdateMemberLeftMessage): return
                
            /// A `LibSessionMessage` may not contain a timestamp and may contain custom instructions regardless of the
            /// state of the group so we should always process it (it should contain it's own versioning which can be used to determine
            /// if it's old)
            case (.group, is LibSessionMessage): return
            
            /// No special logic for these, just make sure that either the conversation is already visible, or we are allowed to
            /// make a config change
            case (.contact, _), (.community, _), (.legacyGroup, _): break
                
            /// If the destination is a group then ensure:
            /// • We have credentials
            /// • The group hasn't been destroyed
            /// • The user wasn't kicked from the group
            /// • The message wasn't sent before all messages/attachments were deleted
            case (.group, _):
                let messageSentTimestamp: TimeInterval = TimeInterval((message.sentTimestampMs ?? 0) / 1000)
                let groupSessionId: SessionId = SessionId(.group, hex: threadId)
                
                /// Ensure the group is able to receive messages
                try dependencies.mutate(cache: .libSession) { cache in
                    guard
                        cache.hasCredentials(groupSessionId: groupSessionId),
                        !cache.groupIsDestroyed(groupSessionId: groupSessionId),
                        !cache.wasKickedFromGroup(groupSessionId: groupSessionId)
                    else { throw MessageReceiverError.outdatedMessage }
                    
                    return
                }
                
                /// Ensure the message shouldn't have been deleted
                try dependencies.mutate(cache: .libSession) { cache in
                    let deleteBefore: TimeInterval = (cache.groupDeleteBefore(groupSessionId: groupSessionId) ?? 0)
                    let deleteAttachmentsBefore: TimeInterval = (cache.groupDeleteAttachmentsBefore(groupSessionId: groupSessionId) ?? 0)
                    
                    guard
                        (
                            deleteBefore == 0 ||
                            messageSentTimestamp > deleteBefore
                        ) && (
                            deleteAttachmentsBefore == 0 ||
                            (message as? VisibleMessage)?.dataMessageHasAttachments == false ||
                            messageSentTimestamp > deleteAttachmentsBefore
                        )
                    else { throw MessageReceiverError.outdatedMessage }
                    
                    return
                }
        }
        
        /// If the conversation is not visible in the config and the message was sent before the last config update (minus a buffer period)
        /// then we can assume that the user has hidden/deleted the conversation and it shouldn't be reshown by this (old) message
        try dependencies.mutate(cache: .libSession) { cache in
            let conversationInConfig: Bool? = cache.conversationInConfig(
                threadId: threadId,
                threadVariant: threadVariant,
                visibleOnly: true,
                openGroupUrlInfo: openGroupUrlInfo
            )
            let canPerformConfigChange: Bool? = cache.canPerformChange(
                threadId: threadId,
                threadVariant: threadVariant,
                changeTimestampMs: message.sentTimestampMs
                    .map { Int64($0) }
                    .defaulting(to: dependencies[cache: .snodeAPI].currentOffsetTimestampMs())
            )
            
            switch (conversationInConfig, canPerformConfigChange) {
                case (false, false): throw MessageReceiverError.outdatedMessage
                default: break
            }
        }
        
        /// If we made it here then the message is not outdated
    }
    
    /// Notify any observers of newly received messages
    public static func prepareNotificationsForInsertedInteractions(
        _ db: ObservingDatabase,
        insertedInteractionInfo: InsertedInteractionInfo?,
        isMessageRequest: Bool,
        using dependencies: Dependencies
    ) {
        guard let info: InsertedInteractionInfo = insertedInteractionInfo else { return }
        
        /// This allows observing for an event where a message request receives an unread message
        if isMessageRequest && !info.wasRead {
            db.addEvent(
                MessageEvent(id: info.interactionId, threadId: info.threadId, change: nil),
                forKey: .messageRequestUnreadMessageReceived
            )
        }
        
        /// Need to re-show the message requests section if we received a new message request
        if isMessageRequest && info.numPreviousInteractionsForMessageRequest == 0 {
            dependencies.set(db, .hasHiddenMessageRequests, false)
        }
    }
    
    // MARK: - Moment Messages
    
    private static func handleMomentMessage(
        _ db: ObservingDatabase,
        sender: String,
        text: String,
        messageSentTimestampMs: UInt64,
        using dependencies: Dependencies
    ) throws {
        // Extract JSON data from text (remove "__MOMENT__:" prefix)
        let jsonString = String(text.dropFirst("__MOMENT__:".count))
        guard let jsonData = jsonString.data(using: .utf8),
              let momentData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }
        
        // Parse moment data
        let content = momentData["content"] as? String
        let imageAttachmentIdsString = momentData["imageAttachmentIds"] as? String
        let imageDownloadUrlsString = momentData["imageDownloadUrls"] as? String
        let imageEncryptionKeysString = momentData["imageEncryptionKeys"] as? String
        let imageDigestsString = momentData["imageDigests"] as? String
        let imageByteCountsString = momentData["imageByteCounts"] as? String
        let timestampMs = (momentData["timestampMs"] as? Int64) ?? Int64(messageSentTimestampMs)
        
        print("🟢 [MessageReceiver] ========== RECEIVED MOMENT ==========")
        print("🟢 [MessageReceiver] Received moment from \(sender)")
        print("🟢 [MessageReceiver] Content: \(content ?? "nil")")
        print("🟢 [MessageReceiver] ImageAttachmentIds: \(imageAttachmentIdsString ?? "nil")")
        print("🟢 [MessageReceiver] ImageDownloadUrls: \(imageDownloadUrlsString ?? "nil")")
        print("🟢 [MessageReceiver] ImageEncryptionKeys: \(imageEncryptionKeysString ?? "nil")")
        print("🟢 [MessageReceiver] ImageDigests: \(imageDigestsString ?? "nil")")
        print("🟢 [MessageReceiver] ImageByteCounts: \(imageByteCountsString ?? "nil")")
        print("🟢 [MessageReceiver] =====================================")
        
        Log.info("[MessageReceiver] Received moment from \(sender)")
        Log.info("[MessageReceiver] Content: \(content ?? "nil")")
        Log.info("[MessageReceiver] ImageAttachmentIds: \(imageAttachmentIdsString ?? "nil")")
        Log.info("[MessageReceiver] ImageDownloadUrls: \(imageDownloadUrlsString ?? "nil")")
        Log.info("[MessageReceiver] ImageEncryptionKeys: \(imageEncryptionKeysString ?? "nil")")
        Log.info("[MessageReceiver] ImageDigests: \(imageDigestsString ?? "nil")")
        Log.info("[MessageReceiver] ImageByteCounts: \(imageByteCountsString ?? "nil")")
        
        // Check if moment already exists (avoid duplicates)
        let existingMoment = try? Moment
            .filter(Moment.Columns.authorId == sender)
            .filter(Moment.Columns.timestampMs == timestampMs)
            .fetchOne(db)
        
        guard existingMoment == nil else { return }
        
        // Parse download URLs
        var attachmentIds: [String] = []
        if let imageDownloadUrlsString = imageDownloadUrlsString {
            let downloadUrls = imageDownloadUrlsString
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            print("🟢 [MessageReceiver] Processing \(downloadUrls.count) download URLs")
            
            // Parse encryption keys, digests, and byteCounts
            let encryptionKeys: [String?] = imageEncryptionKeysString?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .map { $0.isEmpty ? nil : $0 }
                ?? []
            let digests: [String?] = imageDigestsString?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .map { $0.isEmpty ? nil : $0 }
                ?? []
            let byteCounts: [UInt] = imageByteCountsString?
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .compactMap { UInt($0) }
                ?? []
            
            // Create Attachment records for each download URL and download them
            for (index, downloadUrl) in downloadUrls.enumerated() {
                let attachmentId = UUID().uuidString
                
                // Get encryption key, digest, and byteCount for this attachment
                let encryptionKeyHex = (index < encryptionKeys.count) ? encryptionKeys[index] : nil
                let digestHex = (index < digests.count) ? digests[index] : nil
                let byteCount = (index < byteCounts.count) ? byteCounts[index] : 0
                let encryptionKey = encryptionKeyHex.flatMap { Data(hex: $0) }
                let digest = digestHex.flatMap { Data(hex: $0) }
                
                print("🟢 [MessageReceiver] Creating attachment[\(index)]: id=\(attachmentId), url=\(downloadUrl)")
                print("🟢 [MessageReceiver] EncryptionKey[\(index)]: \(encryptionKeyHex ?? "nil"), hasKey=\(encryptionKey != nil)")
                print("🟢 [MessageReceiver] Digest[\(index)]: \(digestHex ?? "nil"), hasDigest=\(digest != nil)")
                print("🟢 [MessageReceiver] ByteCount[\(index)]: \(byteCount)")
                
                // Create attachment record with pending download state
                var attachment = Attachment(
                    id: attachmentId,
                    serverId: Network.FileServer.fileId(for: downloadUrl),
                    variant: .standard,
                    state: .pendingDownload,
                    contentType: "image/jpeg",
                    byteCount: byteCount, // Use the byteCount from message (original plaintext size)
                    creationTimestamp: Date().timeIntervalSince1970,
                    sourceFilename: "moment_image.jpg",
                    downloadUrl: downloadUrl,
                    width: nil,
                    height: nil,
                    duration: nil,
                    isVisualMedia: true,
                    isValid: true,
                    encryptionKey: encryptionKey,
                    digest: digest
                )
                
                try attachment.insert(db)
                attachmentIds.append(attachmentId)
                
                // Download attachment directly (since moment messages don't have Interaction)
                let deps = dependencies
                Task {
                    do {
                        print("🟢 [MessageReceiver] Starting download for moment image: \(attachmentId)")
                        print("🟢 [MessageReceiver] Download URL: \(downloadUrl)")
                        Log.info("[MessageReceiver] Starting download for moment image: \(attachmentId), URL: \(downloadUrl)")
                        let storage = deps[singleton: .storage]
                        
                        // Update state to downloading
                        try await storage.writeAsync { db in
                            _ = try? Attachment
                                .filter(id: attachmentId)
                                .updateAll(db, Attachment.Columns.state.set(to: Attachment.State.downloading))
                            
                            db.addAttachmentEvent(
                                id: attachmentId,
                                messageId: nil,
                                type: .updated(.state(.downloading))
                            )
                        }
                        
                        guard let downloadUrlObj = URL(string: downloadUrl) else {
                            throw AttachmentError.invalidPath
                        }
                        
                        // For FileServer downloads, we don't need authentication
                        // FileServer downloads are public (or use deterministic encryption)
                        let request: Network.PreparedRequest<Data> = try Network.FileServer.preparedDownload(
                            url: downloadUrlObj,
                            using: deps
                        )
                        
                        print("🟢 [MessageReceiver] Downloading from FileServer: \(downloadUrl)")
                        Log.info("[MessageReceiver] Downloading from FileServer: \(downloadUrl)")
                        
                        // Download the data
                        let response: Data = try await request
                            .send(using: deps)
                            .values
                            .first(where: { _ in true })?.1 ?? { throw AttachmentError.downloadFailed }()
                        
                        print("🟢 [MessageReceiver] Downloaded \(response.count) bytes for attachment: \(attachmentId)")
                        Log.info("[MessageReceiver] Downloaded \(response.count) bytes for attachment: \(attachmentId)")
                        
                        // Check if data needs decryption
                        let plaintext: Data
                        let usesDeterministicEncryption: Bool = Network.FileServer
                            .usesDeterministicEncryption(downloadUrl)
                        
                        // Get attachment to check encryption
                        let attachmentForDecrypt = try await storage.readAsync { db -> Attachment? in
                            try? Attachment.fetchOne(db, id: attachmentId)
                        }
                        
                        if let attachment = attachmentForDecrypt {
                            print("🟢 [MessageReceiver] Checking encryption: hasKey=\(attachment.encryptionKey != nil), hasDigest=\(attachment.digest != nil), usesDeterministic=\(usesDeterministicEncryption)")
                            
                            switch (attachment.encryptionKey, attachment.digest, usesDeterministicEncryption) {
                                case (.some(let key), .some(let digest), false) where !key.isEmpty:
                                    let unpaddedSize = attachment.byteCount > 0 ? attachment.byteCount : UInt(response.count)
                                    print("🟢 [MessageReceiver] Decrypting with legacy encryption (key size: \(key.count), digest size: \(digest.count), unpaddedSize: \(unpaddedSize), ciphertext size: \(response.count))")
                                    plaintext = try deps[singleton: .crypto].tryGenerate(
                                        .legacyDecryptAttachment(
                                            ciphertext: response,
                                            key: key,
                                            digest: digest,
                                            unpaddedSize: unpaddedSize
                                        )
                                    )
                                    print("🟢 [MessageReceiver] Decrypted: \(response.count) bytes -> \(plaintext.count) bytes")
                                    
                                case (.some(let key), _, true) where !key.isEmpty:
                                    print("🟢 [MessageReceiver] Decrypting with deterministic encryption (key size: \(key.count))")
                                    plaintext = try deps[singleton: .crypto].tryGenerate(
                                        .decryptAttachment(
                                            ciphertext: response,
                                            key: key
                                        )
                                    )
                                    print("🟢 [MessageReceiver] Decrypted: \(response.count) bytes -> \(plaintext.count) bytes")
                                    
                                case (.some(let key), _, false) where !key.isEmpty:
                                    // Has key but no digest, might be using deterministic encryption without the flag
                                    print("🟢 [MessageReceiver] Has key but no digest, trying deterministic decryption")
                                    plaintext = try deps[singleton: .crypto].tryGenerate(
                                        .decryptAttachment(
                                            ciphertext: response,
                                            key: key
                                        )
                                    )
                                    print("🟢 [MessageReceiver] Decrypted: \(response.count) bytes -> \(plaintext.count) bytes")
                                    
                                default:
                                    print("⚠️ [MessageReceiver] No encryption key available, using response as plaintext")
                                    print("⚠️ [MessageReceiver] Response size: \(response.count) bytes")
                                    // Check if response looks like encrypted data (usually starts with specific bytes)
                                    if response.count > 0 {
                                        let firstBytes = response.prefix(4).map { String(format: "%02x", $0) }.joined()
                                        print("⚠️ [MessageReceiver] First 4 bytes (hex): \(firstBytes)")
                                    }
                                    plaintext = response
                            }
                        } else {
                            print("❌ [MessageReceiver] Attachment not found for decryption check, using plaintext")
                            plaintext = response
                        }
                        
                        print("🟢 [MessageReceiver] Plaintext size: \(plaintext.count) bytes")
                        
                        // Write the data to disk
                        let updatedAttachment = try await storage.writeAsync { db -> Attachment in
                            guard var attachment: Attachment = try? Attachment.fetchOne(db, id: attachmentId) else {
                                print("❌ [MessageReceiver] ERROR: Attachment not found in database: \(attachmentId)")
                                throw AttachmentError.noAttachment
                            }
                            
                            print("🟢 [MessageReceiver] Writing data to disk for attachment: \(attachmentId)")
                            
                            // Write data to file
                            if !(try attachment.write(data: plaintext, using: deps)) {
                                print("❌ [MessageReceiver] ERROR: Failed to write data to disk")
                                throw AttachmentError.writeFailed
                            }
                            
                            print("🟢 [MessageReceiver] Data written successfully, updating attachment state")
                            
                            // Update attachment state to downloaded
                            attachment = try attachment
                                .with(
                                    state: .downloaded,
                                    creationTimestamp: (deps[cache: .snodeAPI].currentOffsetTimestampMs() / 1000),
                                    using: deps
                                )
                            
                            try attachment.upsert(db)
                            
                            print("🟢 [MessageReceiver] Attachment state updated to downloaded: \(attachment.id)")
                            
                            // Trigger attachment event
                            db.addAttachmentEvent(
                                id: attachment.id,
                                messageId: nil,
                                type: .updated(.state(.downloaded))
                            )
                            
                            print("🟢 [MessageReceiver] Attachment event triggered")
                            
                            return attachment
                        }
                        
                        print("✅ [MessageReceiver] Successfully downloaded and saved moment image: \(attachmentId)")
                        Log.info("[MessageReceiver] Successfully downloaded and saved moment image: \(attachmentId)")
                    } catch {
                        print("❌ [MessageReceiver] ERROR: Failed to download moment image \(attachmentId) from \(downloadUrl): \(error)")
                        print("❌ [MessageReceiver] Error type: \(type(of: error))")
                        print("❌ [MessageReceiver] Error description: \(error.localizedDescription)")
                        Log.error("[MessageReceiver] Failed to download moment image \(attachmentId) from \(downloadUrl): \(error)")
                        
                        let storage = deps[singleton: .storage]
                        // Update attachment state to failed
                        try? await storage.writeAsync { db in
                            _ = try? Attachment
                                .filter(id: attachmentId)
                                .updateAll(db, Attachment.Columns.state.set(to: Attachment.State.failedDownload))
                            
                            db.addAttachmentEvent(
                                id: attachmentId,
                                messageId: nil,
                                type: .updated(.state(.failedDownload))
                            )
                            
                            print("❌ [MessageReceiver] Updated attachment state to failedDownload: \(attachmentId)")
                        }
                    }
                }
            }
        } else if let imageAttachmentIdsString = imageAttachmentIdsString {
            // Fallback to old format (attachmentIds only, for backward compatibility)
            attachmentIds = imageAttachmentIdsString
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        
        // Use attachmentIds for moment record
        let attachmentIdsString = attachmentIds.isEmpty ? nil : attachmentIds.joined(separator: ",")
        
        // Create and save moment
        var moment = Moment(
            authorId: sender,
            content: content,
            imageAttachmentIds: attachmentIdsString,
            timestampMs: timestampMs
        )
        
        try moment.insert(db)
    }
    
}
