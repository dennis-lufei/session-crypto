// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Lucide
import GRDB
import SessionUIKit
import SessionUtilitiesKit
import SessionMessagingKit
import SignalUtilitiesKit

/// Main TabBar Controller similar to App Store style
public final class MainTabBarController: UITabBarController {
    private let dependencies: Dependencies
    private var messageRequestCancellable: DatabaseCancellable?
    private var chatUnreadCancellable: DatabaseCancellable?
    private weak var contactsTabBarItem: UITabBarItem?
    private weak var chatTabBarItem: UITabBarItem?
    
    // MARK: - Initialization
    
    public init(using dependencies: Dependencies) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(using:) instead.")
    }
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTabBar()
        setupViewControllers()
        
        // Set initial selected index
        selectedIndex = 0
    }
    
    // MARK: - Setup
    
    private func setupTabBar() {
        // Use temporary views to get theme colors
        let tempBackgroundView = UIView()
        tempBackgroundView.themeBackgroundColor = .backgroundPrimary
        
        let tempTextLabel = UILabel()
        tempTextLabel.themeTextColor = .textSecondary
        
        let tempPrimaryLabel = UILabel()
        tempPrimaryLabel.themeTextColor = .primary
        
        // Force theme application by triggering layout
        view.addSubview(tempBackgroundView)
        view.addSubview(tempTextLabel)
        view.addSubview(tempPrimaryLabel)
        tempBackgroundView.isHidden = true
        tempTextLabel.isHidden = true
        tempPrimaryLabel.isHidden = true
        view.layoutIfNeeded()
        
        let backgroundColor = tempBackgroundView.backgroundColor ?? .systemBackground
        let textSecondaryColor = tempTextLabel.textColor ?? .gray
        let primaryColor = tempPrimaryLabel.textColor ?? .systemBlue
        
        // Clean up temporary views
        tempBackgroundView.removeFromSuperview()
        tempTextLabel.removeFromSuperview()
        tempPrimaryLabel.removeFromSuperview()
        
        // Configure TabBar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = backgroundColor
        
        // Normal state
        appearance.stackedLayoutAppearance.normal.iconColor = textSecondaryColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: textSecondaryColor,
            .font: UIFont.systemFont(ofSize: 10)
        ]
        
        // Selected state
        appearance.stackedLayoutAppearance.selected.iconColor = primaryColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: primaryColor,
            .font: UIFont.systemFont(ofSize: 10)
        ]
        
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        
        // Remove top border
        tabBar.clipsToBounds = true
    }
    
    private func setupViewControllers() {
        // Tab 1: 聊天 (Chat)
        let chatVC = HomeVC(using: dependencies)
        let chatNav = StyledNavigationController(rootViewController: chatVC)
        let chatTabBarItem = UITabBarItem(
            title: NSLocalizedString("聊天", comment: "Chat tab"),
            image: UIImage(systemName: "message.fill"),
            selectedImage: UIImage(systemName: "message.fill")
        )
        chatNav.tabBarItem = chatTabBarItem
        self.chatTabBarItem = chatTabBarItem
        
        // Tab 2: 通讯录 (Contacts)
        let contactsVC = ContactsViewController(using: dependencies)
        let contactsNav = StyledNavigationController(rootViewController: contactsVC)
        let contactsTabBarItem = UITabBarItem(
            title: NSLocalizedString("通讯录", comment: "Contacts tab"),
            image: UIImage(systemName: "person.2.fill"),
            selectedImage: UIImage(systemName: "person.2.fill")
        )
        contactsNav.tabBarItem = contactsTabBarItem
        self.contactsTabBarItem = contactsTabBarItem
        
        // Tab 3: 发现 (Discover)
        let discoverVC = DiscoverViewController(using: dependencies)
        let discoverNav = StyledNavigationController(rootViewController: discoverVC)
        discoverNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("发现", comment: "Discover tab"),
            image: UIImage(systemName: "square.grid.2x2.fill"),
            selectedImage: UIImage(systemName: "square.grid.2x2.fill")
        )
        
        // Tab 4: 我的 (Profile/Settings)
        let settingsVC = SessionTableViewController(
            viewModel: SettingsViewModel(using: dependencies)
        )
        let settingsNav = StyledNavigationController(rootViewController: settingsVC)
        settingsNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("我的", comment: "Profile/Settings tab"),
            image: UIImage(systemName: "person.circle.fill"),
            selectedImage: UIImage(systemName: "person.circle.fill")
        )
        
        viewControllers = [
            chatNav,
            contactsNav,
            discoverNav,
            settingsNav
        ]
        
        setupMessageRequestObservation()
        setupChatUnreadObservation()
    }
    
    // MARK: - Chat Unread Badge
    
    private func setupChatUnreadObservation() {
        let chatUnreadObservation = ValueObservation.trackingConstantRegion { [dependencies] db -> Int in
            try Interaction.fetchAppBadgeUnreadCount(ObservingDatabase.create(db, using: dependencies), using: dependencies)
        }
        
        chatUnreadCancellable = dependencies[singleton: .storage].start(
            chatUnreadObservation,
            scheduling: .async(onQueue: .main),
            onError: { error in
                Log.error("[MainTabBarController] Chat unread observation failed: \(error)")
            },
            onChange: { [weak self] count in
                self?.updateChatUnreadBadge(count: count)
            }
        )
    }
    
    private func updateChatUnreadBadge(count: Int) {
        if count > 0 {
            chatTabBarItem?.badgeValue = "\(count)"
        } else {
            chatTabBarItem?.badgeValue = nil
        }
    }
    
    // MARK: - Message Request Badge
    
    private func setupMessageRequestObservation() {
        let messageRequestObservation = ValueObservation.trackingConstantRegion { [dependencies] db -> Int in
            let hasHidden = dependencies.mutate(cache: .libSession) { libSession in
                libSession.get(.hasHiddenMessageRequests)
            }
            
            // If message requests are hidden, return 0
            guard !hasHidden else { return 0 }
            
            struct ThreadIdVariant: Decodable, Hashable, FetchableRecord {
                let id: String
                let variant: SessionThread.Variant
            }
            
            let potentialMessageRequestThreadInfo: Set<ThreadIdVariant> = try SessionThread
                .select(.id, .variant)
                .filter(
                    SessionThread.Columns.variant == SessionThread.Variant.contact ||
                    SessionThread.Columns.variant == SessionThread.Variant.group
                )
                .asRequest(of: ThreadIdVariant.self)
                .fetchSet(db)
            
            let messageRequestThreadIds: Set<String> = Set(
                dependencies.mutate(cache: .libSession) { libSession in
                    potentialMessageRequestThreadInfo.compactMap {
                        guard libSession.isMessageRequest(threadId: $0.id, threadVariant: $0.variant) else {
                            return nil
                        }
                        return $0.id
                    }
                }
            )
            
            let count = try SessionThread
                .unreadMessageRequestsQuery(messageRequestThreadIds: messageRequestThreadIds)
                .fetchCount(db)
            
            return count
        }
        
        messageRequestCancellable = dependencies[singleton: .storage].start(
            messageRequestObservation,
            scheduling: .async(onQueue: .main),
            onError: { error in
                Log.error("[MainTabBarController] Message request observation failed: \(error)")
            },
            onChange: { [weak self] count in
                self?.updateMessageRequestBadge(count: count)
            }
        )
    }
    
    private func updateMessageRequestBadge(count: Int) {
        if count > 0 {
            contactsTabBarItem?.badgeValue = "\(count)"
        } else {
            contactsTabBarItem?.badgeValue = nil
        }
    }
}

