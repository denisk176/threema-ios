import CocoaLumberjackSwift
import Foundation

public final class GatewayProfilePictureManager {

    // MARK: - Private types

    private enum GatewayAvatarError: Error, LocalizedError {
        case missingAvatarServerInfo(identity: String)

        var errorDescription: String {
            switch self {
            case let .missingAvatarServerInfo(identity):
                "Error: Missing avatar server info for identity: \(identity)."
            }
        }
    }

    // MARK: - Private properties

    private let avatarCheckInterval: TimeInterval = 24 * 60 * 60
    private let avatarExpiresDictionaryKey = "GatewayAvatarExpiresDictionary"
    private let avatarRefreshTimestampKey = "GatewayAvatarLastRefreshDate"

    private let maxConcurrentRequests = 5

    private let authenticationTokenManager = AuthTokenManager.shared()
    private let entityManager: EntityManager

    private let contactStore: any ContactStoreProtocol
    private let dateProvider: () -> Date
    private let serverInfoProvider: any ServerInfoProvider
    private let userDefaults: any UserDefaultsService

    // MARK: - Lifecycle

    public init(
        contactStore: any ContactStoreProtocol = ContactStore.shared(),
        dateProvider: @escaping () -> Date = Date.init,
        entityManager: EntityManager = BusinessInjector.ui.entityManager,
        serverInfoProvider: any ServerInfoProvider = ServerInfoProviderFactory.makeServerInfoProvider(),
        userDefaults: any UserDefaultsService = AppGroup.userDefaults()
    ) {
        self.contactStore = contactStore
        self.dateProvider = dateProvider
        self.entityManager = entityManager
        self.serverInfoProvider = serverInfoProvider
        self.userDefaults = userDefaults
    }

    // MARK: - Public methods

    public func refresh() {
        if let lastRefreshDate = self.lastRefreshDate(),
           dateProvider().timeIntervalSince(lastRefreshDate) < avatarCheckInterval {
            return // too soon, skip
        }

        Task.detached(priority: .utility) {
            await self.loadCache(forceRefresh: false)
        }
    }

    public func refreshForced() {
        deleteExpires()
        Task.detached(priority: .utility) {
            await self.loadCache(forceRefresh: true)
        }
    }

    public func loadAndSaveAvatar(for identity: String) {
        Task.detached(priority: .utility) {
            await self.updateIdentity(identity, forceRefresh: true)
        }
    }

    // MARK: - Private methods

    private func loadCache(forceRefresh: Bool) async {
        let identities: [String] = entityManager.performAndWait {
            guard let contacts = self.entityManager.entityFetcher.gatewayContactEntities(), !contacts.isEmpty else {
                return []
            }
            return contacts.map(\.identity)
        }

        guard !identities.isEmpty else {
            return
        }

        await withTaskGroup(of: Void.self) { group in
            var inFlight = 0

            for identity in identities {
                if inFlight >= maxConcurrentRequests {
                    await group.next()
                    inFlight -= 1
                }

                group.addTask {
                    await self.updateIdentity(identity, forceRefresh: forceRefresh)
                }

                inFlight += 1
            }

            await group.waitForAll()
        }

        updateLastRefreshDate()
    }

    private func updateIdentity(_ identity: String, forceRefresh: Bool) async {
        do {
            guard forceRefresh || isExpired(for: identity) else {
                return
            }

            let (statusCode, data, expires) = try await loadAvatarData(for: identity)

            if statusCode == 404 {
                updateProfileImage(nil, for: identity)
                let expires = Date(timeIntervalSinceNow: avatarCheckInterval)
                updateExpiry(expires, for: identity)
                return
            }

            updateProfileImage(data, for: identity)

            if let expires, let expiresDate = DateFormatter.dateFromRFC1123(expires) {
                updateExpiry(expiresDate, for: identity)
            }
        }
        catch {
            DDLogError("GatewayAvatarMaker: Failed to load avatar for \(identity): \(error)")
        }
    }

    private func loadAvatarData(for identity: String) async throws -> (Int, Data, String?) {
        let url = try await avatarURL(for: identity)

        let authToken = try await obtainAuthToken() // Can be nil for non-OnPrem builds

        let authorization = authToken.map { "Token \($0)" }
        let httpClient = HTTPClient(authorization: authorization)

        let (data, response) = try await httpClient.downloadData(url: url, contentType: .octetStream)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        let expires = httpResponse?.value(forHTTPHeaderField: "Expires")

        return (statusCode, data, expires)
    }

    private func avatarURL(for identity: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            serverInfoProvider.avatarServer(ipv6: false) { avatarServerInfo, error in
                if let error {
                    continuation.resume(throwing: error)
                }
                else if let avatarServerInfo, let baseURL = URL(string: avatarServerInfo.url) {
                    continuation.resume(returning: baseURL.appendingPathComponent(identity))
                }
                else {
                    let error = GatewayAvatarError.missingAvatarServerInfo(identity: identity)
                    DDLogError("\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func obtainAuthToken() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            authenticationTokenManager.obtainToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                }
                else {
                    continuation.resume(returning: token)
                }
            }
        }
    }

    private func updateProfileImage(_ image: Data?, for identity: String) {
        var hasChanged = false

        entityManager.performAndWait {
            guard let contact = self.entityManager.entityFetcher.contactEntity(for: identity) else {
                return
            }

            let needsUpdate = (image != nil && contact.imageData != image) ||
                (image == nil && contact.imageData != nil)

            if needsUpdate {
                self.entityManager.performAndWaitSave {
                    contact.imageData = image
                }
                hasChanged = true
            }
        }

        if hasChanged {
            contactStore.reflect(identity)
        }
    }

    private func expiresDictionary() -> [String: Date] {
        userDefaults.dictionary(forKey: avatarExpiresDictionaryKey) as? [String: Date] ?? [:]
    }

    private func isExpired(for identity: String) -> Bool {
        guard let expires = expiresDictionary()[identity] else {
            return true
        }
        return dateProvider() >= expires
    }

    private func updateExpiry(_ date: Date, for identity: String) {
        var dictionary = expiresDictionary()
        dictionary[identity] = date
        userDefaults.set(dictionary, forKey: avatarExpiresDictionaryKey)
    }

    private func deleteExpires() {
        userDefaults.removeObject(forKey: avatarExpiresDictionaryKey)
    }

    private func updateLastRefreshDate() {
        userDefaults.set(dateProvider(), forKey: avatarRefreshTimestampKey)
    }

    private func lastRefreshDate() -> Date? {
        userDefaults.object(forKey: avatarRefreshTimestampKey) as? Date
    }
}
