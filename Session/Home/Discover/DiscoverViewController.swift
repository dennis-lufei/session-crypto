// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit
import SessionMessagingKit

/// Discover View Controller - Shows discovery features and content
public final class DiscoverViewController: BaseVC {
    private let dependencies: Dependencies
    
    // MARK: - UI
    
    private lazy var scrollView: UIScrollView = {
        let result = UIScrollView()
        result.showsVerticalScrollIndicator = false
        result.alwaysBounceVertical = true
        
        return result
    }()
    
    private lazy var contentStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.spacing = Values.largeSpacing
        result.alignment = .fill
        
        return result
    }()
    
    private lazy var headerLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.text = NSLocalizedString("发现", comment: "Discover")
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var descriptionLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.text = NSLocalizedString("发现新功能和内容", comment: "Discover description")
        result.themeTextColor = .textSecondary
        result.numberOfLines = 0
        
        return result
    }()
    
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
        
        setupUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        // Scroll view
        view.addSubview(scrollView)
        scrollView.pin(to: view)
        
        // Content stack view
        scrollView.addSubview(contentStackView)
        contentStackView.pin(.leading, to: .leading, of: scrollView, withInset: Values.largeSpacing)
        contentStackView.pin(.trailing, to: .trailing, of: scrollView, withInset: -Values.largeSpacing)
        contentStackView.pin(.top, to: .top, of: scrollView, withInset: Values.largeSpacing)
        contentStackView.pin(.bottom, to: .bottom, of: scrollView, withInset: -Values.largeSpacing)
        contentStackView.set(.width, to: .width, of: scrollView, withOffset: -2 * Values.largeSpacing)
        
        // Header
        contentStackView.addArrangedSubview(headerLabel)
        contentStackView.addArrangedSubview(descriptionLabel)
        
        // Add placeholder content
        addPlaceholderContent()
    }
    
    private func addPlaceholderContent() {
        // This is a placeholder - you can add actual discovery features here
        let placeholderLabel = UILabel()
        placeholderLabel.font = .systemFont(ofSize: Values.smallFontSize)
        placeholderLabel.text = NSLocalizedString("更多功能即将推出", comment: "More features coming soon")
        placeholderLabel.themeTextColor = .textSecondary
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 0
        
        contentStackView.addArrangedSubview(placeholderLabel)
    }
}

