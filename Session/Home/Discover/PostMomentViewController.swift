// Copyright © 2025 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import PhotosUI
import SessionUIKit
import SessionUtilitiesKit
import SessionMessagingKit

/// Post Moment View Controller - For creating new moments
final class PostMomentViewController: BaseVC {
    private let dependencies: Dependencies
    private let viewModel: MomentsViewModel
    private var selectedImages: [UIImage] = []
    
    // MARK: - UI
    
    private lazy var scrollView: UIScrollView = {
        let result = UIScrollView()
        result.showsVerticalScrollIndicator = true
        result.alwaysBounceVertical = true
        return result
    }()
    
    private lazy var contentView: UIView = {
        let result = UIView()
        return result
    }()
    
    private lazy var textView: UITextView = {
        let result = UITextView()
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        result.themeBackgroundColor = .backgroundPrimary
        result.layer.cornerRadius = 8
        result.layer.borderWidth = 1
        result.themeBorderColor = .borderSeparator
        result.textContainerInset = UIEdgeInsets(
            top: Values.mediumSpacing,
            left: Values.mediumSpacing,
            bottom: Values.mediumSpacing,
            right: Values.mediumSpacing
        )
        result.delegate = self
        return result
    }()
    
    private lazy var placeholderLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textSecondary
        result.text = NSLocalizedString("分享你的生活...", comment: "Share your life...")
        return result
    }()
    
    private lazy var imageCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 100, height: 100)
        layout.minimumInteritemSpacing = Values.smallSpacing
        layout.minimumLineSpacing = Values.smallSpacing
        layout.sectionInset = UIEdgeInsets(
            top: Values.mediumSpacing,
            left: Values.mediumSpacing,
            bottom: Values.mediumSpacing,
            right: Values.mediumSpacing
        )
        
        let result = UICollectionView(frame: .zero, collectionViewLayout: layout)
        result.themeBackgroundColor = .backgroundPrimary
        result.dataSource = self
        result.delegate = self
        result.register(ImageCell.self, forCellWithReuseIdentifier: "ImageCell")
        return result
    }()
    
    private lazy var addImageButton: UIButton = {
        let result = UIButton(type: .system)
        result.setTitle(NSLocalizedString("📷 添加图片", comment: "Add Image"), for: .normal)
        result.titleLabel?.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTintColor = .primary
        result.addTarget(self, action: #selector(addImageButtonTapped), for: .touchUpInside)
        return result
    }()
    
    // MARK: - Initialization
    
    init(viewModel: MomentsViewModel, using dependencies: Dependencies) {
        self.dependencies = dependencies
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewModel:using:) instead.")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setNavBarTitle(NSLocalizedString("发布朋友圈", comment: "Post Moment"))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelButtonTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("发布", comment: "Post"),
            style: .done,
            target: self,
            action: #selector(postButtonTapped)
        )
        
        setupUI()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.pin(to: view)
        
        scrollView.addSubview(contentView)
        contentView.pin(.leading, to: .leading, of: scrollView)
        contentView.pin(.trailing, to: .trailing, of: scrollView)
        contentView.pin(.top, to: .top, of: scrollView)
        contentView.pin(.bottom, to: .bottom, of: scrollView)
        contentView.set(.width, to: .width, of: scrollView)
        
        // Text view container
        let textContainer = UIView()
        textContainer.addSubview(textView)
        textView.pin(to: textContainer, withInset: Values.mediumSpacing)
        textView.set(.height, to: 120)
        
        textContainer.addSubview(placeholderLabel)
        placeholderLabel.pin(.leading, to: .leading, of: textView, withInset: Values.mediumSpacing + 5)
        placeholderLabel.pin(.top, to: .top, of: textView, withInset: Values.mediumSpacing + 8)
        
        // Image collection view
        imageCollectionView.set(.height, to: selectedImages.isEmpty ? 0 : 120)
        
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [
            textContainer,
            addImageButton,
            imageCollectionView
        ])
        stackView.axis = .vertical
        stackView.spacing = Values.mediumSpacing
        stackView.alignment = .fill
        
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView)
        stackView.pin(.trailing, to: .trailing, of: contentView)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.mediumSpacing)
        stackView.pin(.bottom, to: .bottom, of: contentView, withInset: -Values.mediumSpacing)
    }
    
    // MARK: - Actions
    
    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func postButtonTapped() {
        let content = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 验证：至少需要文本或图片
        guard !content.isEmpty || !selectedImages.isEmpty else {
            let alert = UIAlertController(
                title: NSLocalizedString("提示", comment: "Alert"),
                message: NSLocalizedString("请输入文字或添加图片", comment: "Please enter text or add image"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("确定", comment: "OK"), style: .default))
            present(alert, animated: true)
            return
        }
        
        // 保存图片到临时目录并获取路径（简化版：使用 base64 编码存储，实际应该上传到服务器）
        let imageAttachmentIds: [String] = selectedImages.map { image in
            // 简化处理：使用 UUID 作为临时 ID
            // 实际应用中应该上传图片到服务器并获取真实的 attachment ID
            UUID().uuidString
        }
        
        do {
            try viewModel.createMoment(
                content: content.isEmpty ? nil : content,
                imageAttachmentIds: imageAttachmentIds
            )
            dismiss(animated: true)
        } catch {
            Log.error("[PostMomentViewController] Failed to create moment: \(error)")
            let alert = UIAlertController(
                title: NSLocalizedString("错误", comment: "Error"),
                message: NSLocalizedString("发布失败", comment: "Post failed"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("确定", comment: "OK"), style: .default))
            present(alert, animated: true)
        }
    }
    
    @objc private func addImageButtonTapped() {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 9 - selectedImages.count
        configuration.filter = .images
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }
    
}

// MARK: - UITextViewDelegate

extension PostMomentViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
    }
}

// MARK: - PHPickerViewControllerDelegate

extension PostMomentViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard !results.isEmpty else { return }
        
        let group = DispatchGroup()
        var newImages: [UIImage] = []
        
        for result in results {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                defer { group.leave() }
                guard let image = object as? UIImage else { return }
                newImages.append(image)
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.selectedImages.append(contentsOf: newImages)
            self.imageCollectionView.reloadData()
            self.imageCollectionView.set(.height, to: self.selectedImages.isEmpty ? 0 : 120)
        }
    }
}

// MARK: - UICollectionViewDataSource

extension PostMomentViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return selectedImages.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageCell", for: indexPath) as! ImageCell
        let imageIndex = indexPath.item
        cell.configure(image: selectedImages[imageIndex])
        cell.onDelete = { [weak self] in
            guard let self = self else { return }
            self.selectedImages.remove(at: imageIndex)
            self.imageCollectionView.reloadData()
            self.imageCollectionView.set(.height, to: self.selectedImages.isEmpty ? 0 : 120)
        }
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension PostMomentViewController: UICollectionViewDelegate {
    // No additional delegate methods needed
}

// MARK: - ImageCell

private class ImageCell: UICollectionViewCell {
    var onDelete: (() -> Void)?
    
    private lazy var imageView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFill
        result.clipsToBounds = true
        result.layer.cornerRadius = 8
        return result
    }()
    
    private lazy var deleteButton: UIButton = {
        let result = UIButton(type: .system)
        result.setTitle("×", for: .normal)
        result.titleLabel?.font = .boldSystemFont(ofSize: 24)
        result.themeTintColor = .textPrimary
        result.themeBackgroundColor = .backgroundSecondary
        result.layer.cornerRadius = 12
        result.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        return result
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentView.addSubview(imageView)
        imageView.pin(to: contentView)
        
        contentView.addSubview(deleteButton)
        deleteButton.set(.width, to: 24)
        deleteButton.set(.height, to: 24)
        deleteButton.pin(.trailing, to: .trailing, of: contentView, withInset: -8)
        deleteButton.pin(.top, to: .top, of: contentView, withInset: -8)
    }
    
    func configure(image: UIImage) {
        imageView.image = image
    }
    
    @objc private func deleteButtonTapped() {
        onDelete?()
    }
}

// MARK: - AddImageCell (not used but registered)

private class AddImageCell: UICollectionViewCell {
    // This cell is registered but not used in the current implementation
}

