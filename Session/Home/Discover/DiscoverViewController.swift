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
        
        // Register cell
        tableView.register(MomentCell.self, forCellReuseIdentifier: "MomentCell")
        
        // Table view
        view.addSubview(tableView)
        tableView.pin(to: view)
    }
    
    private func bindViewModel() {
        viewModel.$moments
            .receive(on: DispatchQueue.main)
            .sink { [weak self] moments in
                guard let self = self else { return }
                self.tableView.reloadData()
                self.updateEmptyState(hasMoments: !moments.isEmpty)
            }
            .store(in: &cancellables)
        
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                guard let self = self else { return }
                self.updateLoadingState(isLoading: isLoading)
            }
            .store(in: &cancellables)
    }
    
    private func updateLoadingState(isLoading: Bool) {
        if isLoading {
            // Show loading indicator if needed
            tableView.backgroundView = nil
        }
    }
    
    private func updateEmptyState(hasMoments: Bool) {
        guard !viewModel.isLoading else { return }
        
        if !hasMoments {
            let emptyLabel = UILabel()
            emptyLabel.text = NSLocalizedString("还没有动态，快去发布一条吧！", comment: "No moments yet, go post one!")
            emptyLabel.font = .systemFont(ofSize: Values.mediumFontSize)
            emptyLabel.themeTextColor = .textSecondary
            emptyLabel.textAlignment = .center
            emptyLabel.numberOfLines = 0
            tableView.backgroundView = emptyLabel
        } else {
            tableView.backgroundView = nil
        }
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
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "MomentCell", for: indexPath) as! MomentCell
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
    private var imageLoadCancellables: Set<AnyCancellable> = []
    
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
    
    private lazy var commentsLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textPrimary
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
            commentsLabel,
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
        
        // Comments
        if !momentWithProfile.comments.isEmpty {
            let commentTexts = momentWithProfile.comments.map { commentWithProfile in
                let name = commentWithProfile.profile.displayName(for: .contact)
                let content = commentWithProfile.comment.content
                return "\(name): \(content)"
            }
            commentsLabel.text = commentTexts.joined(separator: "\n")
            commentsLabel.isHidden = false
        } else {
            commentsLabel.isHidden = true
        }
        
        // Load images
        loadImages(attachmentIds: momentWithProfile.imageAttachmentIds)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // Cancel any ongoing image loads
        imageLoadCancellables.removeAll()
        
        // Clear image stack view
        imageStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Reset labels
        likesLabel.text = nil
        likesLabel.isHidden = true
        commentsLabel.text = nil
        commentsLabel.isHidden = true
        
        // Reset state
        momentWithProfile = nil
        viewModel = nil
        dependencies = nil
    }
    
    private func loadImages(attachmentIds: [String]) {
        // Clear existing images
        imageStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        guard !attachmentIds.isEmpty, let dependencies = dependencies else { return }
        
        // Limit to 9 images for display
        let displayIds = Array(attachmentIds.prefix(9))
        
        // Create a grid layout for images
        let imagesPerRow = min(3, displayIds.count)
        let rows = Int(ceil(Double(displayIds.count) / Double(imagesPerRow)))
        
        for row in 0..<rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = Values.smallSpacing
            rowStack.distribution = .fillEqually
            rowStack.alignment = .fill
            
            let startIndex = row * imagesPerRow
            let endIndex = min(startIndex + imagesPerRow, displayIds.count)
            
            for index in startIndex..<endIndex {
                let attachmentId = displayIds[index]
                let imageView = SessionImageView()
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.layer.cornerRadius = 4
                imageView.themeBackgroundColor = .backgroundSecondary
                imageView.set(.width, to: 100)
                imageView.set(.height, to: 100)
                
                // Load image asynchronously
                loadImage(attachmentId: attachmentId, imageView: imageView, using: dependencies)
                
                rowStack.addArrangedSubview(imageView)
            }
            
            // Add spacing views to fill remaining space
            while rowStack.arrangedSubviews.count < imagesPerRow {
                let spacer = UIView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                rowStack.addArrangedSubview(spacer)
            }
            
            imageStackView.addArrangedSubview(rowStack)
        }
        
        // Show count if there are more images
        if attachmentIds.count > 9 {
            let moreLabel = UILabel()
            moreLabel.text = NSLocalizedString("还有 \(attachmentIds.count - 9) 张图片", comment: "More images")
            moreLabel.font = .systemFont(ofSize: Values.smallFontSize)
            moreLabel.themeTextColor = .textSecondary
            moreLabel.textAlignment = .center
            imageStackView.addArrangedSubview(moreLabel)
        }
    }
    
    private func loadImage(attachmentId: String, imageView: SessionImageView, using dependencies: Dependencies) {
        imageView.setDataManager(dependencies[singleton: .imageDataManager])
        
        // Fetch attachment from database
        let storage = dependencies[singleton: .storage]
        storage.read { db in
            guard let attachment: Attachment = try? Attachment.fetchOne(db, id: attachmentId) else {
                DispatchQueue.main.async {
                    // Show placeholder on error
                    imageView.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
                    imageView.themeTintColor = .textSecondary
                    imageView.contentMode = .center
                }
                return
            }
            
            // Load image using SessionImageView convenience method
            DispatchQueue.main.async {
                imageView.loadImage(attachment: attachment, using: dependencies) { [weak imageView] buffer in
                    guard let imageView = imageView else { return }
                    
                    if buffer == nil {
                        imageView.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
                        imageView.themeTintColor = .textSecondary
                        imageView.contentMode = .center
                    } else {
                        imageView.contentMode = .scaleAspectFill
                    }
                }
            }
        }
    }
    
    @objc private func likeButtonTapped() {
        guard let momentWithProfile = momentWithProfile,
              let momentId = momentWithProfile.moment.id,
              let viewModel = viewModel else { return }
        
        do {
            try viewModel.toggleLike(momentId: momentId)
        } catch {
            Log.error("[MomentCell] Failed to toggle like: \(error)")
            showErrorAlert(message: NSLocalizedString("操作失败，请重试", comment: "Operation failed, please try again"))
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
                  !content.trimmingCharacters(in: .whitespaces).isEmpty,
                  let viewModel = self.viewModel else { return }
            
            do {
                try viewModel.addComment(momentId: momentId, content: content)
            } catch {
                Log.error("[MomentCell] Failed to add comment: \(error)")
                self.showErrorAlert(message: NSLocalizedString("评论失败，请重试", comment: "Failed to add comment, please try again"))
            }
        })
        
        if let viewController = self.findViewController() {
            viewController.present(alert, animated: true)
        }
    }
}

private extension MomentCell {
    func showErrorAlert(message: String) {
        guard let viewController = self.findViewController() else { return }
        
        let alert = UIAlertController(
            title: NSLocalizedString("错误", comment: "Error"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("确定", comment: "OK"), style: .default))
        viewController.present(alert, animated: true)
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

