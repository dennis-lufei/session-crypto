// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

private protocol TableViewTouchDelegate {
    func tableViewWasTouched(_ tableView: TableView, withView hitView: UIView?)
}

private final class TableView: UITableView {
    var touchDelegate: TableViewTouchDelegate?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let resultingView: UIView? = super.hitTest(point, with: event)
        touchDelegate?.tableViewWasTouched(self, withView: resultingView)
        
        return resultingView
    }
}

final class NewClosedGroupVC: BaseVC, UITableViewDataSource, UITableViewDelegate, TableViewTouchDelegate, UITextFieldDelegate, UIScrollViewDelegate {
    private enum Section: Int, Differentiable, Equatable, Hashable {
        case contacts
    }
    
    private let dependencies: Dependencies
    private let contacts: [WithProfile<Contact>]
    private let hideCloseButton: Bool
    private let prefilledName: String?
    private lazy var data: [ArraySection<Section, WithProfile<Contact>>] = [
        ArraySection(model: .contacts, elements: contacts)
    ]
    private var selectedProfileIds: Set<String> = [] {
        didSet {
            updateSelectedAvatarsView()
            updateCreateButtonState()
        }
    }
    private var searchText: String = ""
    
    // MARK: - Initialization
    
    init(
        hideCloseButton: Bool = false,
        prefilledName: String? = nil,
        preselectedContactIds: [String] = [],
        using dependencies: Dependencies
    ) {
        self.dependencies = dependencies
        self.hideCloseButton = hideCloseButton
        self.prefilledName = prefilledName
        
        let currentUserSessionId: SessionId = dependencies[cache: .general].sessionId
        let finalPreselectedContactIds: Set<String> = Set(preselectedContactIds)
            .subtracting([currentUserSessionId.hexString])
        
        // FIXME: This should be changed to be an async process (ideally coming from a view model)
        self.contacts = dependencies[singleton: .storage]
            .read { db in
                let contact: TypedTableAlias<Contact> = TypedTableAlias()
                let request: SQLRequest<Contact> = """
                    SELECT \(contact.allColumns)
                    FROM \(contact)
                    WHERE (
                        \(SQL("\(contact[.id]) != \(currentUserSessionId.hexString)")) AND (
                            \(contact[.id]) IN \(Set(finalPreselectedContactIds)) OR (
                                \(contact[.isApproved]) = TRUE AND
                                \(contact[.didApproveMe]) = TRUE AND
                                \(contact[.isBlocked]) = FALSE
                            )
                        )
                    )
                """
                
                let fetchedResults: [WithProfile<Contact>] = try request.fetchAllWithProfiles(
                    db,
                    using: dependencies
                )
                let missingIds: Set<String> = finalPreselectedContactIds
                    .subtracting(fetchedResults.map { $0.profileId })
                
                return fetchedResults
                    .appending(contentsOf: missingIds.map {
                        WithProfile(
                            value: Contact(id: $0, currentUserSessionId: currentUserSessionId),
                            profile: nil,
                            currentUserSessionId: currentUserSessionId
                        )
                    })
            }
            .defaulting(to: [])
            .sorted()
        
        self.selectedProfileIds = finalPreselectedContactIds
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Components
    
    private static let searchBarHeight: CGFloat = (36 + (Values.mediumSpacing * 2))
    private static let avatarSize: CGFloat = 24
    private static let avatarContainerHeight: CGFloat = 60
    
    private let contentStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.axis = .vertical
        result.distribution = .fill
        
        return result
    }()
    
    private lazy var searchBar: ContactsSearchBar = {
        let result = ContactsSearchBar()
        result.themeTintColor = .textPrimary
        result.themeBackgroundColor = .clear
        result.delegate = self
        result.searchTextField.accessibilityIdentifier = "Search contacts field"
        result.set(.height, to: NewClosedGroupVC.searchBarHeight)
        
        // 修改placeholder为"搜索"
        result.searchTextField.themeAttributedPlaceholder = ThemedAttributedString(
            string: "搜索",
            attributes: [
                .themeForegroundColor: ThemeValue.textSecondary
            ]
        )
        
        return result
    }()
    
    // 已选择联系人头像容器（在搜索框下方）
    private lazy var selectedAvatarsContainer: UIView = {
        let result = UIView()
        result.themeBackgroundColor = .clear
        result.set(.height, to: NewClosedGroupVC.avatarContainerHeight)
        result.clipsToBounds = true
        result.isHidden = true // 初始隐藏
        
        return result
    }()
    
    private lazy var selectedAvatarsScrollView: UIScrollView = {
        let result = UIScrollView()
        result.showsHorizontalScrollIndicator = false
        result.showsVerticalScrollIndicator = false
        result.themeBackgroundColor = .clear
        result.set(.height, to: NewClosedGroupVC.avatarContainerHeight)
        
        return result
    }()
    
    private lazy var selectedAvatarsStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .horizontal
        result.spacing = Values.smallSpacing
        result.alignment = .center
        result.distribution = .fill
        
        return result
    }()
    
    private var searchBarTopConstraint: NSLayoutConstraint?
    private var searchBarCenterYConstraint: NSLayoutConstraint?
    
    private lazy var headerView: UIView = {
        let result: UIView = UIView(
            frame: CGRect(
                x: 0, y: 0,
                width: UIScreen.main.bounds.width,
                height: NewClosedGroupVC.searchBarHeight
            )
        )
        
        // 搜索框 - 左右padding改为16px
        result.addSubview(searchBar)
        searchBar.pin(.leading, to: .leading, of: result, withInset: 16)
        searchBar.pin(.trailing, to: .trailing, of: result, withInset: -16)
        
        // 初始状态：没有选中联系人时，搜索框垂直居中
        searchBarCenterYConstraint = searchBar.center(.vertical, in: result)
        searchBarCenterYConstraint?.isActive = true
        
        // 已选择联系人头像容器（在搜索框下方）
        result.addSubview(selectedAvatarsContainer)
        selectedAvatarsContainer.pin(.top, to: .bottom, of: searchBar, withInset: Values.smallSpacing)
        selectedAvatarsContainer.pin(.leading, to: .leading, of: result, withInset: 16)
        selectedAvatarsContainer.pin(.trailing, to: .trailing, of: result, withInset: -16)
        selectedAvatarsContainer.pin(.bottom, to: .bottom, of: result)
        
        selectedAvatarsContainer.addSubview(selectedAvatarsScrollView)
        selectedAvatarsScrollView.pin(to: selectedAvatarsContainer)
        
        selectedAvatarsScrollView.addSubview(selectedAvatarsStackView)
        selectedAvatarsStackView.pin(.top, to: .top, of: selectedAvatarsScrollView)
        selectedAvatarsStackView.pin(.leading, to: .leading, of: selectedAvatarsScrollView)
        selectedAvatarsStackView.pin(.trailing, to: .trailing, of: selectedAvatarsScrollView)
        selectedAvatarsStackView.pin(.bottom, to: .bottom, of: selectedAvatarsScrollView)
        selectedAvatarsStackView.set(.height, to: NewClosedGroupVC.avatarContainerHeight)
        
        return result
    }()

    private lazy var tableView: TableView = {
        let result: TableView = TableView()
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.tableHeaderView = headerView
        result.contentInset = UIEdgeInsets(
            top: 0,
            leading: 0,
            bottom: Values.footerGradientHeight(window: UIApplication.shared.keyWindow),
            trailing: 0
        )
        result.register(view: SessionCell.self)
        result.touchDelegate = self
        result.dataSource = self
        result.delegate = self
        result.sectionHeaderTopPadding = 0
        
        return result
    }()
    
    private lazy var fadeView: GradientView = {
        let result: GradientView = GradientView()
        result.themeBackgroundGradient = [
            .value(.backgroundSecondary, alpha: 0), // Want this to take up 20% (~25pt)
            .backgroundSecondary,
            .backgroundSecondary,
            .backgroundSecondary,
            .backgroundSecondary
        ]
        result.set(.height, to: Values.footerGradientHeight(window: UIApplication.shared.keyWindow))
        
        return result
    }()
    
    private lazy var createButton: UIBarButtonItem = {
        let result = UIBarButtonItem(
            title: "完成",
            style: .plain,
            target: self,
            action: #selector(createClosedGroup)
        )
        result.themeTintColor = .primary
        result.accessibilityIdentifier = "Create group"
        result.isAccessibilityElement = true
        result.isEnabled = false // 初始状态禁用
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.themeBackgroundColor = .backgroundSecondary
        
        let customTitleFontSize = Values.largeFontSize
        setNavBarTitle("发起群聊", customFontSize: customTitleFontSize)
        
        // 初始化crossfadeLabel文本
        crossfadeLabel.text = "发起群聊"
        
        // 设置右上角创建按钮
        navigationItem.rightBarButtonItem = createButton
        updateCreateButtonState()
        
        // 设置左侧返回/关闭按钮
        if !hideCloseButton {
            let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
            closeButton.themeTintColor = .textPrimary
            navigationItem.leftBarButtonItem = closeButton
            navigationItem.leftBarButtonItem?.accessibilityIdentifier = "Cancel"
            navigationItem.leftBarButtonItem?.isAccessibilityElement = true
        } else {
            // 即使hideCloseButton为true，也确保有返回按钮
            let backButton = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
            navigationItem.backBarButtonItem = backButton
        }
        
        // Set up content
        setUpViewHierarchy()
        
        // 初始化已选用户头像视图
        updateSelectedAvatarsView()
    }

    private func setUpViewHierarchy() {
        guard !contacts.isEmpty else {
            let explanationLabel: UILabel = UILabel()
            explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
            explanationLabel.text = "contactNone".localized()
            explanationLabel.themeTextColor = .textSecondary
            explanationLabel.textAlignment = .center
            explanationLabel.lineBreakMode = .byWordWrapping
            explanationLabel.numberOfLines = 0
            
            view.addSubview(explanationLabel)
            explanationLabel.pin(.top, to: .top, of: view, withInset: Values.largeSpacing)
            explanationLabel.center(.horizontal, in: view)
            return
        }
        
        view.addSubview(contentStackView)
        contentStackView.pin(.top, to: .top, of: view)
        contentStackView.pin(.leading, to: .leading, of: view)
        contentStackView.pin(.trailing, to: .trailing, of: view)
        contentStackView.pin(.bottom, to: .bottom, of: view)
        
        contentStackView.addArrangedSubview(tableView)
        
        view.addSubview(fadeView)
        fadeView.pin(.leading, to: .leading, of: view)
        fadeView.pin(.trailing, to: .trailing, of: view)
        fadeView.pin(.bottom, to: .bottom, of: view)
    }
    
    // MARK: - Table View Data Source
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data[section].elements.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: SessionCell = tableView.dequeue(type: SessionCell.self, for: indexPath)
        let item: WithProfile<Contact> = data[indexPath.section].elements[indexPath.row]
        cell.update(
            with: SessionCell.Info(
                id: item.profileId,
                position: Position.with(indexPath.row, count: data[indexPath.section].elements.count),
                leadingAccessory: .profile(id: item.profileId, profile: item.profile),
                title: (item.profile?.displayName() ?? item.profileId.truncated()),
                trailingAccessory: .radio(isSelected: selectedProfileIds.contains(item.profileId)),
                styling: SessionCell.StyleInfo(
                    backgroundStyle: .edgeToEdge
                ),
                accessibility: Accessibility(
                    identifier: "Contact"
                )
            ),
            tableSize: tableView.bounds.size,
            using: dependencies
        )
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item: WithProfile<Contact> = data[indexPath.section].elements[indexPath.row]
        
        if selectedProfileIds.contains(item.profileId) {
            selectedProfileIds.remove(item.profileId)
        }
        else {
            selectedProfileIds.insert(item.profileId)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        tableView.reloadRows(at: [indexPath], with: .none)
    }
    
    // MARK: - Interaction

    fileprivate func tableViewWasTouched(_ tableView: TableView, withView hitView: UIView?) {
        if searchBar.isFirstResponder {
            var hitSuperview: UIView? = hitView?.superview
            
            while hitSuperview != nil && hitSuperview != searchBar {
                hitSuperview = hitSuperview?.superview
            }
            
            // If the user hit the cancel button then do nothing (we want to let the cancel
            // button remove the focus or it will instantly refocus)
            if hitSuperview == searchBar { return }
            
            searchBar.resignFirstResponder()
        }
    }
    
    @objc private func close() {
        // 如果是从navigationController push进来的，则pop；否则dismiss
        if navigationController?.viewControllers.count ?? 0 > 1 {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true, completion: nil)
        }
    }
    
    // MARK: - Selected Avatars Management
    
    private func updateSelectedAvatarsView() {
        // 清除现有的头像视图
        selectedAvatarsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // 添加已选择用户的头像
        for profileId in selectedProfileIds.sorted() {
            guard let contact = contacts.first(where: { $0.profileId == profileId }) else { continue }
            
            let avatarView = ProfilePictureView(
                size: .list,
                dataManager: dependencies[singleton: .imageDataManager]
            )
            
            let (info, _) = ProfilePictureView.Info.generateInfoFrom(
                size: .list,
                publicKey: contact.profileId,
                threadVariant: .contact,
                displayPictureUrl: nil,
                profile: contact.profile,
                using: dependencies
            )
            
            if let profileInfo = info {
                avatarView.update(profileInfo)
            }
            
            // 添加删除按钮
            let containerView = UIView()
            containerView.addSubview(avatarView)
            
            let deleteButton = UIButton(type: .custom)
            deleteButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            deleteButton.tintColor = .systemRed
            deleteButton.backgroundColor = .white
            deleteButton.layer.cornerRadius = 10
            deleteButton.clipsToBounds = true
            deleteButton.addTarget(self, action: #selector(removeSelectedContact(_:)), for: .touchUpInside)
            // 使用profileId作为标识符存储
            deleteButton.accessibilityIdentifier = profileId
            containerView.addSubview(deleteButton)
            
            avatarView.pin(to: containerView)
            deleteButton.set(.width, to: 20)
            deleteButton.set(.height, to: 20)
            deleteButton.pin(.top, to: .top, of: containerView, withInset: -5)
            // delete button往右凸出自己一半的width（20/2 = 10）
            deleteButton.pin(.trailing, to: .trailing, of: containerView, withInset: 5)
            
            containerView.set(.width, to: ProfilePictureView.Info.Size.list.viewSize)
            containerView.set(.height, to: ProfilePictureView.Info.Size.list.viewSize)
            
            selectedAvatarsStackView.addArrangedSubview(containerView)
        }
        
        // 更新scrollView的contentSize
        selectedAvatarsStackView.layoutIfNeeded()
        selectedAvatarsScrollView.layoutIfNeeded()
        
        selectedAvatarsScrollView.contentSize = CGSize(
            width: max(selectedAvatarsStackView.frame.width, selectedAvatarsScrollView.bounds.width),
            height: NewClosedGroupVC.avatarContainerHeight
        )
        
        // 显示/隐藏头像容器
        selectedAvatarsContainer.isHidden = selectedProfileIds.isEmpty
        
        // 更新headerView高度
        updateHeaderViewHeight()
        
        // 强制更新布局
        view.layoutIfNeeded()
    }
    
    private func updateHeaderViewHeight() {
        let hasSelectedContacts = !selectedProfileIds.isEmpty
        
        // 更新搜索框的约束：有选中联系人时在顶部，没有时垂直居中
        if hasSelectedContacts {
            // 有选中联系人：搜索框在顶部，增加顶部间距
            searchBarCenterYConstraint?.isActive = false
            if searchBarTopConstraint == nil {
                searchBarTopConstraint = searchBar.pin(.top, to: .top, of: headerView, withInset: Values.mediumSpacing)
            }
            searchBarTopConstraint?.isActive = true
        } else {
            // 没有选中联系人：搜索框垂直居中
            searchBarTopConstraint?.isActive = false
            // 使用已存在的centerY约束，如果不存在则创建
            if searchBarCenterYConstraint == nil {
                searchBarCenterYConstraint = searchBar.center(.vertical, in: headerView)
            }
            searchBarCenterYConstraint?.isActive = true
        }
        
        // 计算高度：有选中联系人时：顶部间距 + 搜索框高度 + 间距 + 头像容器高度
        // 没有选中联系人时：搜索框高度（垂直居中）
        let newHeight = hasSelectedContacts ? 
            (Values.mediumSpacing + NewClosedGroupVC.searchBarHeight + Values.smallSpacing + NewClosedGroupVC.avatarContainerHeight) :
            NewClosedGroupVC.searchBarHeight
        
        var frame = headerView.frame
        frame.size.height = newHeight
        headerView.frame = frame
        
        tableView.tableHeaderView = headerView
        tableView.tableHeaderView?.layoutIfNeeded()
    }
    
    @objc private func removeSelectedContact(_ sender: UIButton) {
        guard let profileId = sender.accessibilityIdentifier else { return }
        selectedProfileIds.remove(profileId)
        
        // 刷新表格视图
        if let indexPath = data.first?.elements.firstIndex(where: { $0.profileId == profileId }).map({ IndexPath(row: $0, section: 0) }) {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
    
    private func updateCreateButtonState() {
        let count = selectedProfileIds.count
        createButton.isEnabled = count > 0
        if count > 0 {
            createButton.title = "完成(\(count))"
        } else {
            createButton.title = "完成"
        }
    }
    
    @objc private func createClosedGroup() {
        func showError(title: String, message: String = "") {
            let modal: ConfirmationModal = ConfirmationModal(
                info: ConfirmationModal.Info(
                    title: title,
                    body: .text(message),
                    cancelTitle: "okay".localized(),
                    cancelStyle: .alert_text
                    
                )
            )
            present(modal, animated: true)
        }
        // 生成默认群组名称
        let name: String = {
            if let prefilledName = prefilledName, !prefilledName.isEmpty {
                return prefilledName
            }
            // 根据选中的联系人生成默认名称
            let selectedNames = selectedProfileIds.compactMap { id in
                contacts.first(where: { $0.profileId == id })?.profile?.displayName() ?? id.truncated()
            }
            if selectedNames.count <= 3 {
                return selectedNames.joined(separator: "、")
            } else {
                return selectedNames.prefix(3).joined(separator: "、") + "等\(selectedNames.count)人"
            }
        }()
        
        guard !name.isEmpty else {
            return showError(title: "groupNameEnterPlease".localized())
        }
        guard !LibSession.isTooLong(groupName: name) else {
            return showError(title: "groupNameEnterShorter".localized())
        }
        guard selectedProfileIds.count >= 1 else {
            return showError(title: "groupCreateErrorNoMembers".localized())
        }
        /// Minus one because we're going to include self later
        guard selectedProfileIds.count < (LibSession.sizeMaxGroupMemberCount - 1) else {
            return showError(title: "groupAddMemberMaximum".localized())
        }
        let selectedProfiles: [(String, Profile?)] = self.selectedProfileIds.map { id in
            (id, self.contacts.first { $0.profileId == id }?.profile)
        }
        
        let indicator: ModalActivityIndicatorViewController = ModalActivityIndicatorViewController()
        navigationController?.present(indicator, animated: false)
        
        Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            do {
                let thread: SessionThread = try await MessageSender.createGroup(
                    name: name,
                    description: nil,
                    displayPicture: nil,
                    displayPictureCropRect: nil,
                    members: selectedProfiles,
                    using: dependencies
                )
                
                /// When this is triggered via the "Recreate Group" action for Legacy Groups the screen will have been
                /// pushed instead of presented and, as a result, we need to dismiss the `activityIndicatorViewController`
                /// and want the transition to be animated in order to behave nicely
                await MainActor.run { [weak self, dependencies] in
                    dependencies[singleton: .app].presentConversationCreatingIfNeeded(
                        for: thread.id,
                        variant: thread.variant,
                        action: .none,
                        dismissing: (self?.presentingViewController ?? indicator),
                        animated: (self?.presentingViewController == nil)
                    )
                }
            }
            catch {
                await MainActor.run { [weak self] in
                    self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                    
                    let modal: ConfirmationModal = ConfirmationModal(
                        targetView: self?.view,
                        info: ConfirmationModal.Info(
                            title: "groupError".localized(),
                            body: .text("groupErrorCreate".localized()),
                            cancelTitle: "okay".localized(),
                            cancelStyle: .alert_text
                        )
                    )
                    self?.present(modal, animated: true)
                }
            }
        }
    }
}

extension NewClosedGroupVC: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        
        let changeset: StagedChangeset<[ArraySection<Section, WithProfile<Contact>>]> = StagedChangeset(
            source: data,
            target: [
                ArraySection(
                    model: .contacts,
                    elements: (searchText.isEmpty ?
                        contacts :
                        contacts.filter {
                            $0.profile?.displayName().range(of: searchText, options: [.caseInsensitive]) != nil
                        }
                    )
                )
            ]
        )
        
        self.tableView.reload(
            using: changeset,
            deleteSectionsAnimation: .none,
            insertSectionsAnimation: .none,
            reloadSectionsAnimation: .none,
            deleteRowsAnimation: .none,
            insertRowsAnimation: .none,
            reloadRowsAnimation: .none,
            interrupt: { $0.changeCount > 100 }
        ) { [weak self] updatedData in
            self?.data = updatedData
        }
    }
    
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        searchBar.setShowsCancelButton(true, animated: true)
        return true
    }
    
    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        searchBar.setShowsCancelButton(false, animated: true)
        return true
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
