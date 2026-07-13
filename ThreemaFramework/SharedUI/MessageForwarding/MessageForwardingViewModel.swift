import CocoaLumberjackSwift
import CoreData
import Observation
import ThreemaMacros

@MainActor @Observable
public final class MessageForwardingViewModel {

    // MARK: - Internal types

    enum Section: Hashable {
        case main
    }

    // MARK: - Public properties

    let cancelButtonTitle = #localize("cancel")
    let confirmationButtonTitle = #localize("send")
    let screenTitle = #localize("message_forwarding_screen_title")
    let message: BaseMessageEntity

    var isConfirmationButtonEnabled: Bool {
        !selectedItemIdentifiers.isEmpty
    }

    /// The item identifiers of the conversations in their order.
    ///
    /// While a filter is set, this contains the matching contacts, groups and distribution lists instead (see
    /// `applyFilter()`).
    private(set) var itemIdentifiers = [ItemID]()

    /// The selected conversation item identifiers in their order.
    ///
    /// This is an array instead of a set because the header carousel must keep
    /// the selection order stable. A set would reorder the items whenever the
    /// selection changes.
    private(set) var selectedItemIdentifiers = [ItemID]() {
        willSet {
            previouslySelectedItemIdentifiers = Set(selectedItemIdentifiers)
        }
    }

    /// A list of items that needs to be updated (reconfigured) to reflect their new selection state
    ///
    /// Contains:
    /// - Selected before, but are not selected now (they were deselected).
    /// - Not selected before, but are selected now (they were newly selected).
    /// - Everything is a subset of all item identifiers
    @ObservationIgnored
    var changedItemIdentifiers: [ItemID] {
        Array(
            Set(itemIdentifiers).intersection(
                previouslySelectedItemIdentifiers.symmetricDifference(selectedItemIdentifiers)
            )
        )
    }

    /// A flag that indicates if the forward message screen should be dismissed.
    private(set) var shouldDismiss = false

    // MARK: - Private properties

    private let distributionListManager: any DistributionListManagerProtocol
    private let entityFetcher: EntityFetcher
    private let entityManager: EntityManager
    private let forwarder = MessageForwarder()
    private let groupManager: any GroupManagerProtocol
    private let settingsStore: any SettingsStoreProtocol

    /// The previously selected conversation item identifiers before updating with search results new selection.
    @ObservationIgnored
    private(set) var previouslySelectedItemIdentifiers = Set<ItemID>()

    /// All loaded conversation item identifiers, independent of the current filter
    @ObservationIgnored
    private var allItemIdentifiers = [ItemID]()

    /// The current search filter (see `updateFilterText(_:)`)
    @ObservationIgnored
    private var filterText = ""

    var isSearching: Bool {
        !filterText.isEmpty
    }
    
    // MARK: - Lifecycle

    public init(businessInjector: any BusinessInjectorProtocol, message: BaseMessageEntity) {
        self.distributionListManager = businessInjector.distributionListManager
        self.entityFetcher = businessInjector.entityManager.entityFetcher
        self.entityManager = businessInjector.entityManager
        self.groupManager = businessInjector.groupManager
        self.message = message
        self.settingsStore = businessInjector.settingsStore
    }

    // MARK: - Public methods

    func viewWillAppear() {
        loadItems()
    }

    func selectableItem(for itemIdentifier: ItemID) -> SelectableItem? {
        let isSelected = isIdentifierSelected(itemIdentifier)

        if let contactEntity = entityFetcher.contactEntity(with: itemIdentifier) {
            let contact = Contact(contactEntity: contactEntity)
            let item = SelectableItem(id: itemIdentifier, item: .contact(contact), isSelected: isSelected)
            return item
        }
        else {
            guard let conversationEntity = entityFetcher.conversationEntity(with: itemIdentifier) else {
                return nil
            }
            if conversationEntity.isGroup, let group = groupManager.getGroup(conversation: conversationEntity) {
                let item = SelectableItem(id: itemIdentifier, item: .group(group), isSelected: isSelected)
                return item
            }
            else if let list = distributionListManager.distributionList(for: conversationEntity) {
                let item = SelectableItem(id: itemIdentifier, item: .distributionList(list), isSelected: isSelected)
                return item
            }
            else {
                return nil
            }
        }
    }

    func selectableItemForSelectedIdentifier(at index: Int) -> SelectableItem? {
        guard index < selectedItemIdentifiers.count else {
            return nil
        }
        return selectableItem(for: selectedItemIdentifiers[index])
    }

    func selectableItemsForSelectedIdentifiers() -> [SelectableItem] {
        selectedItemIdentifiers.compactMap { selectableItem(for: $0) }
    }

    func selectItem(with itemIdentifier: ItemID) {
        selectedItemIdentifiers.append(itemIdentifier)
    }

    func deselectItem(with itemIdentifier: ItemID) {
        selectedItemIdentifiers.removeAll { $0 == itemIdentifier }
    }

    func isIdentifierSelected(_ itemIdentifier: ItemID) -> Bool {
        selectedItemIdentifiers.contains(itemIdentifier)
    }

    /// Filters the shown items to the contacts, groups and distribution lists matching the passed text. Pass an
    /// empty string to show the conversation list again.
    func updateFilterText(_ text: String) {
        // Treat blank text (empty or whitespace-only) as no filter, so the full list stays visible
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != filterText else {
            return
        }

        filterText = trimmed
        applyFilter()
    }

    func cancelFiltering() {
        filterText = ""
    }
    
    func handleConfirmationButtonTapped(sendAsFile: Bool, additionalContent: MessageForwarder.AdditionalContent?) {
        let conversationEntities = entityManager.performAndWait {
            self.selectedItemIdentifiers.compactMap {
                if let conversationEntity = self.entityFetcher.conversationEntity(with: $0) {
                    return conversationEntity
                }
                else if let contactEntity = self.entityFetcher.contactEntity(with: $0),
                        let conversationEntity = self.entityManager.conversation(
                            forContact: contactEntity,
                            createIfNotExisting: true
                        ) {
                    return conversationEntity
                }
                else {
                    let error = "Every selected item must be either a conversation or a contact"
                    assertionFailure("\(error)")
                    DDLogError("\(error)")
                    return nil
                }
            }
        }

        for conversationEntity in conversationEntities {
            forwarder.forward(
                message,
                to: conversationEntity,
                sendAsFile: sendAsFile,
                additionalContent: additionalContent
            )
        }
        shouldDismiss = true
    }

    // MARK: - Private Methods

    private func loadItems() {
        let excludePrivate = settingsStore.hidePrivateChats
        let ids = entityManager.performAndWait {
            self.entityFetcher.conversationOrContactIDs(excludeArchived: true, excludePrivate: excludePrivate)
        }
        allItemIdentifiers = ids
        applyFilter()
    }

    private func applyFilter() {
        if !isSearching {
            // Keep selected items visible that are not part of the conversation list (e.g. a contact without an
            // existing conversation that was selected while searching)
            let additional = selectedItemIdentifiers.filter { allItemIdentifiers.contains($0) == false }
            itemIdentifiers = allItemIdentifiers + additional
        }
        else {
            // Search all contacts, groups and distribution lists. This intentionally goes beyond filtering the
            // conversation list, so recipients without an existing conversation can be found too.
            itemIdentifiers = searchResultObjectIDs(for: filterText)
        }
    }

    /// Fetches the contacts, groups and distribution lists matching `query` and returns their item identifiers,
    /// grouped by type in that order.
    ///
    /// The three result types live in separate Core Data entities and therefore can't share a single fetch
    /// request, but they are all fetched within one managed object context transaction.
    private func searchResultObjectIDs(for query: String) -> [ItemID] {
        entityManager.performAndWait {
            let contactObjectIDs = self.entityFetcher.matchingContactsForContactListSearch(
                containing: query,
                hideStaleContacts: self.settingsStore.hideStaleContacts
            )

            let groupObjectIDs = self.entityFetcher.filteredGroupConversationEntities(
                by: [query], excludePrivate: self.settingsStore.hidePrivateChats
            ).map(\.objectID)

            let distributionListObjectIDs = self.entityFetcher.filteredDistributionListEntities(
                by: [query], excludePrivate: self.settingsStore.hidePrivateChats
            ).map(\.conversation.objectID)

            return contactObjectIDs + groupObjectIDs + distributionListObjectIDs
        }
    }
}
