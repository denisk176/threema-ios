//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2025 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import CocoaLumberjackSwift
import ThreemaMacros
import UIKit

/// Show detailed information about the provided message
///
/// This automatically updates if some message information changes
final class ChatViewMessageDetailsViewController: ThemedCodeModernGroupedTableViewController {
    
    // MARK: - Private types
    
    private enum Section: Hashable {
        case message
        
        // TODO: IOS-2788
        case error
                
        case editHistory
        
        case fileMetadata
       
        case messageStates
        
        case metadata
        case debugInfo
    }
    
    private enum Row: Hashable {
        case message
        
        case fileSize
                
        case messageDisplayState(_ displayState: BaseMessageEntity.DisplayState)
        
        case deletedMessage
        case editedMessage
        
        // Warning: `EditHistoryItem` should not be stored directly inside the snapshot, but rather outside. As this is
        // only an issue when the details are shown during an edit update we leave it as is. (See `Hashable`
        // implementation of `EditHistoryItem` for details)
        case historyItem(_ item: EditHistoryItem)
        
        case consumed
        
        case perfectForwardSecrecy
        case messageID

        case coreDataDebugInfo
    }
    
    // MARK: - Private properties
    
    private let messageManagedObjectID: NSManagedObjectID
    private lazy var message: BaseMessageEntity? = EntityManager().entityFetcher.existingObject(
        with: messageManagedObjectID
    ) as? BaseMessageEntity
    
    private let messageCellProvider = ChatViewCellProvider()
    private static let contentConfigurationCellIdentifier = "contentConfigurationCellIdentifier"
    
    private lazy var fileSizeFormatter = ByteCountFormatter()
    
    private lazy var dataSource = TableViewDiffableSimpleHeaderAndFooterDataSource<Section, Row>(
        tableView: tableView,
        cellProvider: { [weak self] tableView, indexPath, row in
            guard let strongSelf = self else {
                fatalError("This seems to be deallocated")
            }
            
            guard let message = strongSelf.message else {
                fatalError("No message to show details for")
            }
            
            switch row {
            case .message:
                let cell = strongSelf.messageCellProvider.cell(
                    for: message,
                    with: .noNeighbors,
                    in: tableView,
                    at: indexPath
                )
                
                // Deactivate because we don't assign a delegate for the context menu and things like quote would be
                // hard to implement
                cell.isUserInteractionEnabled = false
                cell.backgroundColor = .secondarySystemGroupedBackground
                
                // A bit hacky: Adjust spacing
                if let chatViewBaseTableViewCell = cell as? ChatViewBaseTableViewCell {
                    chatViewBaseTableViewCell.contentTopSpacingConstraint.constant = ChatViewConfiguration
                        .ChatBubble.defaultGroupTopBottomInset
                    chatViewBaseTableViewCell.contentBottomSpacingConstraint.constant = -ChatViewConfiguration
                        .ChatBubble.defaultGroupTopBottomInset
                }
                
                return cell
                
            case let .messageDisplayState(displayState):
                return strongSelf.configuredCell(
                    in: tableView,
                    at: indexPath,
                    text: displayState.localizedLabel(for: message),
                    secondaryText: DateFormatter.shortStyleDateTime(message.date(for: displayState)),
                    image: displayState.symbol(with: .label, variant: .default)
                )

            case .deletedMessage:
                return strongSelf.configuredCell(
                    in: tableView,
                    at: indexPath,
                    text: #localize("message_display_status_deleted_message"),
                    secondaryText: DateFormatter.shortStyleDateTime(message.deletedAt),
                    image: UIImage(systemName: "trash")?.withTintColor(.label, renderingMode: .alwaysOriginal)
                )

            case .editedMessage:
                return strongSelf.configuredCell(
                    in: tableView,
                    at: indexPath,
                    text: #localize("message_display_status_edited_message"),
                    secondaryText: DateFormatter.shortStyleDateTime(message.lastEditedAt),
                    image: UIImage(resource: .threemaPencilBubbleLeft)
                        .withTintColor(.label, renderingMode: .alwaysOriginal)
                )

            case .consumed:
                var secondaryText: String?
                var image: UIImage?
                if let voiceMessage = message as? VoiceMessage,
                   let consumedDate = voiceMessage.consumed {
                    secondaryText = DateFormatter.shortStyleDateTime(consumedDate)
                    
                    image = UIImage(systemName: "mic")
                }
                
                return strongSelf.configuredCell(
                    in: tableView,
                    at: indexPath,
                    text: #localize("detailView_consumed"),
                    secondaryText: secondaryText,
                    image: image
                )
                
            case .fileSize:
                var secondaryText: String?
                var image: UIImage?
                if let fileMessage = message as? FileMessage {
                    secondaryText = strongSelf.fileSizeFormatter.string(from: fileMessage.dataBlobFileSize)
                    
                    image = UIImage(systemName: fileMessage.fileMessageType.symbolName)
                    if image == nil {
                        // Try non system symbol if it didn't match a system symbol
                        image = UIImage(named: fileMessage.fileMessageType.symbolName)
                    }
                }
                
                return strongSelf.configuredCell(
                    in: tableView,
                    at: indexPath,
                    text: #localize("detailView_group_file_size"),
                    secondaryText: secondaryText,
                    image: image
                )
                
            case let .historyItem(historyItem):
                let cell: ChatViewMessageDetailsMessageHistoryTableViewCell = tableView.dequeueCell(for: indexPath)
                cell.historyItem = historyItem
                return cell
                
            case .perfectForwardSecrecy:
                return strongSelf.configuredCell(
                    in: tableView,
                    at: indexPath,
                    text: #localize("forward_security"),
                    secondaryText: ForwardSecurityMode(rawValue: message.forwardSecurityMode.uintValue)?.localizedLabel
                )
                
            case .messageID:
                let cell = strongSelf.configuredCell(
                    in: tableView,
                    at: indexPath,
                    text: #localize("detailView_messageID"),
                    secondaryText: strongSelf.message?.id.hexString
                )
                // A message ID can be selected for copying and showing debug info
                cell.selectionStyle = .default
                return cell
                
            case .coreDataDebugInfo:
                let cell: DebugInfoTableViewCell = tableView.dequeueCell(for: indexPath)
                cell.debugText = message.debugDescription
                return cell
            }
        },
        headerProvider: { [weak self] _, section in
            guard let self else {
                return nil
            }
            
            return switch section {
            case .editHistory:
                if let entries = message?.historyEntries, !entries.isEmpty {
                    #localize("detailView_edit_history_header")
                }
                else {
                    nil
                }
            default:
                nil
            }
        },
        footerProvider: { [weak self] _, section in
            // Show creation date in footer after the last regular section before the debugging section
            guard section == .metadata, let message = self?.message else {
                return nil
            }
            
            return String.localizedStringWithFormat(
                #localize("detailView_created_footer"),
                DateFormatter.shortStyleDateTime(message.date)
            )
        }
    )
    
    // Keep tack of debug info taps and configure threshold after how many taps to show debug info
    private var showDebugInfoTapCounter = 0
    private let showDebugInfoThreshold = 5
    
    private var observers = [NSKeyValueObservation]()
    
    // MARK: - Lifecycle
    
    init(messageManagedObjectID: NSManagedObjectID) {
        self.messageManagedObjectID = messageManagedObjectID
        super.init()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationBarTitle = #localize("detailView_title")
        
        configureTableView()
        configureDataSource()
        addObservers()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeObservers()
    }
    
    // MARK: - Configuration
    
    private func configureTableView() {
        
        ChatViewCellProvider.registerCells(in: tableView)
        tableView.register(
            UITableViewCell.self,
            forCellReuseIdentifier: ChatViewMessageDetailsViewController.contentConfigurationCellIdentifier
        )
        tableView.registerCell(ChatViewMessageDetailsMessageHistoryTableViewCell.self)
        tableView.registerCell(DebugInfoTableViewCell.self)
                
        tableView.delegate = self
    }
    
    private func configureDataSource() {
        dataSource.defaultRowAnimation = .middle
        
        dataSource.apply(newSnapshot())
    }
    
    // MARK: - Observers
    
    private func addObservers() {
        observeMessage(\.remoteSentDate) { [weak self] in
            self?.updateSnapshot(reconfigure: [.messageDisplayState(.sent)])
        }
        
        observeMessage(\.deliveryDate) { [weak self] in
            self?.updateSnapshot(reconfigure: [.messageDisplayState(.delivered)])
        }
        
        observeMessage(\.readDate) { [weak self] in
            self?.updateSnapshot(reconfigure: [.messageDisplayState(.read)])
        }
    
        observeMessage(\.deletedAt) { [weak self] in
            guard let self else {
                return
            }
            // Do not reconfigure, because the message cell will change
            dataSource.applySnapshotUsingReloadData(newSnapshot())
        }
        observeMessage(\.lastEditedAt) { [weak self] in
            // `lastEditedAt` getting triggered if the message will be remotely deleted
            guard let msg = self?.message,
                  msg.deletedAt == nil else {
                return
            }
            self?.updateSnapshot(reconfigure: [])
        }
        
        observeMessage(\.groupDeliveryReceipts) { [weak self] in
            self?.updateSnapshot(reconfigure: [])
        }
    }
    
    private func removeObservers() {
        // Invalidate all observers
        for observer in observers {
            observer.invalidate()
        }
        
        // Remove them so we don't reference old observers
        observers.removeAll()
    }
    
    /// Helper to add observers to the `message` property
    ///
    /// All observers are store in the `observers` property.
    ///
    /// - Parameters:
    ///   - keyPath: Key path in `BaseMessageEntity` to observe
    ///   - changeHandler: Handler called on each observed change.
    ///                     Don't forget to capture `self` weakly! Dispatched on the main queue.
    private func observeMessage(_ keyPath: KeyPath<BaseMessageEntity, some Any>, changeHandler: @escaping () -> Void) {
        guard let message else {
            return
        }
        
        let observer = message.observe(keyPath) { [weak self] _, _ in
            guard let strongSelf = self else {
                return
            }
            
            // Check if the observed message is in the process to be deleted
            guard !(strongSelf.message?.willBeDeleted ?? true) else {
                // Invalidate and remove all observers
                strongSelf.removeObservers()
                
                // Hide myself
                if strongSelf.isPresentedInModalAndRootView {
                    strongSelf.dismiss(animated: true)
                }
                else {
                    strongSelf.navigationController?.popViewController(animated: true)
                }
                
                return
            }
            
            // Because `changeHandler` update the snapshot we need to ensure that it runs on the same/main queue
            Task { @MainActor in
                changeHandler()
            }
        }
        
        observers.append(observer)
    }
    
    // MARK: - Helper
    
    private func configuredCell(
        in tableView: UITableView,
        at indexPath: IndexPath,
        text: String,
        secondaryText: String?,
        image: UIImage? = nil
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ChatViewMessageDetailsViewController.contentConfigurationCellIdentifier,
            for: indexPath
        )
        
        cell.selectionStyle = .none
        
        cell.contentConfiguration = listContentConfiguration(text: text, secondaryText: secondaryText, image: image)
        
        return cell
    }
    
    private func listContentConfiguration(
        text: String,
        secondaryText: String?,
        image: UIImage? = nil
    ) -> UIListContentConfiguration {
        var content = UIListContentConfiguration.valueCell()
        
        content.text = text
        
        if let secondaryText, !secondaryText.isEmpty {
            content.secondaryText = secondaryText
        }
        else {
            content.secondaryText = "-"
        }
        
        content.image = image
        
        content.secondaryTextProperties.color = .secondaryLabel
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .medium)
        content.imageProperties.tintColor = .label
        
        return content
    }
    
    // MARK: - Update
    
    private func updateSnapshot(reconfigure rows: Set<Row>) {
        var nextSnapshot = newSnapshot()
        
        var potentialRowsToReconfigure: Set<Row> = rows
        
        // On any change we want to keep message and debug info up to date
        potentialRowsToReconfigure.insert(.message)
        potentialRowsToReconfigure.insert(.coreDataDebugInfo)
        
        // We are only allowed to reconfigure items that are in the snapshot (otherwise is crashes)
        let itemsToReconfigure = Array(
            Set(nextSnapshot.itemIdentifiers).intersection(potentialRowsToReconfigure)
        )
        nextSnapshot.reconfigureItems(itemsToReconfigure)
        
        dataSource.apply(nextSnapshot)
    }
    
    // MARK: - Snapshot
    
    private func newSnapshot() -> NSDiffableDataSourceSnapshot<Section, Row> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        
        guard let message else {
            return snapshot
        }
        
        snapshot.appendSections([.message])
        snapshot.appendItems([.message])
        
        // TODO: (IOS-2788) Nothing interesting to show for now, so we don't show it
//        let messageDisplayState = message.messageDisplayState
//        if messageDisplayState == .failed {
//            snapshot.appendSections([.errors])
//            snapshot.appendItems([.messageDisplayState(.failed)])
//        }
        
        /// Note: Ideally we would use an approach where we can reconfigure the cells for the history, by storing the
        /// information not inside the snapshot. (See `Hashable` implementation of `EditHistoryItem` for details.)
        let historyRows = historyRows(for: message)
        if !historyRows.isEmpty {
            snapshot.appendSections([.editHistory])
            snapshot.appendItems(historyRows, toSection: .editHistory)
        }
        
        if message.deletedAt == nil, message is FileMessage {
            snapshot.appendSections([.fileMetadata])
            snapshot.appendItems([.fileSize])
        }
        
        snapshot.appendSections([.messageStates])
        // Show nothing for SystemMessages
        if message is SystemMessageEntity {
            // Empty
        }
        // Don't show delivered and read state for outgoing group messages as this is not set
        else if message.isGroupMessage && message.isOwnMessage {
            snapshot.appendItems([
                .messageDisplayState(.sent),
            ])

            if message.deletedAt != nil {
                snapshot.appendItems([.deletedMessage])
            }

            if message.lastEditedAt != nil {
                snapshot.appendItems([.editedMessage])
            }
        }
        else {
            snapshot.appendItems([
                .messageDisplayState(.sent),
                .messageDisplayState(.delivered),
                .messageDisplayState(.read),
            ])

            if message.deletedAt != nil {
                snapshot.appendItems([.deletedMessage])
            }

            if message.lastEditedAt != nil {
                snapshot.appendItems([.editedMessage])
            }
        }
        
        // Show consumed only for received voice messages where the consumed date is not 1970 (default date for all
        // existing voice messages before this feature)
        if let voiceMessage = message as? VoiceMessage,
           !voiceMessage.isOwnMessage,
           let consumedDate = voiceMessage.consumed,
           consumedDate != Date(timeIntervalSince1970: 0) {
            snapshot.appendItems([.consumed])
        }
        
        snapshot.appendSections([.metadata])
        // Show PFS mode for all messages except non-call system messages
        if let systemMessage = message as? SystemMessageEntity {
            switch systemMessage.systemMessageType {
            case .callMessage:
                snapshot.appendItems([.perfectForwardSecrecy])
            case .systemMessage, .workConsumerInfo:
                break
            }
        }
        else {
            snapshot.appendItems([.perfectForwardSecrecy])
        }
        snapshot.appendItems([.messageID])
        
        if showDebugInfoTapCounter >= showDebugInfoThreshold || ThreemaEnvironment.env() == .xcode {
            snapshot.appendSections([.debugInfo])
            snapshot.appendItems([.coreDataDebugInfo])
        }
        
        return snapshot
    }
    
    private func historyRows(for message: BaseMessageEntity) -> [Row] {
        // Only add any rows if there are any history messages
        guard let historyEntries = message.historyEntries, !historyEntries.isEmpty else {
            return []
        }
        
        var rows = [Row]()
        
        // Add content of message first
        switch message {
        case let textMessage as TextMessageEntity:
            let item = EditHistoryItem(textMessage: textMessage)
            rows.append(.historyItem(item))
            
        case let fileMessage as FileMessage:
            let item = EditHistoryItem(fileMessage: fileMessage)
            rows.append(.historyItem(item))
            
        default:
            assertionFailure("The message \(message.loggingDescription) doesn't support editing")
        }
        
        // Add all entries
        let entryItemRows = historyEntries
            .sorted { $0.editDate > $1.editDate }
            .map {
                Row.historyItem(
                    EditHistoryItem(messageHistoryEntry: $0)
                )
            }
        
        rows.append(contentsOf: entryItemRows)
        
        return rows
    }
}

// MARK: - UITableViewDelegate

extension ChatViewMessageDetailsViewController: UITableViewDelegate {
    
    // MARK: - Selection, copy & debug info
    
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        // Only allow selection of message id cell
        guard let row = dataSource.itemIdentifier(for: indexPath), row == .messageID else {
            return nil
        }
        
        return indexPath
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Only message id cell has any actions
        if let row = dataSource.itemIdentifier(for: indexPath), row == .messageID {
            if showDebugInfoTapCounter == 0 || showDebugInfoTapCounter > showDebugInfoThreshold {
                copySecondaryText(in: tableView, fromCellAt: indexPath)
            }
            
            showDebugInfoTapCounter += 1
            
            if showDebugInfoTapCounter >= showDebugInfoThreshold {
                updateSnapshot(reconfigure: [])
            }
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    private func copySecondaryText(in tableView: UITableView, fromCellAt indexPath: IndexPath) {
        if let cell = tableView.cellForRow(at: indexPath),
           let listContentConfiguration = cell.contentConfiguration as? UIListContentConfiguration {
            UIPasteboard.general.string = listContentConfiguration.secondaryText
            NotificationPresenterWrapper.shared.present(type: .copySuccess)
            return
        }
        
        DDLogWarn("Could not copy secondary text at \(indexPath)")
        // Do nothing
    }
}
