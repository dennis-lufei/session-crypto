// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine
import SessionUIKit
import SessionUtilitiesKit
import SessionMessagingKit

/// Discover View Controller - Shows discovery features and content (Moments/朋友圈)
public final class DiscoverViewController: BaseVC {
    private let dependencies: Dependencies
    private let viewModel: MomentsViewModel
    private var cancellables: Set<AnyCancellable> = []
    
    // MARK: - UI
    
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.showsVerticalScrollIndicator = true
        result.dataSource = self
        result.delegate = self
        result.sectionHeaderTopPadding = 0
        
        return result
    }()
    
    private lazy var composeButton: UIButton = {
        let result = UIButton(type: .system)
        result.setTitle(NSLocalizedString("发布", comment: "Compose"), for: .normal)
        result.titleLabel?.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTintColor = .primary
        result.addTarget(self, action: #selector(composeButtonTapped), for: .touchUpInside)
        
        return result
    }()
    
    // MARK: - Initialization
    
    public init(using dependencies: Dependencies) {
        self.dependencies = dependencies
        self.viewModel = MomentsViewModel(using: dependencies)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(using:) instead.")
    }
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setNavBarTitle(NSLocalizedString("朋友圈", comment: "Moments"))
        
        setupUI()
        bindViewModel()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        // Navigation bar button
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: composeButton)
        
        // Table view
        view.addSubview(tableView)
        tableView.pin(to: view)
    }
    
    private func bindViewModel() {
        viewModel.$moments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
        
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                // Handle loading state if needed
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    @objc private func composeButtonTapped() {
        let postVC = PostMomentViewController(viewModel: viewModel, using: dependencies)
        let navController = StyledNavigationController(rootViewController: postVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension DiscoverViewController: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.moments.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let momentWithProfile = viewModel.moments[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "MomentCell") as? MomentCell ?? MomentCell(style: .default, reuseIdentifier: "MomentCell")
        cell.configure(
            with: momentWithProfile,
            viewModel: viewModel,
            dependencies: dependencies
        )
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension DiscoverViewController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 200
    }
}

// MARK: - MomentCell

private class MomentCell: UITableViewCell {
    private var momentWithProfile: MomentsViewModel.MomentWithProfile?
    private weak var viewModel: MomentsViewModel?
    private var dependencies: Dependencies?
    
    private lazy var profilePictureView: ProfilePictureView = ProfilePictureView(size: .list, dataManager: nil)
    
    private lazy var nameLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        return result
    }()
    
    private lazy var contentLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        return result
    }()
    
    private lazy var imageStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        result.spacing = Values.smallSpacing
        result.alignment = .fill
        return result
    }()
    
    private lazy var timeLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textSecondary
        return result
    }()
    
    private lazy var likeButton: UIButton = {
        let result = UIButton(type: .system)
        result.setTitle(NSLocalizedString("👍 赞", comment: "Like"), for: .normal)
        result.titleLabel?.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTintColor = .primary
        result.addTarget(self, action: #selector(likeButtonTapped), for: .touchUpInside)
        return result
    }()
    
    private lazy var commentButton: UIButton = {
        let result = UIButton(type: .system)
        result.setTitle(NSLocalizedString("💬 评论", comment: "Comment"), for: .normal)
        result.titleLabel?.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTintColor = .primary
        result.addTarget(self, action: #selector(commentButtonTapped), for: .touchUpInside)
        return result
    }()
    
    private lazy var likesLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textSecondary
        result.numberOfLines = 0
        return result
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        selectionStyle = .none
        themeBackgroundColor = .backgroundPrimary
        
        let headerStack = UIStackView(arrangedSubviews: [profilePictureView, nameLabel])
        headerStack.axis = .horizontal
        headerStack.spacing = Values.mediumSpacing
        headerStack.alignment = .center
        
        let actionStack = UIStackView(arrangedSubviews: [likeButton, commentButton])
        actionStack.axis = .horizontal
        actionStack.spacing = Values.largeSpacing
        
        let contentStack = UIStackView(arrangedSubviews: [
            headerStack,
            contentLabel,
            imageStackView,
            timeLabel,
            likesLabel,
            actionStack
        ])
        contentStack.axis = .vertical
        contentStack.spacing = Values.mediumSpacing
        contentStack.alignment = .leading
        
        contentView.addSubview(contentStack)
        contentStack.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        contentStack.pin(.trailing, to: .trailing, of: contentView, withInset: -Values.largeSpacing)
        contentStack.pin(.top, to: .top, of: contentView, withInset: Values.mediumSpacing)
        contentStack.pin(.bottom, to: .bottom, of: contentView, withInset: -Values.mediumSpacing)
        
        profilePictureView.set(.width, to: 40)
        profilePictureView.set(.height, to: 40)
    }
    
    func configure(
        with momentWithProfile: MomentsViewModel.MomentWithProfile,
        viewModel: MomentsViewModel,
        dependencies: Dependencies
    ) {
        self.momentWithProfile = momentWithProfile
        self.viewModel = viewModel
        self.dependencies = dependencies
        
        // Set data manager if not already set
        profilePictureView.setDataManager(dependencies[singleton: .imageDataManager])
        
        let profile = momentWithProfile.profile
        nameLabel.text = profile.displayName(for: .contact)
        contentLabel.text = momentWithProfile.moment.content
        contentLabel.isHidden = (momentWithProfile.moment.content?.isEmpty ?? true)
        
        // Profile picture
        profilePictureView.update(
            publicKey: profile.id,
            threadVariant: .contact,
            displayPictureUrl: profile.displayPictureUrl,
            profile: profile,
            using: dependencies
        )
        
        // Time
        let date = Date(timeIntervalSince1970: Double(momentWithProfile.moment.timestampMs) / 1000)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        timeLabel.text = formatter.string(from: date)
        
        // Likes
        if !momentWithProfile.likes.isEmpty {
            let names = momentWithProfile.likes.prefix(3).map { $0.profile.displayName(for: .contact) }
            let moreCount = momentWithProfile.likes.count - 3
            let text = names.joined(separator: ", ") + (moreCount > 0 ? " 等\(momentWithProfile.likes.count)人" : "")
            likesLabel.text = "👍 \(text)"
            likesLabel.isHidden = false
        } else {
            likesLabel.isHidden = true
        }
        
        // Like button state
        if momentWithProfile.isLikedByCurrentUser {
            likeButton.setTitle(NSLocalizedString("👍 已赞", comment: "Liked"), for: .normal)
        } else {
            likeButton.setTitle(NSLocalizedString("👍 赞", comment: "Like"), for: .normal)
        }
        
        // Images (simplified - would need proper image loading)
        imageStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if !momentWithProfile.imageAttachmentIds.isEmpty {
            let placeholderLabel = UILabel()
            placeholderLabel.text = "📷 \(momentWithProfile.imageAttachmentIds.count) 张图片"
            placeholderLabel.font = .systemFont(ofSize: Values.smallFontSize)
            placeholderLabel.themeTextColor = .textSecondary
            imageStackView.addArrangedSubview(placeholderLabel)
        }
    }
    
    @objc private func likeButtonTapped() {
        guard let momentWithProfile = momentWithProfile,
              let momentId = momentWithProfile.moment.id else { return }
        
        do {
            try viewModel?.toggleLike(momentId: momentId)
        } catch {
            Log.error("[MomentCell] Failed to toggle like: \(error)")
        }
    }
    
    @objc private func commentButtonTapped() {
        guard let momentWithProfile = momentWithProfile,
              let momentId = momentWithProfile.moment.id else { return }
        
        let alert = UIAlertController(
            title: NSLocalizedString("评论", comment: "Comment"),
            message: nil,
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("输入评论...", comment: "Enter comment...")
        }
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("发送", comment: "Send"), style: .default) { [weak self] _ in
            guard let self = self,
                  let textField = alert.textFields?.first,
                  let content = textField.text,
                  !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            
            do {
                try self.viewModel?.addComment(momentId: momentId, content: content)
            } catch {
                Log.error("[MomentCell] Failed to add comment: \(error)")
            }
        })
        
        if let viewController = self.findViewController() {
            viewController.present(alert, animated: true)
        }
    }
}

private extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}

