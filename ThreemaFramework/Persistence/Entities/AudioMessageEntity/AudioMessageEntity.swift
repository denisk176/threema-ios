import CoreData
import Foundation
import ThreemaMacros

@objc(AudioMessageEntity)
public final class AudioMessageEntity: BaseMessageEntity {

    static let entityName = "AudioMessage"

    enum Field: String {
        case audio
        case audioBlobID
        case dataAvailable

        static func name(for field: Field, encrypted: Bool) -> String {
            switch field {
            case .audio:
                field.rawValue
            case .audioBlobID:
                encrypted ? encryptedAudioBlobIDName : audioBlobIDName
            case .dataAvailable:
                encrypted ? encryptedDataAvailableName : dataAvailableName
            }
        }
    }

    // MARK: Attributes

    @EncryptedField(name: "audioBlobId")
    // swiftformat:disable:next acronyms
    @objc(audioBlobId) public dynamic var audioBlobID: Data? {
        get {
            getAudioBlobID()
        }

        set {
            setAudioBlobID(newValue)
        }
    }

    @EncryptedField
    @objc public dynamic var audioSize: NSNumber? {
        get {
            getAudioSize()
        }

        set {
            setAudioSize(newValue)
        }
    }

    @EncryptedField
    @objc public dynamic var duration: NSNumber {
        get {
            getDuration()
        }

        set {
            setDuration(newValue)
        }
    }

    @EncryptedField
    @objc public dynamic var encryptionKey: Data? {
        get {
            getEncryptionKey()
        }

        set {
            setEncryptionKey(newValue)
        }
    }
    
    @EncryptedField
    @objc public internal(set) dynamic var dataAvailable: NSNumber {
        get {
            getDataAvailable()
        }

        set {
            setDataAvailable(newValue)
        }
    }

    @NSManaged public var progress: NSNumber?

    // MARK: Relationships

    @objc public dynamic var audio: AudioDataEntity? {
        get {
            willAccessValue(forKey: #keyPath(AudioMessageEntity.audio))
            let value = primitiveValue(forKey: #keyPath(AudioMessageEntity.audio)) as? AudioDataEntity
            didAccessValue(forKey: #keyPath(AudioMessageEntity.audio))
            return value
        }
        set {
            willChangeValue(forKey: #keyPath(AudioMessageEntity.audio))
            setPrimitiveValue(newValue, forKey: #keyPath(AudioMessageEntity.audio))
            didChangeValue(forKey: #keyPath(AudioMessageEntity.audio))
            dataAvailable = NSNumber(booleanLiteral: newValue?.data != nil)
        }
    }

    // MARK: Private properties

    // Cached decrypted values
    private var decryptedAudioBlobID: Data?
    private var decryptedAudioSize: Int32?
    private var decryptedDuration: Float? // Non optional
    private var decryptedEncryptionKey: Data?
    private var decryptedDataAvailable: Bool?

    // MARK: - Lifecycle

    /// Preferred initializer that ensures all non optional values are set
    /// - Parameters:
    ///   - context: Managed object context to insert created entity into
    ///   - id: Message ID
    ///   - isOwn: Did I send the message?
    ///   - audioBlobID: BlobID of the audio data
    ///   - audioSize: Size of the audio data
    ///   - duration: Duration of the audio
    ///   - encryptionKey: Key the audio data is encrypted with
    ///   - progress: Progress
    ///   - conversation: Conversation the message belongs to
    ///   - audio: `AudioDataEntity` to which the audio is saved
    init(
        context: NSManagedObjectContext,
        id: Data,
        isOwn: Bool,
        audioBlobID: Data? = nil,
        audioSize: UInt32? = nil,
        duration: Float = 0,
        encryptionKey: Data? = nil,
        progress: Float? = nil,
        conversation: ConversationEntity,
        audio: AudioDataEntity? = nil,
    ) {
        let entity = NSEntityDescription.entity(forEntityName: "AudioMessage", in: context)!
        super.init(entity: entity, insertInto: context, id: id, isOwn: isOwn, conversation: conversation)

        setAudioBlobID(audioBlobID)

        if let audioSize {
            setAudioSize(audioSize as NSNumber)
        }

        setDuration(duration as NSNumber)
        setEncryptionKey(encryptionKey)

        if let progress {
            self.progress = progress as NSNumber
        }

        self.audio = audio
    }

    @available(*, unavailable)
    init() {
        fatalError("\(#function) not implemented")
    }

    @available(*, unavailable)
    convenience init(context: NSManagedObjectContext) {
        fatalError("\(#function) not implemented")
    }

    // MARK: Public functions

    #if !DEBUG
        override public var debugDescription: String {
            "<\(type(of: self))>:\(AudioMessageEntity.self), audioBlobId = \("***"), audioSize = \(audioSize?.description ?? "nil"), duration = \(duration.description), encryptionKey = \("***"), progress = \(progress?.description ?? "nil"), audio = \(audio?.description ?? "nil"), dataAvailable = \(dataAvailable)"
        }
    #endif

    // MARK: - Custom get/set functions

    // MARK: AudioBlobID

    private func getAudioBlobID() -> Data? {
        var value: Data?
        guard let managedObjectContext else {
            return value
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            decryptOptional(&decryptedAudioBlobID, forKey: Self.encryptedAudioBlobIDName)
            value = decryptedAudioBlobID
        }
        else {
            willAccessValue(forKey: Self.audioBlobIDName)
            value = primitiveValue(forKey: Self.audioBlobIDName) as? Data
            didAccessValue(forKey: Self.audioBlobIDName)
        }
        return value
    }

    private func setAudioBlobID(_ newValue: Data?) {
        guard let managedObjectContext else {
            return
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            encryptOptional(newValue, forKey: Self.encryptedAudioBlobIDName)
            decryptedAudioBlobID = newValue
        }
        else {
            willChangeValue(forKey: Self.audioBlobIDName)
            setPrimitiveValue(newValue, forKey: Self.audioBlobIDName)
            didChangeValue(forKey: Self.audioBlobIDName)
        }
    }

    // MARK: AudioSize

    private func getAudioSize() -> NSNumber? {
        var value: NSNumber?
        guard let managedObjectContext else {
            return value
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            decryptOptional(&decryptedAudioSize, forKey: Self.encryptedAudioSizeName)
            if let decryptedAudioSize {
                value = NSNumber(integerLiteral: Int(decryptedAudioSize))
            }
        }
        else {
            willAccessValue(forKey: Self.audioSizeName)
            value = primitiveValue(forKey: Self.audioSizeName) as? NSNumber
            didAccessValue(forKey: Self.audioSizeName)
        }
        return value
    }

    private func setAudioSize(_ newValue: NSNumber?) {
        guard let managedObjectContext else {
            return
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            encryptOptional(newValue?.int32Value, forKey: Self.encryptedAudioSizeName)
            decryptedAudioSize = newValue?.int32Value
        }
        else {
            willChangeValue(forKey: Self.audioSizeName)
            setPrimitiveValue(newValue, forKey: Self.audioSizeName)
            didChangeValue(forKey: Self.audioSizeName)
        }
    }

    // MARK: Duration

    private func getDuration() -> NSNumber {
        var value: NSNumber = 0
        guard let managedObjectContext else {
            return value
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            decrypt(&decryptedDuration, forKey: Self.encryptedDurationName)
            if let decryptedDuration {
                value = NSNumber(value: decryptedDuration)
            }
        }
        else {
            willAccessValue(forKey: Self.durationName)
            value = primitiveValue(forKey: Self.durationName) as? NSNumber ?? value
            didAccessValue(forKey: Self.durationName)
        }
        return value
    }

    private func setDuration(_ newValue: NSNumber) {
        guard let managedObjectContext else {
            return
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            encrypt(newValue.floatValue, forKey: Self.encryptedDurationName)
            decryptedDuration = newValue.floatValue
        }
        else {
            willChangeValue(forKey: Self.durationName)
            setPrimitiveValue(newValue, forKey: Self.durationName)
            didChangeValue(forKey: Self.durationName)
        }
    }

    // MARK: EncryptionKey

    private func getEncryptionKey() -> Data? {
        var value: Data?
        guard let managedObjectContext else {
            return value
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            decryptOptional(&decryptedEncryptionKey, forKey: Self.encryptedEncryptionKeyName)
            value = decryptedEncryptionKey
        }
        else {
            willAccessValue(forKey: Self.encryptionKeyName)
            value = primitiveValue(forKey: Self.encryptionKeyName) as? Data
            didAccessValue(forKey: Self.encryptionKeyName)
        }
        return value
    }

    private func setEncryptionKey(_ newValue: Data?) {
        guard let managedObjectContext else {
            return
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            encryptOptional(newValue, forKey: Self.encryptedEncryptionKeyName)
            decryptedEncryptionKey = newValue
        }
        else {
            willChangeValue(forKey: Self.encryptionKeyName)
            setPrimitiveValue(newValue, forKey: Self.encryptionKeyName)
            didChangeValue(forKey: Self.encryptionKeyName)
        }
    }
    
    // MARK: DataAvailable
    
    private func getDataAvailable() -> NSNumber {
        var value: NSNumber = NSNumber(value: false)
        guard let managedObjectContext else {
            return value
        }

        if managedObjectContext.usesAdditionallyEncryptedModel {
            decryptOptional(&decryptedDataAvailable, forKey: Self.encryptedDataAvailableName)
            if let decryptedDataAvailable {
                value = NSNumber(booleanLiteral: decryptedDataAvailable)
            }
        }
        else {
            willAccessValue(forKey: Self.dataAvailableName)
            value = primitiveValue(forKey: Self.dataAvailableName) as? NSNumber ?? value
            didAccessValue(forKey: Self.dataAvailableName)
        }
        return value
    }
    
    private func setDataAvailable(_ newValue: NSNumber?) {
        guard let managedObjectContext else {
            return
        }
        
        if managedObjectContext.usesAdditionallyEncryptedModel {
            encryptOptional(newValue?.boolValue, forKey: Self.encryptedDataAvailableName)
            decryptedDataAvailable = newValue?.boolValue
        }
        else {
            willChangeValue(forKey: Self.dataAvailableName)
            setPrimitiveValue(newValue, forKey: Self.dataAvailableName)
            didChangeValue(forKey: Self.dataAvailableName)
        }
    }

    // MARK: - Clearing cached values
    
    override public func didChangeValue(forKey key: String) {
        if key == Self.encryptedAudioBlobIDName {
            decryptedAudioBlobID = nil
        }
        else if key == Self.encryptedAudioSizeName {
            decryptedAudioSize = nil
        }
        else if key == Self.encryptedDurationName {
            decryptedDuration = nil
        }
        else if key == Self.encryptedEncryptionKeyName {
            decryptedEncryptionKey = nil
        }
        else if key == Self.encryptedDataAvailableName {
            decryptedDataAvailable = nil
        }
        super.didChangeValue(forKey: key)
    }

    override public func didTurnIntoFault() {
        decryptedAudioBlobID = nil
        decryptedAudioSize = nil
        decryptedDuration = nil
        decryptedEncryptionKey = nil
        decryptedDataAvailable = nil
        super.didTurnIntoFault()
    }
}
