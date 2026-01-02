// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Lucide
import SessionUIKit
import SessionUtilitiesKit
import SessionMessagingKit

/// Main TabBar Controller similar to App Store style
public final class MainTabBarController: UITabBarController {
    private let dependencies: Dependencies
    
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
        chatNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("聊天", comment: "Chat tab"),
            image: UIImage(systemName: "message.fill"),
            selectedImage: UIImage(systemName: "message.fill")
        )
        
        // Tab 2: 通讯录 (Contacts)
        let contactsVC = ContactsViewController(using: dependencies)
        let contactsNav = StyledNavigationController(rootViewController: contactsVC)
        contactsNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("通讯录", comment: "Contacts tab"),
            image: UIImage(systemName: "person.2.fill"),
            selectedImage: UIImage(systemName: "person.2.fill")
        )
        
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
        
        // Tab 5: 搜索 (Search) - Similar to App Store
        let searchVC = GlobalSearchViewController(using: dependencies)
        let searchNav = StyledNavigationController(rootViewController: searchVC)
        searchNav.tabBarItem = UITabBarItem(
            title: NSLocalizedString("搜索", comment: "Search tab"),
            image: UIImage(systemName: "magnifyingglass"),
            selectedImage: UIImage(systemName: "magnifyingglass")
        )
        
        viewControllers = [
            chatNav,
            contactsNav,
            discoverNav,
            settingsNav,
            searchNav
        ]
    }
}

