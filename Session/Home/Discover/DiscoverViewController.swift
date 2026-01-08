// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine
import GRDB
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
    private var attachmentObservations: [String: DatabaseCancellable] = [:]
    
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
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        result.lineBreakMode = .byCharWrapping
        return result
    }()
    
    private lazy var commentsLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        result.lineBreakMode = .byCharWrapping
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
        
        // 点赞和评论容器
        let interactionContainer = UIStackView(arrangedSubviews: [likesLabel, commentsLabel])
        interactionContainer.axis = .vertical
        interactionContainer.spacing = Values.smallSpacing
        interactionContainer.alignment = .leading
        
        let contentStack = UIStackView(arrangedSubviews: [
            headerStack,
            contentLabel,
            imageStackView,
            timeLabel,
            interactionContainer,
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
        
        // Time - 显示相对时间（如"2天前"）
        let date = Date(timeIntervalSince1970: Double(momentWithProfile.moment.timestampMs) / 1000)
        timeLabel.text = formatRelativeTime(from: date)
        
        // Likes - 改进显示样式，使用中文分隔符
        if !momentWithProfile.likes.isEmpty {
            let names = momentWithProfile.likes.map { $0.profile.displayName(for: .contact) }
            let text = names.joined(separator: "、")
            likesLabel.text = "❤️ \(text)"
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
        
        // Comments - 改进显示样式，支持回复
        if !momentWithProfile.comments.isEmpty {
            let commentTexts = momentWithProfile.comments.map { commentWithProfile in
                let name = commentWithProfile.profile.displayName(for: .contact)
                let content = commentWithProfile.comment.content
                // 检查是否是回复评论（可以通过内容格式判断，或者添加replyTo字段）
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
        
        // Cancel attachment observations
        attachmentObservations.values.forEach { $0.cancel() }
        attachmentObservations.removeAll()
        
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
        
        // 计算图片尺寸 - 根据图片数量调整
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = Values.largeSpacing * 2
        let availableWidth = screenWidth - padding
        let spacing: CGFloat = Values.smallSpacing
        let imagesPerRow: Int
        let imageSize: CGFloat
        
        // 根据图片数量决定每行显示几个和图片大小
        switch displayIds.count {
        case 1:
            // 单张图片显示更大
            imagesPerRow = 1
            imageSize = min(availableWidth * 0.7, 300) // 最大宽度为屏幕的70%或300点
        case 2, 4:
            imagesPerRow = 2
            imageSize = (availableWidth - spacing) / 2
        default:
            imagesPerRow = 3
            imageSize = (availableWidth - CGFloat(imagesPerRow - 1) * spacing) / CGFloat(imagesPerRow)
        }
        
        let rows = Int(ceil(Double(displayIds.count) / Double(imagesPerRow)))
        
        for row in 0..<rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = spacing
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
                imageView.set(.width, to: imageSize)
                imageView.set(.height, to: imageSize)
                
                // Load image asynchronously
                loadImage(attachmentId: attachmentId, imageView: imageView, using: dependencies)
                
                rowStack.addArrangedSubview(imageView)
            }
            
            // 如果这一行图片数量不足，添加占位视图
            while rowStack.arrangedSubviews.count < imagesPerRow {
                let spacer = UIView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                rowStack.addArrangedSubview(spacer)
            }
            
            imageStackView.addArrangedSubview(rowStack)
        }
    }
    
    private func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return NSLocalizedString("刚刚", comment: "Just now")
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return String(format: NSLocalizedString("%d分钟前", comment: "%d minutes ago"), minutes)
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return String(format: NSLocalizedString("%d小时前", comment: "%d hours ago"), hours)
        } else if timeInterval < 604800 {
            let days = Int(timeInterval / 86400)
            return String(format: NSLocalizedString("%d天前", comment: "%d days ago"), days)
        } else if timeInterval < 2592000 {
            let weeks = Int(timeInterval / 604800)
            return String(format: NSLocalizedString("%d周前", comment: "%d weeks ago"), weeks)
        } else if timeInterval < 31536000 {
            let months = Int(timeInterval / 2592000)
            return String(format: NSLocalizedString("%d个月前", comment: "%d months ago"), months)
        } else {
            let years = Int(timeInterval / 31536000)
            return String(format: NSLocalizedString("%d年前", comment: "%d years ago"), years)
        }
    }
    
    private func loadImage(attachmentId: String, imageView: SessionImageView, using dependencies: Dependencies) {
        imageView.setDataManager(dependencies[singleton: .imageDataManager])
        
        // Cancel previous observation for this attachment
        attachmentObservations[attachmentId]?.cancel()
        
        // Fetch attachment from database and observe state changes
        let storage = dependencies[singleton: .storage]
        let observation = ValueObservation.trackingConstantRegion { db -> Attachment? in
            try? Attachment.fetchOne(db, id: attachmentId)
        }
        
        let cancellable = storage.start(
            observation,
            scheduling: .async(onQueue: .main),
            onError: { error in
                Log.error("[MomentCell] Attachment observation failed: \(error)")
            },
            onChange: { [weak self, weak imageView] attachment in
                guard let self = self, let imageView = imageView else { return }
                
                guard let attachment = attachment else {
                    Log.warn("[MomentCell] Attachment not found: \(attachmentId)")
                    imageView.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
                    imageView.themeTintColor = .textSecondary
                    imageView.contentMode = .center
                    return
                }
                
                // If still downloading, show placeholder and wait
                if attachment.state == .pendingDownload || attachment.state == .downloading {
                    Log.info("[MomentCell] Attachment downloading: \(attachmentId), state: \(attachment.state)")
                    imageView.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
                    imageView.themeTintColor = .textSecondary
                    imageView.contentMode = .center
                    return
                }
                
                // If download failed, show placeholder
                if attachment.state == .failedDownload {
                    Log.warn("[MomentCell] Attachment download failed: \(attachmentId)")
                    imageView.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
                    imageView.themeTintColor = .textSecondary
                    imageView.contentMode = .center
                    return
                }
                
                // If downloaded or uploaded, load the image
                guard attachment.state == .downloaded || attachment.state == .uploaded else {
                    print("⚠️ [MomentCell] Attachment state is not ready: \(attachment.state) for \(attachmentId)")
                    return
                }
                
                print("🟢 [MomentCell] Attachment ready, loading image: \(attachmentId), state: \(attachment.state)")
                
                // Cancel observation once we have the image
                self.attachmentObservations[attachmentId]?.cancel()
                self.attachmentObservations.removeValue(forKey: attachmentId)
                
                // For both uploaded and downloaded states, try to load directly from file first
                if let downloadUrl = attachment.downloadUrl {
                    let attachmentManager = dependencies[singleton: .attachmentManager]
                    print("🟢 [MomentCell] Trying to load image from file for attachment: \(attachmentId)")
                    print("🟢 [MomentCell] DownloadUrl: \(downloadUrl)")
                    
                    if let path = try? attachmentManager.path(for: downloadUrl) {
                        print("🟢 [MomentCell] File path: \(path)")
                        
                        // Check if file exists
                        let fileManager = dependencies[singleton: .fileManager]
                        if fileManager.fileExists(atPath: path) {
                            print("🟢 [MomentCell] File exists, loading image data...")
                            if let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                                print("🟢 [MomentCell] Loaded \(imageData.count) bytes from file")
                                
                                // Check file header to see what format it is
                                if imageData.count >= 4 {
                                    let header = imageData.prefix(4).map { String(format: "%02x", $0) }.joined()
                                    print("🟢 [MomentCell] File header (hex): \(header)")
                                    
                                    // Check for common image formats
                                    if header.hasPrefix("ffd8") {
                                        print("🟢 [MomentCell] Detected JPEG format")
                                    } else if header.hasPrefix("8950") {
                                        print("🟢 [MomentCell] Detected PNG format")
                                    } else if header.hasPrefix("5249") {
                                        print("🟢 [MomentCell] Detected WebP format (RIFF)")
                                    } else {
                                        print("⚠️ [MomentCell] Unknown file format, header: \(header)")
                                    }
                                }
                                
                                // Try to create UIImage
                                if let image = UIImage(data: imageData) {
                                    print("✅ [MomentCell] Successfully created UIImage, size: \(image.size)")
                                    imageView.image = image
                                    imageView.contentMode = .scaleAspectFill
                                    return
                                } else {
                                    print("❌ [MomentCell] Failed to create UIImage from data")
                                    print("❌ [MomentCell] Data size: \(imageData.count) bytes")
                                    
                                    // Try using ImageIO directly
                                    if let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
                                       let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                                        let uiImage = UIImage(cgImage: cgImage)
                                        print("✅ [MomentCell] Successfully created UIImage using ImageIO")
                                        imageView.image = uiImage
                                        imageView.contentMode = .scaleAspectFill
                                        return
                                    } else {
                                        print("❌ [MomentCell] Failed to create image using ImageIO as well")
                                    }
                                }
                            } else {
                                print("❌ [MomentCell] Failed to read data from file")
                            }
                        } else {
                            print("❌ [MomentCell] File does not exist at path: \(path)")
                        }
                    } else {
                        print("❌ [MomentCell] Failed to get file path for downloadUrl: \(downloadUrl)")
                    }
                } else {
                    print("❌ [MomentCell] Attachment has no downloadUrl: \(attachmentId)")
                }
                
                // Fallback: Load image using SessionImageView convenience method
                print("🟢 [MomentCell] Trying SessionImageView.loadImage for attachment: \(attachmentId)")
                print("🟢 [MomentCell] Attachment state: \(attachment.state), downloadUrl: \(attachment.downloadUrl ?? "nil")")
                print("🟢 [MomentCell] Attachment isVisualMedia: \(attachment.isVisualMedia)")
                
                // Check if ImageDataManager.DataSource.from can create a source
                if let source = ImageDataManager.DataSource.from(attachment: attachment, using: dependencies) {
                    print("🟢 [MomentCell] Created ImageDataManager.DataSource successfully")
                    imageView.loadImage(source) { [weak imageView] buffer in
                        guard let imageView = imageView else { return }
                        
                        if buffer == nil {
                            print("❌ [MomentCell] Failed to load image for attachment: \(attachmentId)")
                            Log.warn("[MomentCell] Failed to load image for attachment: \(attachmentId)")
                            imageView.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
                            imageView.themeTintColor = .textSecondary
                            imageView.contentMode = .center
                        } else {
                            print("✅ [MomentCell] Successfully loaded image using SessionImageView for attachment: \(attachmentId)")
                            imageView.contentMode = .scaleAspectFill
                        }
                    }
                } else {
                    print("❌ [MomentCell] Failed to create ImageDataManager.DataSource for attachment: \(attachmentId)")
                    imageView.image = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)
                    imageView.themeTintColor = .textSecondary
                    imageView.contentMode = .center
                }
            }
        )
        
        attachmentObservations[attachmentId] = cancellable
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

