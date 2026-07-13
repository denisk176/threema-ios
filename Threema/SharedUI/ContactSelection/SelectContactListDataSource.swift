import CocoaLumberjackSwift
import Combine
import Foundation
import ThreemaFramework
import ThreemaMacros
import UIKit

final class SelectContactListDataSource: UITableViewDiffableDataSource<
    String,
    NSManagedObjectID
> {
    
    public var contentUnavailableConfiguration: ThreemaTableContentUnavailableView.Configuration {
        didSet {
            contentUnavailable = tableView?
                .setupContentUnavailableView(configuration: contentUnavailableConfiguration)
            snapshot().itemIdentifiers.isEmpty && !isSearching
                ? contentUnavailable?.show()
                : contentUnavailable?.hide()
        }
    }

    var onSnapshotApplied: (() -> Void)?

    var filterText = "" {
        didSet {
            // Treat blank text (empty or whitespace-only) as no filter, so the full list stays visible
            filterText = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard filterText != oldValue else {
                return
            }
            applyProviderSnapshot()
        }
    }
    
    var isSearching: Bool {
        !filterText.isEmpty
    }

    private weak var coordinator: ContactListCoordinator?
    private weak var tableView: UITableView?
    private let entityManager: EntityManager
    private var snapshotSubscription: Cancellable?
    private var providerSnapshot = ContactListProvider.ContactListSnapshot()
    private var sectionTitles: [String] { ThreemaLocalizedIndexedCollation.sectionIndexTitles }
    
    private var tableIndexTitles: [String] {
        (snapshot().sectionIdentifiers + [.broadcasts]).compactMap { str in
            guard let i = Int(str), i >= 0, i < sectionTitles.count else {
                return str
            }
            return sectionTitles[i]
        }
    }
    
    private let sectionIndexEnabled: Bool
    private var contentUnavailable: (show: () -> Void, hide: () -> Void)?
    
    // MARK: - Lifecycle
    
    init(
        coordinator: ContactListCoordinator?,
        provider: ContactListProvider,
        cellProvider: ContactListSelectionCellProvider,
        entityManager: EntityManager,
        in tableView: UITableView,
        sectionIndexEnabled: Bool = true,
        contentUnavailableConfiguration: ThreemaTableContentUnavailableView.Configuration
    ) {
        self.coordinator = coordinator
        self.tableView = tableView
        self.entityManager = entityManager
        self.sectionIndexEnabled = sectionIndexEnabled
        self.contentUnavailableConfiguration = contentUnavailableConfiguration
        
        super.init(tableView: tableView) { tableView, indexPath, objectID in
            let contactEntity = entityManager.performAndWait {
                entityManager.entityFetcher.existingObject(with: objectID) as? ContactEntity
            }
            guard let contactEntity else {
                // TODO: (IOS-4536) Error
                fatalError()
            }
            
            return cellProvider.dequeueCell(for: indexPath, and: Contact(contactEntity: contactEntity), in: tableView)
        }
        
        defaultRowAnimation = .fade
        
        cellProvider.registerCells(in: tableView)
        
        subscribe(to: provider)
    }
    
    deinit {
        snapshotSubscription?.cancel()
    }
    
    // MARK: - Overrides
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sectionIndexEnabled ? tableIndexTitles[section] : nil
    }

    override func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        sectionIndexEnabled && isSearching ? sectionTitles : nil
    }
    
    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        tableIndexTitles.firstIndex(of: title) ?? 0
    }
    
    private func subscribe(to provider: ContactListProvider) {
        snapshotSubscription = provider.currentSnapshot.sink { [weak self] snapshot in
            guard let self else {
                return
            }
            providerSnapshot = snapshot
            applyProviderSnapshot()
        }
    }

    // MARK: - Private functions

    private func applyProviderSnapshot() {
        let snapshot = filteredSnapshot(from: providerSnapshot)
        apply(snapshot)
        didUpdate(snapshot: snapshot)
        onSnapshotApplied?()
    }

    private func filteredSnapshot(
        from snapshot: ContactListProvider.ContactListSnapshot
    ) -> ContactListProvider.ContactListSnapshot {
        guard isSearching else {
            return snapshot
        }

        let matchingIDs = Set(
            entityManager.entityFetcher.matchingContactsForContactListSearch(
                containing: filterText,
                hideStaleContacts: UserSettings.shared().hideStaleContacts
            )
        )

        var filtered = ContactListProvider.ContactListSnapshot()
        for section in snapshot.sectionIdentifiers {
            let items = snapshot.itemIdentifiers(inSection: section).filter { matchingIDs.contains($0) }
            if !items.isEmpty {
                filtered.appendSections([section])
                filtered.appendItems(items, toSection: section)
            }
        }
        return filtered
    }

    private func didUpdate(snapshot: ContactListProvider.ContactListSnapshot) {
        guard snapshot.numberOfItems > 0 || isSearching else {
            contentUnavailable?.show()
            return
        }
        
        contentUnavailable?.hide()
    }
}
