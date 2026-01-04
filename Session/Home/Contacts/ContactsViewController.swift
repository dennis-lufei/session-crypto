// Copyright © 2024 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine
import GRDB
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

/// Contacts View Controller - Shows list of all contacts
public final class ContactsViewController: BaseVC {
    private let dependencies: Dependencies
    private let viewModel: ContactsViewModel
    private var disposables: Set<AnyCancellable> = Set()
    
    // MARK: - UI
    
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.register(view: MessageRequestsCell.self)
        result.register(view: FullConversationCell.self)
        result.dataSource = self
        result.delegate = self
        result.sectionHeaderTopPadding = 0
        
        return result
    }()
    
    private lazy var emptyStateView: UIView = {
        let emptyLabel = UILabel()
        emptyLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        emptyLabel.text = "contactNone".localized()
        emptyLabel.themeTextColor = .textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        
        let result = UIView()
        result.addSubview(emptyLabel)
        emptyLabel.center(in: result)
        emptyLabel.pin(.leading, to: .leading, of: result, withInset: Values.largeSpacing)
        emptyLabel.pin(.trailing, to: .trailing, of: result, withInset: -Values.largeSpacing)
        
        return result
    }()
    
    // MARK: - Initialization
    
    public init(using dependencies: Dependencies) {
        self.dependencies = dependencies
        self.viewModel = ContactsViewModel(using: dependencies)
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(using:) instead.")
    }
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        setNavBarTitle(NSLocalizedString("通讯录", comment: "Contacts"))
        
        // Table view
        view.addSubview(tableView)
        tableView.pin(to: view)
        
        // Empty state view
        view.addSubview(emptyStateView)
        emptyStateView.pin(to: view)
        emptyStateView.isHidden = true
        
        bindViewModel()
    }
    
    // MARK: - Binding
    
    private func bindViewModel() {
        viewModel.$sections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.tableView.reloadData()
                self?.updateEmptyState()
            }
            .store(in: &disposables)
    }
    
    private func updateEmptyState() {
        // Check if we have any contact sections (excluding message requests section)
        let hasContacts = viewModel.sections.contains { section in
            section.messageRequestCount == nil && !section.elements.isEmpty
        }
        emptyStateView.isHidden = hasContacts
    }
}

// MARK: - UITableViewDataSource

extension ContactsViewController: UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.sections.count
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < viewModel.sections.count else { return 0 }
        let sectionModel = viewModel.sections[section]
        // Message requests section has 1 row, contact sections have their elements count
        if sectionModel.messageRequestCount != nil {
            return 1
        }
        return sectionModel.elements.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = viewModel.sections[indexPath.section]
        
        // Check if this is a message requests section
        if let messageRequestCount = section.messageRequestCount {
            let cell: MessageRequestsCell = tableView.dequeue(type: MessageRequestsCell.self, for: indexPath)
            cell.accessibilityIdentifier = "Message requests banner"
            cell.isAccessibilityElement = true
            cell.update(with: messageRequestCount)
            return cell
        }
        
        let threadViewModel = section.elements[indexPath.row]
        let cell: FullConversationCell = tableView.dequeue(type: FullConversationCell.self, for: indexPath)
        cell.update(with: threadViewModel, using: dependencies)
        cell.accessibilityIdentifier = "Contact list item"
        cell.accessibilityLabel = threadViewModel.displayName
        
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ContactsViewController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let section = viewModel.sections[indexPath.section]
        
        // Handle message requests section
        if section.messageRequestCount != nil {
            let viewController: SessionTableViewController = SessionTableViewController(
                viewModel: MessageRequestsViewModel(using: dependencies)
            )
            navigationController?.pushViewController(viewController, animated: true)
            return
        }
        
        let threadViewModel = section.elements[indexPath.row]
        let viewController = ConversationVC(
            threadId: threadViewModel.threadId,
            threadVariant: threadViewModel.threadVariant,
            focusedInteractionInfo: nil,
            using: dependencies
        )
        navigationController?.pushViewController(viewController, animated: true)
    }
}

// MARK: - ContactsViewModel

private final class ContactsViewModel: ObservableObject {
    @Published private(set) var sections: [ContactsSectionModel] = []
    let dependencies: Dependencies
    private var contactsCancellable: DatabaseCancellable?
    private var messageRequestCancellable: DatabaseCancellable?
    private var messageRequestCount: Int = 0
    private var hasHiddenMessageRequests: Bool = false
    
    init(using dependencies: Dependencies) {
        self.dependencies = dependencies
        setupObservation()
    }
    
    private func setupObservation() {
        // Observe contacts
        let contactsObservation = ValueObservation.trackingConstantRegion { [dependencies] db -> [SessionThreadViewModel] in
            let userSessionId = dependencies[cache: .general].sessionId
            let contact: TypedTableAlias<Contact> = TypedTableAlias()
            
            // Query approved contacts only
            let contactIds = try Contact
                .filter(contact[.isApproved] == true)
                .filter(contact[.didApproveMe] == true)
                .filter(contact[.isBlocked] == false)
                .filter(contact[.id] != userSessionId.hexString)
                .select(.id)
                .asRequest(of: String.self)
                .fetchAll(db)
            
            guard !contactIds.isEmpty else { return [] }
            
            // Get thread view models for these contacts
            return try SessionThreadViewModel
                .query(
                    userSessionId: userSessionId,
                    groupSQL: SessionThreadViewModel.groupSQL,
                    orderSQL: SessionThreadViewModel.homeOrderSQL,
                    ids: contactIds
                )
                .fetchAll(db)
        }
        
        contactsCancellable = dependencies[singleton: .storage].start(
            contactsObservation,
            scheduling: .async(onQueue: .main),
            onError: { error in
                Log.error("[ContactsViewModel] Contacts observation failed: \(error)")
            },
            onChange: { [weak self] viewModels in
                self?.updateSections(contactViewModels: viewModels)
            }
        )
        
        // Observe message request count
        let messageRequestObservation = ValueObservation.trackingConstantRegion { [dependencies] db -> (Int, Bool) in
            let hasHidden = dependencies.mutate(cache: .libSession) { libSession in
                libSession.get(.hasHiddenMessageRequests)
            }
            
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
            
            return (count, hasHidden)
        }
        
        messageRequestCancellable = dependencies[singleton: .storage].start(
            messageRequestObservation,
            scheduling: .async(onQueue: .main),
            onError: { error in
                Log.error("[ContactsViewModel] Message request observation failed: \(error)")
            },
            onChange: { [weak self] result in
                self?.messageRequestCount = result.0
                self?.hasHiddenMessageRequests = result.1
                self?.updateSections(contactViewModels: nil)
            }
        )
    }
    
    private var lastContactViewModels: [SessionThreadViewModel] = []
    
    private func updateSections(contactViewModels: [SessionThreadViewModel]?) {
        let viewModels = contactViewModels ?? lastContactViewModels
        if contactViewModels != nil {
            lastContactViewModels = viewModels
        }
        
        // Group contacts by first letter
        let grouped = Dictionary(grouping: viewModels) { viewModel -> String in
            let displayName = viewModel.displayName
            let firstChar = String(displayName.prefix(1)).uppercased()
            // Check if it's a letter, otherwise group under "#"
            return firstChar.rangeOfCharacter(from: .letters) != nil ? firstChar : "#"
        }
        
        var contactSections = grouped
            .sorted { pair1, pair2 -> Bool in
                let key1 = pair1.key
                let key2 = pair2.key
                // Sort "#" to the end
                if key1 == "#" { return false }
                if key2 == "#" { return true }
                return key1 < key2
            }
            .map { key, values in
                ContactsSectionModel(
                    title: key,
                    elements: values.sorted { $0.displayName < $1.displayName },
                    messageRequestCount: nil
                )
            }
        
        // Add message requests section at the beginning if needed
        if !hasHiddenMessageRequests && messageRequestCount > 0 {
            let messageRequestSection = ContactsSectionModel(
                title: "",
                elements: [],
                messageRequestCount: messageRequestCount
            )
            contactSections.insert(messageRequestSection, at: 0)
        }
        
        self.sections = contactSections
    }
}

// MARK: - ContactsSectionModel

private struct ContactsSectionModel {
    let title: String
    let elements: [SessionThreadViewModel]
    let messageRequestCount: Int? // nil表示不显示消息请求，非nil表示要显示消息请求cell
}


