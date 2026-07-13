import FileUtility

public protocol DatabaseManagerProtocol {
    static func storeRequiresImport(fileUtility: any FileUtilityProtocol) -> Bool

    static func dbExists(appGroupID: String, fileUtility: any FileUtilityProtocol) -> Bool

    /// Database main context for main thread.

    var persistentStoreCoordinator: NSPersistentStoreCoordinator { get throws }

    func databaseContext() -> any DatabaseContextProtocol

    /// Database child context for main or background thread.
    /// - Parameter withChildContextForBackgroundProcess: Is true get database context for background thread
    func databaseContext(withChildContextForBackgroundProcess: Bool) -> any DatabaseContextProtocol

    /// Check free available storage on the device, if there a database file.
    /// - Parameter showAlert: Called if not enough disk space available
    /// - Throws: DatabaseManagerError.notEnoughDiskSpaceAvailable
    func checkFreeDiskSpaceForDatabaseMigration() throws

    func storeRequiresMigration() -> DatabaseManager.StoreRequiresMigration

    func eraseDB() throws

    func migrateDB() throws

    #if DEBUG
        /// Imports an database from App/Documents folder, this is useful for testing database migration.
        func importOldVersionDatabase() throws -> Bool
    #endif

    /// Imports a repaired database.
    func importRepairedDatabase() throws
}
