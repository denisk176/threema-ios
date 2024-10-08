//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2019-2021 Threema GmbH
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

import XCTest

import ThreemaEssentials
@testable import Threema
@testable import ThreemaFramework

class DBLoadTests: XCTestCase {

    override func setUp() {
        // necessary for ValidationLogger
        AppGroup.setGroupID("group.ch.threema") // THREEMA_GROUP_IDENTIFIER @"group.ch.threema"
    }

    /// Print out shell commands to copy database and external data form simulator. To prepare database before, run
    /// methods in this file like 'testDbLoad'.
    func testCopyOldVersionOfDatabase() {
        
        let databasePath = FileUtility.shared.appDataDirectory?.path
        
        if databasePath != nil {
            print("\nCopy 'old' version of database for testing DB migration:")
            print("""
                \n
                cd \(databasePath!)
                tar cf ThreemaDataOldVersion.tar.gz .ThreemaData_SUPPORT ThreemaData.sqlite
                mv ThreemaDataOldVersion.tar.gz ~/Documents/
                cd ~/Documents
                mkdir ThreemaDataOldVersion
                tar xf ThreemaDataOldVersion.tar.gz -C ./ThreemaDataOldVersion
                \n
                """)
            print(
                "As last step copy the directory 'ThreemaDataOldVersion' via iTunes into 'applicationDocuments' of Threema.\n"
            )
        }

        XCTAssertNotNil(databasePath)
    }

    /// Generate duplicate contacts of each existing contact:
    /// - create a 1:1 conversation with some messages for the first duplicate contact
    /// - create 10 call history entries for the first duplicate contact
    /// - create a group for all existing identities plus all new duplicates, with some messages
    /// This test is useful to test "Settings - Advanced - Contacts Cleanup"
    ///
    /// Note: the database must contain at least 2 nonduplicate contacts before running this test
    func testGenerateDuplicateContacts() async throws {
        let em = EntityManager(withChildContextForBackgroundProcess: true)

        let allContactIdentity: [String] = await em.perform {
            (em.entityFetcher.allContacts() as? [ContactEntity])?.map(\.identity) ?? [String]()
        }

        guard allContactIdentity.count >= 2 else {
            print("\nSkipping test, please first add at least 2 contacts\n")
            return
        }

        let newDuplicateContacts = await em.perform {
            var newDuplicateContacts = [ContactEntity]()

            for identity in allContactIdentity {

                if let contactsForIdentity = em.entityFetcher.allContacts(forID: identity) as? [ContactEntity],
                   contactsForIdentity.count == 1,
                   let contact = contactsForIdentity.first {

                    print("Create duplicate contact for \(identity)")
                    if let duplicateContact = em.entityCreator.contact() {
                        duplicateContact.identity = identity
                        duplicateContact.firstName = "Duplicate of"
                        duplicateContact.lastName = identity
                        duplicateContact.publicKey = contact.publicKey
                        duplicateContact.verificationLevel = contact.verificationLevel
                        duplicateContact.workContact = contact.workContact
                        duplicateContact.forwardSecurityState = contact.forwardSecurityState
                        duplicateContact.featureMask = contact.featureMask
                        duplicateContact.isContactHidden = contact.isContactHidden
                        duplicateContact.typingIndicator = contact.typingIndicator
                        duplicateContact.readReceipt = contact.readReceipt
                        duplicateContact.importedStatus = contact.importedStatus
                        duplicateContact.publicNickname = contact.publicNickname

                        newDuplicateContacts.append(duplicateContact)
                    }
                }
            }

            return newDuplicateContacts
        }

        guard !newDuplicateContacts.isEmpty else {
            print("No duplicates created, terminating test.")
            return
        }

        await em.performSave {

            //
            // create 1:1 conversation for the first duplicated contact
            //

            if let firstDuplicateContact = newDuplicateContacts.first {
                self.addOneToOneTextMessage(
                    "This message was received",
                    isOwn: false,
                    contact: firstDuplicateContact,
                    entityManager: em
                )
                self.addOneToOneTextMessage(
                    "This message was sent",
                    isOwn: true,
                    contact: firstDuplicateContact,
                    entityManager: em
                )
                print(
                    "Created (duplicate) 1:1 conversation with \(firstDuplicateContact.identity) and sent/received messages"
                )
            }

            //
            // create call history entries for duplicate contact
            //

            if let firstDuplicateContact = newDuplicateContacts.first {
                // inspired from CallHistoryManager / CallHistoryManagerTests
                for _ in 0..<10 {
                    if let call = em.entityCreator.callEntity() {
                        call.callID = NSNumber(value: UInt32.random(in: UInt32.min..<UInt32.max))
                        call.date = Date()
                        call.contact = firstDuplicateContact
                    }
                }
                print(
                    "Created 10 (invisible) call history entries for duplicate of \(firstDuplicateContact.identity)"
                )
            }
        }

        //
        // create group with duplicate contacts
        //

        let group = try await createGroup(
            named: "Duplicate members in this group",
            with: allContactIdentity,
            entityManager: em
        )

        await em.performSave {
            group.conversation.addMembers(Set(newDuplicateContacts))
            for duplicateContact in newDuplicateContacts {
                let mainContact = em.entityFetcher.contact(for: duplicateContact.identity)

                self.addGroupTextMessage("From main contact", sender: mainContact, in: group, entityManager: em)
                self.addGroupTextMessage(
                    "From duplicate contact",
                    sender: duplicateContact,
                    in: group,
                    entityManager: em
                )
            }
            print(
                "Created group conversation '\(group.name ?? "-")' with regular and duplicate members and received messages"
            )

            //
            // add rejected message at the end of the group
            //

            let message = self.addGroupTextMessage(
                "From myself. Rejected by 50% main contacts and 50% duplicates.",
                in: group,
                entityManager: em
            )
            message.sendFailed = NSNumber(booleanLiteral: true)
            for i in 0..<newDuplicateContacts.count {
                // alternate between regular and duplicate contacts
                let duplicate = newDuplicateContacts[i]
                let contact = i % 2 == 0 ? duplicate : em.entityFetcher.contact(for: duplicate.identity)
                message.addRejectedBy(contact!)
            }
            print(
                "Added message in group '\(group.name ?? "-")' rejected by various main contacts/duplicates"
            )
        }
    }

    /// Add 10000 messages (./Resources/test_texts.json) to ECHOECHO for testing.
    func testLoadTextMessages() throws {
        let testBundle = Bundle(for: DBLoadTests.self)

        guard let textsPath = testBundle.url(forResource: "test_texts", withExtension: "json") else {
            XCTFail("Cannot find file with test texts")
            return
        }
        
        let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: textsPath))
        
        var conversation: Conversation?
        
        _ = createContacts(for: ["ECHOECHO"])
        
        let entityManager = EntityManager()
        entityManager.performAndWaitSave {
            if let contact = entityManager.entityFetcher.contact(for: "ECHOECHO") {
                conversation = entityManager.conversation(forContact: contact, createIfNotExisting: true)
            }
        }
        
        entityManager.performAndWaitSave {
            for index in 0..<100_000 {
                let calendar = Calendar.current
                let date = calendar.date(byAdding: .hour, value: index, to: Date(timeIntervalSince1970: 0))
                let message = entityManager.entityCreator.textMessage(
                    for: conversation,
                    setLastUpdate: true
                )!
                message.text = "\(index) - \(texts[index % texts.count])"
                message.date = date
                message.sender = conversation?.contact
                message.sent = true
                message.delivered = true
                message.read = true
                message.remoteSentDate = Date()
                print("\(index)/100'000")
            }
        }
    }

    func testImportTestLiveIDs() {
        let testIDs = [
            "4SA2FT56", "Y7D72UZ2", "YT2UREKN", "Y2ZS4H4Y", "HV7UKC9B", "S8T7SKVP", "JEAR4C68", "299N6FAF",
            "8JA7ZRHX", "NJ9NYUNU", "3AD82KSN", "8T6Y4MTA", "C2NTU8DS", "ABP323M8", "MSAAJY4R", "CF6BWXYE",
            "A9CDB69Z", "BNKTHA3X", "W9JYWXHM", "MRB4X6NY", "JTPT46YP", "6M59BE5H", "3328D2U6", "PWM5HHTK",
            "D4NVXVYZ", "9UNACVPH", "94SBW52N", "2MCMK2V8", "JBB56TAU", "8PFR4VMC", "V92D9CDN", "38S27RMC",
            "CPUC6WH9", "C97DW8TJ", "7RWVXVY9", "BJJFNHEZ", "8P3H8ADN", "U6JXRHKX", "Z3PFEKWT", "NZETVFTY",
            "ENUA5S5D", "6HJTP8XV", "PBJST426", "ZB48CUSJ", "Z3JJZ436", "ZU5TRUAM", "H6AXSHKC", "5U38HREW",
            "9N2A8689", "NS5EJ4JJ", "95MHAUMK", "UDNEPRMM", "MYJJF7WH", "AX6BBU4K", "RBT83N6W", "P3PM59D7",
            "XWPSAUSE", "DY7HMAKN", "ECP4HFWE", "FXHR5WFX", "XERCUKNS", "NRH4F2JM", "RY4PAMSV", "FD4D5H6H",
            "DH5WZHYK", "HJA2S8HA", "2HC47N7Z", "RNJRZPWF", "TCZ3AZ9U", "78Y2MEV6", "EA3SKCJE", "SCV2RXFD",
            "8V2RMJ28", "C5WF6E79", "669E8U8D", "KZ3CCF88", "RBAS3SBX", "6HSE6VVE", "CXF84N53", "W7KTP29Y",
            "YRE95V2W", "CPXDFB4M", "F35HXBE3", "XRJZTWXP", "5ZDNC5NZ", "7PVKMD6Y", "92KEZ9H9", "98P3ZJFY",
            "ADDRTCNX", "8K43TJ9Y", "JAZR8BHV", "TMZJ3E5P", "N9KS9ZMX", "FS46TYHE", "FNHVBMD2", "X6KN2NKU",
            "ASDUT598", "F4NWU2WY", "2R9TXZMV", "9X7XBJAN", "DFNMZWRZ", "N4PKWSJ5", "NX57R85W", "95RA89WF",
            "57JTE5EK", "TMV4ZCBK", "97NHH47W", "X7P8B8MM", "5AJ6WD6B", "U89FSTN8", "CHANPKUP", "NKPMFP92",
            "Y4T3YKW6", "4H6FD5AM", "AYPJVYRS", "D3YAX8BB", "664NJK2C", "YFUF8T5M", "YV3YD9YH", "E272NS79",
            "DJ8TBMWR", "CH5E8AAF", "R9V9EZ55", "NZ7RSKUB", "5SWJ9KPM", "S4XZPWER", "CZT7WN8C", "J2E9UPY3",
            "7KMUDH6Z", "583ACKJJ", "4MHT43PT", "A322VDCZ", "V44EUFVE", "AJ78UVJD", "JRDDC6J9", "89WPPC28",
            "M3Z7A9NF", "TNPEMDAM", "TJT4Y8HD", "9D58MRVF", "VD59NC8Y", "TPVCT7XB", "RN57D48P", "V7T4NFUF",
            "9S5NZ2MS", "FJUTHMXN", "4N6EKVVB", "22YWHRNT", "N9RJCB6H", "86DWR5FS", "FCU2RFU9", "BUHJVECK",
            "7YC7JRY5", "2H35ZCHN", "YVRKD6K6", "K7D2DVPA", "AH5K4J36", "9E55UB2K", "BVX4NFF5", "J8CKV4C2",
            "F9CTVB88", "RZ6V4K7P", "3BZ66RCS", "YSWVXUZP", "H8P8FSK7", "J4NZ8A9F", "Z3R4JBKY", "C36BBD72",
            "DD52YEPB", "8U88DSJA", "UE9C74SD", "AUBDPXFM", "AW5BE83S", "58NJCKPD", "9877UEYD", "X5CNADHT",
            "F7F8VD53", "4995K37U", "4KBMDY73", "AZ2HKVXZ", "BR9C76FH", "7TADJ5K7", "JBYYFUMY", "2SKTMD5T",
            "TV4TRXYW", "BVNNVD5J", "48B4E2ER", "92WZ8DDH", "EJZJX2MM", "CT8BW584", "BDB72MVX", "BAXV3XUK",
            "45MVVWHB", "7CXV8JUK", "2DET88WJ", "3ENE9X42", "EJEWJ8F7", "8827FF7U", "FEAUXBT3", "MVZ7NYVR",
            "N46FZW8C", "3F87E2D5", "EWTV2K82", "KYK5YW9E", "V3BESYSR", "53YCJ4ZS", "PFAPHCT7", "KNZNMSX5",
            "Y3ER2RH7", "R9ND6T48", "3K6KHP7C", "U4DZ9JCN", "MSR393YW", "A336U2RE", "Z3BVCPA3", "JF96657J",
            "B5CZA8YK", "3ECSYCJD", "X94D97KN", "PV2R9X34", "8XDVA2F7", "RXR58XAS", "7VVC63T5", "AYNJNXKY",
            "AUWNU8H4", "PDE5CCXY", "BUH7VMKZ", "WTJK9VST", "9RXHBE2N", "YZH66YC6", "677Y6YVW", "2D4EVX57",
            "77PW947J", "A3PYY24W", "HZ4EYB6V", "ZPT9VWPD", "3Z3EKUAV", "ASDDX5AE", "76NE2Y2C", "PZSX3XUW",
            "5TA948ZN", "TZ5DFKDP", "8T2EY7WY", "5DW6XRVM", "76UA8N39", "UPH2ENA7", "SZMAK3K7", "VKCCWD3J",
            "9WS3HKB3", "WTY5WTRH", "ZBT98WNS", "TPJSH62P", "EWH275UV", "R9XFZKYV", "CTM4XR2J", "JM5VD3UX",
            "AR9394S3", "RX7Y9N9S", "5PTBNNCW", "2UR8PYN2", "8UCCTRJX", "3KWWDN3Z", "3FMRF8V3", "PFT4Y2DP",
            "2MUJAHE7", "WNPFHRFM", "6AXTPA93", "D5PE9W9X", "B9MX8K69", "S2WYS8JA", "SW35VYZF", "HHDEPX43",
            "CTD47XRK", "PFZS2AP8", "J4DP9N3Z", "RN9495A7", "V88EY5E5", "EW4ERCX6", "H78FPRFS", "P7J6AENR",
            "UU7VHDVW", "PSSF8KAA", "PWDVRCDD", "YAKFAKPX", "SFM6DSVZ", "BB4ZTPM9", "UUZW2D9W", "ABYDNFYS",
            "RSDSENRV", "XV7XWHEM", "JESYRPPR", "8FHKVCA2", "XZ8BTYXE", "UNZRF545", "JSYT4MTK", "MWDJBKYB",
            "7TNKPMDU", "2SRE23ST", "ANEYAN3J", "RB7C3E5H",
        ]

        _ = createContacts(for: testIDs)
    }
    
    /// Add 1000 messages to every contacts conversation with wrong last message and count of unread messages.
    /// To test last message workaround (see `AppLaunchTasks.checkLastMessageOfAllConversations()`)
    func testLoadTextMessagesToAllOneToOneConversations() throws {
        let testBundle = Bundle(for: DBLoadTests.self)

        guard let textsPath = testBundle.url(forResource: "test_texts", withExtension: "json") else {
            XCTFail("Cannot find file with test texts")
            return
        }

        let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: textsPath))

        let entityManager = EntityManager()
        entityManager.performAndWaitSave {
            for item in entityManager.entityFetcher.allContacts() {
                guard let contactEntity = item as? ContactEntity, !contactEntity.isContactHidden else {
                    continue
                }

                _ = entityManager.conversation(forContact: contactEntity, createIfNotExisting: true)
            }
        }

        entityManager.performAndWait {
            for item in entityManager.entityFetcher.allConversations() {
                guard let conversation = item as? Conversation else {
                    continue
                }

                var lastMessage: BaseMessage?

                entityManager.performAndWaitSave {
                    for index in 0..<1000 {
                        let calendar = Calendar.current
                        let date = calendar.date(byAdding: .second, value: index, to: Date(timeIntervalSince1970: 0))
                        let message = entityManager.entityCreator.textMessage(for: conversation, setLastUpdate: true)!
                        message.text = "\(index) - \(texts[index % texts.count])"
                        message.isOwn = index % 4 == 0 ? true : false
                        message.date = date
                        message.sender = conversation.contact
                        message.sent = true
                        message.delivered = true
                        message.read = index % 5 == 0 ? true : false
                        message.remoteSentDate = Date()

                        if index == 998 {
                            lastMessage = message
                        }

                        print("\(index)/1000")
                    }
                }

                entityManager.performAndWaitSave {
                    // Set wrong last message and count of unread messages deliberately
                    conversation.lastMessage = lastMessage
                    conversation.unreadMessageCount = 0
                }
            }
        }
    }

    func testUnreadMessagesCount() throws {
        let testBundle = Bundle(for: DBLoadTests.self)

        guard let textsPath = testBundle.url(forResource: "test_texts", withExtension: "json") else {
            XCTFail("Cannot find file with test texts")
            return
        }

        let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: textsPath))

        var conversation: Conversation?

        let entityManager = EntityManager()

        let senders = ["ECHOECHO"]
        _ = createContacts(for: senders)
        for sender in senders {
            entityManager.performAndWaitSave {
                if let contact = entityManager.entityFetcher.contact(for: sender) {
                    conversation = entityManager.conversation(forContact: contact, createIfNotExisting: true)
                }
            }

            for index in 0..<5000 {
                entityManager.performAndWaitSave {
                    let calendar = Calendar.current
                    let date = calendar.date(byAdding: .second, value: +index, to: Date())
                    let message = entityManager.entityCreator.textMessage(for: conversation, setLastUpdate: true)!
                    let isOwn = index % 3 == 0 ? false : true
                    message.isOwn = NSNumber(booleanLiteral: isOwn)
                    message.text = texts[index % texts.count]
                    message.date = date
                    message.sent = true
                    message.delivered = true
                    if !isOwn {
                        message.sender = conversation?.contact
                        message.read = index % 5 == 0 ? true : false
                        message.readDate = index % 5 == 0 ? date : nil
                    }
                    message.remoteSentDate = date
                }
            }
        }
    }

    func testFillGroupsWithText() throws {
        let testBundle = Bundle(for: DBLoadTests.self)

        guard let textsPath = testBundle.url(forResource: "test_texts", withExtension: "json") else {
            XCTFail("Cannot find file with test texts")
            return
        }
        
        let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: textsPath))
        
        let entityManager = EntityManager()

        for num in 0..<1000 {
            for groupConversation in entityManager.entityFetcher.allGroupConversations() as! [Conversation] {
                entityManager.performAndWaitSave {
                    for contact in entityManager.entityFetcher.allContacts() as! [ContactEntity] {
                        let calendar = Calendar.current
                        let date = calendar.date(byAdding: .hour, value: 1, to: Date(timeIntervalSince1970: 0))
                        let message = entityManager.entityCreator.textMessage(
                            for: groupConversation,
                            setLastUpdate: true
                        )!
                        message.text = "Message \(num) from \(contact.identity) \(texts[num % texts.count])"
                        message.date = date
                        message.sender = contact
                        message.isOwn = NSNumber(booleanLiteral: false)
                        message.remoteSentDate = date
                    }
                }
            }
        }

        if let groupConversations = entityManager.entityFetcher.allGroupConversations() as? [Conversation] {
            let unreadMessages = UnreadMessages(messageSender: MessageSenderMock(), entityManager: entityManager)
            unreadMessages.totalCount(doCalcUnreadMessagesCountOf: Set(groupConversations))
        }
    }
    
    /// Adding 160 contacts with Threema ID's (./Resources/test_ids.txt) for testing.
    func testLoadContacts() throws {
        let testBundle = Bundle(for: DBLoadTests.self)
        let filePath = try XCTUnwrap(testBundle.path(forResource: "test_ids", ofType: "txt"))
        
        do {
            var fetchIdentities = [String]()
            
            let ids = try String(contentsOfFile: filePath, encoding: .utf8)
            for id in ids.components(separatedBy: .newlines) {
                if !id.isEmpty {
                    fetchIdentities.append(id)
                }
            }
            
            try addContacts(for: fetchIdentities, entityManager: EntityManager())
        }
        catch {
            print(error)
        }
    }
    
    // This doesn't seem to work right now as the network calls seem to block infinitely
    // This is probably due to the fact of `semaphore.wait()` blocking the main thread and `fetchBulkIdentityInfo`
    // running on the main thread as well.
    private func addContacts(for ids: [String], entityManager: EntityManager) throws {
        let queue = DispatchQueue.global()
        let semaphore = DispatchSemaphore(value: 0)
        
        var pks = [String: Data]()

        queue.async {
            let api = ServerAPIConnector()
            api.fetchBulkIdentityInfo(ids, onCompletion: { identities, publicKeys, _, _, _ in
                
                for index in 0..<(identities!.count - 1) {
                    pks[identities![index] as! String] = Data(base64Encoded: publicKeys![index] as! String)
                }
                
                semaphore.signal()
            }) { error in
                print(error?.localizedDescription ?? "")
                
                semaphore.signal()
            }
        }
        
        semaphore.wait()
        
        for pk in pks {
            print("add id: \(pk.key)")
            
            entityManager.performAndWaitSave {
                if let contact = entityManager.entityCreator.contact() {
                    contact.identity = pk.key
                    contact.verificationLevel = 0
                    contact.publicNickname = pk.key
                    contact.isContactHidden = false
                    contact.workContact = 0
                    contact.publicKey = pk.value
                }
            }
        }
    }
    
    func testAssignImagesToAllContacts() {
        let entityManager = EntityManager()
        
        for contact in entityManager.entityFetcher.allContacts() as! [ContactEntity] {
            
            let testBundle = Bundle(for: DBLoadTests.self)
            let testImageURL = testBundle.url(forResource: "Bild-1-0", withExtension: "jpg")
            let testImageData = try? Data(contentsOf: testImageURL!)
            let resizedTestImage = MediaConverter.scaleImageData(testImageData!, toMaxSize: 512)?
                .jpegData(compressionQuality: 0.99)!
            
            entityManager.performAndWaitSave {
                let imageData = entityManager.entityCreator.imageData()!
                imageData.data = resizedTestImage
                imageData.width = 512
                imageData.height = 512
                
                contact.contactImage = imageData
            }
        }
    }
    
    func testLoadImageFileMessages() {
        var conversation: Conversation?
        
        _ = createContacts(for: ["ECHOECHO"])
        let entityManager = EntityManager(withChildContextForBackgroundProcess: false)
        entityManager.performAndWaitSave {
            if let contact = entityManager.entityFetcher.contact(for: "ECHOECHO") {
                conversation = (entityManager.conversation(forContact: contact, createIfNotExisting: true))!
            }
        }
        
        let imageCount = 100_000
        
        for i in 0..<imageCount {
            let log = "Image: \(i) / \(imageCount)"
            print(log)
            let testBundle = Bundle(for: DBLoadTests.self)
            let testImageURL = testBundle.url(forResource: "Bild-1-0", withExtension: "jpg")
            let testImageData = try? Data(contentsOf: testImageURL!)
            
            loadImage(with: testImageData!, conversation!, entityManager, log)
        }
    }
    
    func loadImage(
        with imageData: Data,
        _ conversation: Conversation,
        _ entityManager: EntityManager,
        _ caption: String
    ) {
        
        entityManager.performAndWaitSave {
            let dbFile: FileData = (entityManager.entityCreator.fileData())!
            dbFile.data = imageData
            
            let thumbnailFile: ImageData = entityManager.entityCreator.imageData()!
            thumbnailFile.data = MediaConverter.getThumbnailFor(UIImage(data: imageData)!)?
                .jpegData(compressionQuality: 1.0)
            
            let message: FileMessageEntity = (entityManager.entityCreator.fileMessageEntity(for: conversation))!
            message.data = dbFile
            message.thumbnail = thumbnailFile
            message.fileName = "Bild.jpeg"
            message.fileSize = NSNumber(integerLiteral: dbFile.data!.count)
            message.mimeType = "image/jpeg"
            message.type = NSNumber(integerLiteral: 1)
            message.date = Date(timeIntervalSinceReferenceDate: TimeInterval(-1 * Int.random(in: 0...223_456_789)))
            message.deliveryDate = message.date
            message.sender = conversation.contact
            message.sent = NSNumber(booleanLiteral: true)
            message.delivered = NSNumber(booleanLiteral: true)
            message.read = NSNumber(booleanLiteral: true)
            message.remoteSentDate = Date()
            message.encryptionKey = NaClCrypto.shared().randomBytes(kBlobKeyLen)
            
            do {
                if let jsonWithoutCaption = FileMessageEncoder.jsonString(for: message),
                   let dataWithoutCaption = jsonWithoutCaption.data(using: .utf8),
                   var dict = try JSONSerialization.jsonObject(with: dataWithoutCaption) as? [String: AnyObject] {
                    dict["d"] = caption as AnyObject
                    let dataWithCaption = try JSONSerialization.data(withJSONObject: dict)
                    message.json = String(data: dataWithCaption, encoding: .utf8)
                }
            }
            catch {
                // do nothing
            }
        }
    }
    
    // TODO: Call messages (IOS-3033)
    
    // MARK: - Groups with single set of messages
    
    // MARK: Text messages with quotes

    func testGroupWithQuoteMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let testBundle = Bundle(for: DBLoadTests.self)
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "Quote Messages", with: [], entityManager: entityManager)

        // Sender
        _ = createContacts(for: ["ECHOECHO"])
        let senderContact = try XCTUnwrap(entityManager.entityFetcher.contact(for: "ECHOECHO"))
        
        // Load texts
        let testTextsURL = try XCTUnwrap(testBundle.url(forResource: "test_texts", withExtension: "json"))
        let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: testTextsURL))
        
        // Create set of messages to quote
        
        var quotableMessages = [BaseMessage]()
        
        // Text messages
        entityManager.performAndWaitSave {
            let outgoingMessage = entityManager.entityCreator.textMessage(for: group.conversation, setLastUpdate: true)!
            outgoingMessage.text = texts[0]
            outgoingMessage.date = Date()
            outgoingMessage.sent = true
            outgoingMessage.delivered = true
            outgoingMessage.remoteSentDate = Date()
            outgoingMessage.deliveryDate = Date()
            outgoingMessage.isOwn = true
            quotableMessages.append(outgoingMessage)
            
            let incomingMessage = entityManager.entityCreator.textMessage(for: group.conversation, setLastUpdate: true)!
            incomingMessage.text = texts[1]
            incomingMessage.date = Date()
            incomingMessage.sent = true
            incomingMessage.delivered = true
            incomingMessage.remoteSentDate = Date()
            incomingMessage.deliveryDate = Date()
            incomingMessage.isOwn = false
            incomingMessage.sender = senderContact
            quotableMessages.append(incomingMessage)
        }
        
        // File messages
        
        var senderItems = [URLSenderItem]()
        
        // Load image
        let testImageURL = try XCTUnwrap(testBundle.url(forResource: "Bild-1-0", withExtension: "jpg"))
        let imageSenderItem = try XCTUnwrap(ImageURLSenderItemCreator().senderItem(from: testImageURL))
        senderItems.append(imageSenderItem)
        
        // Load sticker
        let testStickerURL = try XCTUnwrap(testBundle.url(forResource: "Sticker-sine_wave", withExtension: "png"))
        let stickerSenderItem = try XCTUnwrap(URLSenderItem(
            url: testStickerURL,
            type: UTType.png.identifier,
            renderType: 2,
            sendAsFile: false
        ))
        senderItems.append(stickerSenderItem)
        
        // Load animated image
        let testAnimatedImageURL = try XCTUnwrap(testBundle.url(
            forResource: "Animated_two_spur_gears_1_2",
            withExtension: "gif"
        ))
        let animatedImageSenderItem = try XCTUnwrap(ImageURLSenderItemCreator().senderItem(from: testAnimatedImageURL))
        senderItems.append(animatedImageSenderItem)
        
        // Load animated sticker
        let testAnimatedStickerURL = try XCTUnwrap(testBundle.url(
            forResource: "Animated_sticker-sine_wave",
            withExtension: "gif"
        ))
        let animatedStickerSenderItem = try XCTUnwrap(URLSenderItem(
            url: testAnimatedStickerURL,
            type: UTType.gif.identifier,
            renderType: 2,
            sendAsFile: false
        ))
        senderItems.append(animatedStickerSenderItem)
        
        // Load video
        let testVideoURL = try XCTUnwrap(testBundle.url(forResource: "Video-1", withExtension: "mp4"))
        let videoSenderItem = try XCTUnwrap(VideoURLSenderItemCreator().senderItem(from: testVideoURL))
        senderItems.append(videoSenderItem)
        
        // Load voice message
        let testVoiceURL = try XCTUnwrap(testBundle.url(forResource: "audioAnalyzerTest", withExtension: "m4a"))
        let voiceSenderItem = try XCTUnwrap(URLSenderItem(
            url: testVoiceURL,
            type: UTType.mpeg4Audio.identifier,
            renderType: 1,
            sendAsFile: false
        ))
        senderItems.append(voiceSenderItem)
        
        // Load document
        let testFileURL = try XCTUnwrap(testBundle.url(forResource: "Test", withExtension: "pdf"))
        let fileSenderItem = try XCTUnwrap(URLSenderItem(
            url: testFileURL,
            type: UTType.pdf.identifier,
            renderType: 0,
            sendAsFile: false
        ))
        senderItems.append(fileSenderItem)
        
        // Add quotable file messages
        
        var fileMessageCreationError: Error?
        
        entityManager.performAndWaitSave {
            do {
                for senderItem in senderItems {
                    let ownFileMessageEntity = try entityManager.entityCreator.createFileMessageEntity(
                        for: senderItem,
                        in: group.conversation,
                        with: .public
                    )
                    ownFileMessageEntity.isOwn = true
                    quotableMessages.append(ownFileMessageEntity)
                    
                    let otherFileMessageEntity = try entityManager.entityCreator.createFileMessageEntity(
                        for: senderItem,
                        in: group.conversation,
                        with: .public
                    )
                    otherFileMessageEntity.isOwn = false
                    otherFileMessageEntity.sender = senderContact
                    quotableMessages.append(otherFileMessageEntity)
                    
                    // This needs to be last otherwise the `renderType` of stickers will be 1 instead of 2
                    senderItem.caption = texts.randomElement() ?? "Caption"
                    let captionFileMessageEntity = try entityManager.entityCreator.createFileMessageEntity(
                        for: senderItem,
                        in: group.conversation,
                        with: .public
                    )
                    captionFileMessageEntity.isOwn = false
                    captionFileMessageEntity.sender = senderContact
                    quotableMessages.append(captionFileMessageEntity)
                }
            }
            catch {
                fileMessageCreationError = error
            }
        }
        
        if let fileMessageCreationError {
            XCTFail(fileMessageCreationError.localizedDescription)
        }
        
        // Location messages
        
        let testLocationsURL = try XCTUnwrap(testBundle.url(forResource: "test_locations", withExtension: "json"))
        let locations = try JSONDecoder().decode([Location].self, from: Data(contentsOf: testLocationsURL))
        
        entityManager.performAndWaitSave {
            let ownLocationMessage = entityManager.entityCreator.locationMessage(for: group.conversation)!
            ownLocationMessage.latitude = locations[0].latitude as NSNumber
            ownLocationMessage.longitude = locations[0].longitude as NSNumber
            ownLocationMessage.accuracy = locations[0].accuracy as NSNumber
            ownLocationMessage.poiName = locations[0].name
            ownLocationMessage.poiAddress = locations[0].address
            ownLocationMessage.isOwn = true
            quotableMessages.append(ownLocationMessage)
            
            let otherLocationMessage = entityManager.entityCreator.locationMessage(for: group.conversation)!
            otherLocationMessage.latitude = locations[2].latitude as NSNumber
            otherLocationMessage.longitude = locations[2].longitude as NSNumber
            otherLocationMessage.accuracy = locations[2].accuracy as NSNumber
            otherLocationMessage.poiName = locations[2].name
            otherLocationMessage.poiAddress = locations[2].address
            otherLocationMessage.isOwn = false
            otherLocationMessage.sender = senderContact
            quotableMessages.append(otherLocationMessage)

            let anotherLocationMessage = entityManager.entityCreator.locationMessage(for: group.conversation)!
            anotherLocationMessage.latitude = locations[3].latitude as NSNumber
            anotherLocationMessage.longitude = locations[3].longitude as NSNumber
            anotherLocationMessage.accuracy = locations[3].accuracy as NSNumber
            anotherLocationMessage.poiName = locations[3].name
            anotherLocationMessage.poiAddress = locations[3].address
            anotherLocationMessage.isOwn = false
            anotherLocationMessage.sender = senderContact
            quotableMessages.append(anotherLocationMessage)
        }
        
        // TODO: Add quotable ballots to `quotableMessages` (IOS-3033)
        
        // Create quote messages
        
        entityManager.performAndWaitSave {
            for index in 0..<numberOfMessagesToAdd {
                let message = entityManager.entityCreator.textMessage(for: group.conversation, setLastUpdate: true)!
                message.text = "\(index) - \(texts[index % texts.count])"
                message.date = Date()
                message.sent = true
                message.delivered = true
                message.remoteSentDate = Date()
                message.deliveryDate = Date()
                
                // Don't add a quote to every forth message
                if index % 4 > 0 {
                    message.quotedMessageID = quotableMessages[index % quotableMessages.count].id
                }
                
                if index % (alternateEveryXMessage * 2) >= alternateEveryXMessage {
                    // incoming message
                    message.isOwn = false
                    message.sender = senderContact
                }
                else {
                    // outgoing message
                    message.isOwn = true
                }
            }
        }
    }
    
    // MARK: Image file messages

    func testGroupWithImageFileMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "Image File Messages", with: [], entityManager: entityManager)

        // Load image
        let testBundle = Bundle(for: DBLoadTests.self)
        let testImageURL = try XCTUnwrap(testBundle.url(forResource: "Bild-1-0", withExtension: "jpg"))
        let imageSenderItem = try XCTUnwrap(ImageURLSenderItemCreator().senderItem(from: testImageURL))
        
        // Create messages
        try add(
            senderItem: imageSenderItem,
            to: group,
            numberOfMessagesToAdd,
            timesAndAlternateEvery: alternateEveryXMessage,
            entityManager: entityManager
        )
    }
    
    // MARK: Sticker file messages

    func testGroupWithStickerFileMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "Sticker File Messages", with: [], entityManager: entityManager)

        // Load image
        let testBundle = Bundle(for: DBLoadTests.self)
        let testStickerURL = try XCTUnwrap(testBundle.url(forResource: "Sticker-sine_wave", withExtension: "png"))
        let stickerSenderItem = try XCTUnwrap(URLSenderItem(
            url: testStickerURL,
            type: UTType.png.identifier,
            renderType: 2,
            sendAsFile: false
        ))
        
        // Create messages
        try add(
            senderItem: stickerSenderItem,
            showCaptions: false,
            to: group,
            numberOfMessagesToAdd,
            timesAndAlternateEvery: alternateEveryXMessage,
            entityManager: entityManager
        )
    }
    
    // MARK: Animated image file messages

    func testGroupWithAnimatedImageFileMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "Animated Image File Messages", with: [], entityManager: entityManager)

        // Load image
        let testBundle = Bundle(for: DBLoadTests.self)
        let testAnimatedImageURL = try XCTUnwrap(testBundle.url(
            forResource: "Animated_two_spur_gears_1_2",
            withExtension: "gif"
        ))
        let animatedImageSenderItem = try XCTUnwrap(ImageURLSenderItemCreator().senderItem(from: testAnimatedImageURL))
        
        // Create messages
        try add(
            senderItem: animatedImageSenderItem,
            to: group,
            numberOfMessagesToAdd,
            timesAndAlternateEvery: alternateEveryXMessage,
            entityManager: entityManager
        )
    }
    
    // MARK: Animated sticker file messages
    
    func testGroupWithAnimatedStickerFileMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(
            named: "Animated Sticker File Messages",
            with: [],
            entityManager: entityManager
        )

        // Load image
        let testBundle = Bundle(for: DBLoadTests.self)
        let testAnimatedStickerURL = try XCTUnwrap(testBundle.url(
            forResource: "Animated_sticker-sine_wave",
            withExtension: "gif"
        ))
        let animatedStickerSenderItem = try XCTUnwrap(URLSenderItem(
            url: testAnimatedStickerURL,
            type: UTType.gif.identifier,
            renderType: 2,
            sendAsFile: false
        ))
        
        // Create messages
        try add(
            senderItem: animatedStickerSenderItem,
            showCaptions: false,
            to: group,
            numberOfMessagesToAdd,
            timesAndAlternateEvery: alternateEveryXMessage,
            entityManager: entityManager
        )
    }
    
    // MARK: Video file messages

    func testGroupWithVideoFileMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "Video File Messages", with: [], entityManager: entityManager)

        // Load image
        let testBundle = Bundle(for: DBLoadTests.self)
        let testVideoURL = try XCTUnwrap(testBundle.url(forResource: "Video-1", withExtension: "mp4"))
        let videoSenderItem = try XCTUnwrap(VideoURLSenderItemCreator().senderItem(from: testVideoURL))
        
        // Create messages
        try add(
            senderItem: videoSenderItem,
            to: group,
            numberOfMessagesToAdd,
            timesAndAlternateEvery: alternateEveryXMessage,
            entityManager: entityManager
        )
    }
    
    // MARK: Voice file messages

    func testGroupWithVoiceFileMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "Voice File Messages", with: [], entityManager: entityManager)

        // Load image
        let testBundle = Bundle(for: DBLoadTests.self)
        let testVoiceURL = try XCTUnwrap(testBundle.url(forResource: "audioAnalyzerTest", withExtension: "m4a"))
        let voiceSenderItem = try XCTUnwrap(URLSenderItem(
            url: testVoiceURL,
            type: UTType.mpeg4Audio.identifier,
            renderType: 1,
            sendAsFile: false
        ))
        
        // Create messages
        try add(
            senderItem: voiceSenderItem,
            to: group,
            numberOfMessagesToAdd,
            timesAndAlternateEvery: alternateEveryXMessage,
            entityManager: entityManager
        )
    }
    
    // MARK: File file messages

    func testGroupWithFileFileMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "File File Messages", with: [], entityManager: entityManager)

        // Load image
        let testBundle = Bundle(for: DBLoadTests.self)
        let testFileURL = try XCTUnwrap(testBundle.url(forResource: "Test", withExtension: "pdf"))
        let fileSenderItem = try XCTUnwrap(URLSenderItem(
            url: testFileURL,
            type: UTType.pdf.identifier,
            renderType: 0,
            sendAsFile: false
        ))
        
        // Create messages
        try add(
            senderItem: fileSenderItem,
            to: group,
            numberOfMessagesToAdd,
            timesAndAlternateEvery: alternateEveryXMessage,
            entityManager: entityManager
        )
    }
    
    // MARK: Call Status Message
    
    func testCallStatusMessages() {
        let numberOfMessagesToAdd = 500
        let alternateEveryXMessage = 10
        let identity = "ECHOECHO"
        
        _ = createContacts(for: [identity])
        
        let entityManager = EntityManager()
        
        // Load conversation
        var conversation: Conversation!
        
        entityManager.performAndWaitSave {
            if let contact = entityManager.entityFetcher.contact(for: identity) {
                conversation = entityManager.conversation(forContact: contact, createIfNotExisting: true)
            }
        }
        
        let incomingCallStates: [Int] = [
            kSystemMessageCallMissed,
            kSystemMessageCallRejected,
            kSystemMessageCallRejectedBusy,
            kSystemMessageCallRejectedTimeout,
            kSystemMessageCallEnded,
            kSystemMessageCallRejectedDisabled,
            kSystemMessageCallRejectedUnknown,
        ]
        
        let outgoingCallStates: [Int] = [
            kSystemMessageCallRejected,
            kSystemMessageCallRejectedBusy,
            kSystemMessageCallRejectedTimeout,
            kSystemMessageCallEnded,
            kSystemMessageCallRejectedDisabled,
            kSystemMessageCallRejectedUnknown,
        ]
        
        for index in 0..<numberOfMessagesToAdd {
            let isIncoming = index % (alternateEveryXMessage * 2) >= alternateEveryXMessage
            let callType = isIncoming ? incomingCallStates[index % incomingCallStates.count] :
                outgoingCallStates[index % outgoingCallStates.count]
            
            entityManager.performAndWaitSave {
                guard let systemMessage = entityManager.entityCreator.systemMessage(for: conversation) else {
                    XCTFail("Could not create system message")
                    return
                }
                
                systemMessage.remoteSentDate = Date()
                systemMessage.type = NSNumber(integerLiteral: callType)
                
                var callInfo = [
                    "DateString": DateFormatter.shortStyleTimeNoDate(Date()),
                    "CallInitiator": NSNumber(booleanLiteral: isIncoming),
                ] as [String: Any]
                
                if index % (incomingCallStates.count + outgoingCallStates.count) == 0,
                   callType == kSystemMessageCallEnded {
                    callInfo["CallTime"] = DateFormatter.timeFormatted(Int.random(in: 1..<60 * 60 * 48))
                }
                
                do {
                    let callInfoData = try JSONSerialization.data(withJSONObject: callInfo, options: .prettyPrinted)
                    systemMessage.arg = callInfoData
                    systemMessage.isOwn = NSNumber(booleanLiteral: isIncoming)
                    systemMessage.conversation = conversation
                    conversation.lastMessage = systemMessage
                    conversation.lastUpdate = Date()
                }
                catch {
                    XCTFail(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: Ballot Messages
    
    func testGroupWithBallotMessages() async throws {
        // Configuration
        // There is more configuration in the loop below
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 20
        let choicesPerBallot = 2..<15
        let totalVotes = 0..<256
        
        // Load test data
        let testBundle = Bundle(for: DBLoadTests.self)

        guard let textsPath = testBundle.url(forResource: "test_ballot_titles", withExtension: "json") else {
            XCTFail("Cannot find file with test texts")
            return
        }
        let ballotTitles = try XCTUnwrap(JSONDecoder().decode([String].self, from: Data(contentsOf: textsPath)))
        
        guard let textsPath = testBundle.url(forResource: "test_ballot_options", withExtension: "json") else {
            XCTFail("Cannot find file with test texts")
            return
        }
        let ballotOptions = try XCTUnwrap(JSONDecoder().decode([String].self, from: Data(contentsOf: textsPath)))
        
        let filePath = try XCTUnwrap(testBundle.path(forResource: "test_ids", ofType: "txt"))
        
        // Prepare Group
        // Load test identities
        var fetchIdentities = ["ECHOECHO"]
        
        let ids = try XCTUnwrap(String(contentsOfFile: filePath, encoding: .utf8))
        for id in ids.components(separatedBy: .newlines) {
            if !id.isEmpty {
                fetchIdentities.append(id)
            }
        }
        
        var participants = createContacts(for: fetchIdentities.reversed())
        
        let entityManager = EntityManager()
        
        let myIdentityStoreMock = MyIdentityStoreMock()
        
        participants.append(myIdentityStoreMock.identity)
        
        // Create group
        let group = try await createGroup(
            named: "Ballot Messages (\(DateFormatter.accessibilityDateTime(Date())))",
            with: participants,
            entityManager: entityManager
        )
        let conversation = group.conversation
        
        for index in 0..<numberOfMessagesToAdd {
            let isIncoming = index % (alternateEveryXMessage * 2) >= alternateEveryXMessage
            let isClosed = index % 2 == 1
            let intermediateResults = index % 5 == 0
            let multipleChoice = index % 3 == 0
            
            entityManager.performAndWaitSave {
                // Setup ballot
                let baseBallot = entityManager.entityCreator.ballot()!
                baseBallot.id = BytesUtility.generateRandomBytes(length: ThreemaProtocol.ballotIDLength)
                baseBallot.createDate = Date()
                baseBallot.creatorID = isIncoming ? "ECHOECHO" : myIdentityStoreMock.identity
                baseBallot.conversation = conversation
                baseBallot.title = ballotTitles[index % ballotTitles.count]
                baseBallot.setIntermediate(intermediateResults)
                baseBallot.setMultipleChoice(multipleChoice)
                
                if isClosed {
                    baseBallot.setClosed()
                }
                
                var ballotChoices = [BallotChoice]()
                
                // Setup choices
                for choiceNo in 0..<Int.random(in: choicesPerBallot) {
                    let ballotChoice = entityManager.entityCreator.ballotChoice()!
                    ballotChoice.ballot = baseBallot
                    ballotChoice.createDate = Date()
                    ballotChoice.id = NSNumber(value: choiceNo)
                    ballotChoice.name = ballotOptions[choiceNo % ballotOptions.count]
                    ballotChoice.orderPosition = NSNumber(value: choiceNo)
                    
                    ballotChoices.append(ballotChoice)
                }
                
                // Setup votes
                // We don't post vote messages here to avoid cluttering up the chat
                let ballotManager = BallotManager(entityManager: entityManager)
                for participant in 0..<Int.random(in: totalVotes) {
                    let maxChoices = multipleChoice ? 1 : Int.random(in: choicesPerBallot)
                    for _ in 0..<maxChoices {
                        ballotManager.updateChoice(
                            ballotChoices[Int.random(in: 0..<ballotChoices.count)],
                            with: NSNumber(booleanLiteral: true),
                            for: participants[participant % participants.count]
                        )
                    }
                }
                
                // Get sender
                let sender = entityManager.entityFetcher
                    .contact(
                        for: isIncoming ? participants
                            .filter { $0 != myIdentityStoreMock.identity
                            }[Int.random(in: 0..<(participants.count - 1))] :
                            myIdentityStoreMock.identity
                    )
                
                // Always create open ballot message
                let ballotOpenMessage = entityManager.entityCreator.ballotMessage(for: conversation)!
                ballotOpenMessage.isOwn = NSNumber(value: !isIncoming)
                ballotOpenMessage.ballot = baseBallot
                ballotOpenMessage.sender = sender
                ballotOpenMessage.ballotState = NSNumber(value: kBallotStateOpen)
                
                // Only sometimes create ballot close message
                if isClosed {
                    let ballotCloseMessage = entityManager.entityCreator.ballotMessage(for: conversation)!
                    ballotCloseMessage.isOwn = NSNumber(value: !isIncoming)
                    ballotCloseMessage.ballot = baseBallot
                    ballotCloseMessage.sender = sender
                    ballotCloseMessage.ballotState = NSNumber(value: kBallotStateClosed)
                }
            }
        }
    }
    
    // MARK: File message helper
    
    private func add(
        senderItem: URLSenderItem,
        caption: String? = nil,
        showCaptions: Bool = true,
        to group: Group,
        _ times: Int,
        timesAndAlternateEvery alternateEveryXMessage: Int,
        entityManager: EntityManager
    ) throws {
        let testBundle = Bundle(for: DBLoadTests.self)

        let testCaptionsURL = try XCTUnwrap(testBundle.url(forResource: "test_texts", withExtension: "json"))
        let captions = try JSONDecoder().decode([String].self, from: Data(contentsOf: testCaptionsURL))
        
        _ = createContacts(for: ["ECHOECHO"])
        let senderContact = try XCTUnwrap(entityManager.entityFetcher.contact(for: "ECHOECHO"))
        
        for index in 0..<times {
            if showCaptions {
                // Add a caption if given or to every eighth message
                if let caption {
                    senderItem.caption = caption
                }
                else if index % 8 == 0 {
                    senderItem.caption = captions[(index / 8) % captions.count]
                }
                else {
                    senderItem.caption = nil
                }
            }
            
            var fileMessageCreationError: Error?
            
            entityManager.performAndWaitSave {
                do {
                    let fileMessageEntity = try entityManager.entityCreator.createFileMessageEntity(
                        for: senderItem,
                        in: group.conversation,
                        with: .public
                    )
                    
                    if index % (alternateEveryXMessage * 2) >= alternateEveryXMessage {
                        // incoming message
                        fileMessageEntity.isOwn = false
                        fileMessageEntity.sender = senderContact
                    }
                    else {
                        // outgoing message
                        fileMessageEntity.isOwn = true
                    }
                }
                catch {
                    fileMessageCreationError = error
                }
            }
            
            if let fileMessageCreationError {
                XCTFail(fileMessageCreationError.localizedDescription)
            }
        }
    }
    
    // MARK: Location messages

    func testGroupWithLocationMessages() async throws {
        let numberOfMessagesToAdd = 100
        let alternateEveryXMessage = 5
        
        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "Location Messages", with: [], entityManager: entityManager)

        // Fetch contact
        _ = _ = createContacts(for: ["ECHOECHO"])
        let senderContact = try XCTUnwrap(entityManager.entityFetcher.contact(for: "ECHOECHO"))
        
        // Load and add locations
        
        let testBundle = Bundle(for: DBLoadTests.self)
        let testLocationsURL = try XCTUnwrap(testBundle.url(forResource: "test_locations", withExtension: "json"))
        let locations = try JSONDecoder().decode([Location].self, from: Data(contentsOf: testLocationsURL))
    
        for index in 0..<numberOfMessagesToAdd {
            let location = locations[index % locations.count]
            
            entityManager.performAndWaitSave {
                let locationMessage = entityManager.entityCreator.locationMessage(for: group.conversation)!
                
                locationMessage.latitude = location.latitude as NSNumber
                locationMessage.longitude = location.longitude as NSNumber
                locationMessage.accuracy = location.accuracy as NSNumber
                locationMessage.poiName = location.name
                locationMessage.poiAddress = location.address
                
                if index % (alternateEveryXMessage * 2) >= alternateEveryXMessage {
                    // incoming message
                    locationMessage.isOwn = false
                    locationMessage.sender = senderContact
                }
                else {
                    // outgoing message
                    locationMessage.isOwn = true
                }
            }
        }
    }
    
    /// Used to parse  `test_locations.json`
    private struct Location: Codable {
        let name: String?
        let address: String?
        let latitude: Double
        let longitude: Double
        let accuracy: Double
    }
    
    // MARK: System messages
    
    func testGroupWithSystemMessages() async throws {
        let memberIDsToAddAndRemove = [
            "79PNJP93",
            "86C8TPSV",
            "89A6R535",
            "8K4PHKZ8",
            "938BYJZ2",
            "9DA769XW",
            "9UMM8RUX",
            "AMNR4PJH",
            "ANH9VK8J",
            "BR84ASE5",
            "BV9P56XX",
            "CHD7UH2B",
            "CPPDA7HM",
            "CT2AP9XA",
            "D2CJFSC2",
            "DSWMK3UZ",
            "EE365MVK",
        ]
        
        _ = createContacts(for: memberIDsToAddAndRemove)

        let entityManager = EntityManager()
        
        // Create group
        let group = try await createGroup(named: "System Messages", with: [], entityManager: entityManager)
        let groupManager: GroupManagerProtocol = GroupManager(
            entityManager: entityManager,
            taskManager: TaskManagerMock()
        )

        // Add system messages by doing different group updates
        
        try await groupManager.setName(group: group, name: "System Messages 1")

        _ = try await groupManager.createOrUpdate(
            for: group.groupIdentity,
            members: Set(memberIDsToAddAndRemove),
            systemMessageDate: Date()
        )

        _ = try await groupManager.createOrUpdate(
            for: group.groupIdentity,
            members: [],
            systemMessageDate: Date()
        )
    }
    
    // MARK: Example group
    
    /// An example "Hikers" group
    ///
    /// Generates a group chat with named members and a set of messages. This is useful for demos.
    func testExampleGroup() async throws {
        let groupMemberIDsAndNames = [
            "4PBBKVUS": "Emily Yeung",
            "86C8TPSV": "Peter Schreiner",
            "9UMM8RUX": "Robert Diaz",
            "78HFFYMF": "Lisa Goldman",
            "4TWXB3EP": "Hanna Schmidt",
        ]

        // Ensure all contacts exist
        _ = createContacts(for: Array(groupMemberIDsAndNames.keys))

        let entityManager = EntityManager()

        // Load all contacts and assign the names
        let members = try groupMemberIDsAndNames.map { id, name -> ContactEntity in
            let contact = try XCTUnwrap(entityManager.entityFetcher.contact(for: id))
            
            let names = name.components(separatedBy: .whitespaces)
            entityManager.performAndWaitSave {
                contact.firstName = names.first
                contact.lastName = names.last
            }
            
            return contact
        }
        
        let group = try await createGroup(
            named: "Hikers",
            with: Array(groupMemberIDsAndNames.keys),
            entityManager: entityManager
        )
        
        // Add messages
        
        addGroupTextMessage("Hello", sender: members[0], in: group, entityManager: entityManager)
        addGroupTextMessage(
            "Who's up for a hike next weekend?",
            sender: members[0],
            in: group,
            entityManager: entityManager
        )
        
        addGroupTextMessage("I'm in!", sender: members[1], in: group, entityManager: entityManager)
        addGroupTextMessage("Let's do it. 🥾", sender: members[2], in: group, entityManager: entityManager)
        
        let testBundle = Bundle(for: DBLoadTests.self)
        let testImageURL = try XCTUnwrap(testBundle.url(forResource: "Bild-1-0", withExtension: "jpg"))
        let imageSenderItem = try XCTUnwrap(ImageURLSenderItemCreator().senderItem(from: testImageURL))
        try add(
            senderItem: imageSenderItem,
            caption: "I can't, but last weekend was amazing.",
            to: group,
            1,
            timesAndAlternateEvery: 1,
            entityManager: entityManager
        )
        
        addGroupTextMessage(
            "I need to check how my schedule looks like. When do you plan to go? Only one day or both days?",
            sender: members[3],
            in: group,
            entityManager: entityManager
        )
        
        let testFileURL = try XCTUnwrap(testBundle.url(forResource: "Hike Churfirsten", withExtension: "gpx"))
        let fileSenderItem = try XCTUnwrap(URLSenderItem(
            url: testFileURL,
            type: UTType.pdf.identifier,
            renderType: 0,
            sendAsFile: false
        ))
        fileSenderItem.caption = "I would suggest this one day hike. What do you think?"
        
        var fileMessageCreationError: Error?
        
        entityManager.performAndWaitSave {
            do {
                let fileMessageEntity = try entityManager.entityCreator.createFileMessageEntity(
                    for: fileSenderItem,
                    in: group.conversation,
                    with: .public
                )
                
                fileMessageEntity.isOwn = false
                fileMessageEntity.sender = members[0]
            }
            catch {
                fileMessageCreationError = error
            }
        }
        
        if let fileMessageCreationError {
            XCTFail(fileMessageCreationError.localizedDescription)
        }
    }
    
    // TODO: Helper
    
    private func createGroup(
        named: String,
        with members: [String],
        entityManager: EntityManager
    ) async throws -> Group {
        let groupManager: GroupManagerProtocol = GroupManager(
            entityManager: entityManager,
            taskManager: TaskManagerMock()
        )

        let groupIdentity = try GroupIdentity(
            id: XCTUnwrap(BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)),
            creator: ThreemaIdentity(XCTUnwrap(MyIdentityStore.shared().identity))
        )

        // Creation
        
        let (group, _) = try await groupManager.createOrUpdate(
            for: groupIdentity,
            members: Set(members),
            systemMessageDate: Date()
        )

        // Set name
        try await groupManager.setName(group: group, name: named)

        return group
    }
    
    // Workaround to add contacts as `addContacts(for:entityManager:)` doesn't seem to work
    private func createContacts(for ids: [String]) -> [String] {
        var createdContacts = [String]()
        var contactStoreExpectations = [XCTestExpectation]()
        for id in ids {
            print("Checking \(id)")
            let contactStoreExpectation = expectation(description: "Add contact to contact store")
            ContactStore.shared().addContact(
                with: id,
                verificationLevel: Int32(kVerificationLevelUnverified)
            ) { _, _ in
                createdContacts.append(id)
                contactStoreExpectation.fulfill()
            } onError: { error in
                print("Failed to create contact from \(id) \(error.localizedDescription)")
                contactStoreExpectation.fulfill()
            }
            contactStoreExpectations.append(contactStoreExpectation)
        }
        wait(for: contactStoreExpectations, timeout: 30)
        
        return createdContacts
    }
    
    // the function below is a copy from entityManager.conversation,
    // but it allows creating a (potentially) duplicate conversation for contactEntity.identity
    private func getOrCreateDuplicateOneToOneConversation(
        forContact contactEntity: ContactEntity,
        entityManager: EntityManager
    ) -> Conversation? {
        let conversation = entityManager.entityFetcher.conversation(for: contactEntity)
        
        if conversation == nil,
           let conversation = entityManager.entityCreator.conversation(true) {
            conversation.contact = contactEntity
            
            if contactEntity.showOtherThreemaTypeIcon {
                // Add work info as first message
                let systemMessage = entityManager.entityCreator.systemMessage(for: conversation)
                systemMessage?.type = NSNumber(value: kSystemMessageContactOtherAppInfo)
                systemMessage?.remoteSentDate = Date()
            }
            
            print("Created 1:1 conversation for \(contactEntity.identity)")
            return conversation
        }
        else {
            print("Found exising 1:1 conversation for \(contactEntity.identity)")
        }
        
        // Check if the contact still needs to be hidden
        if contactEntity.isContactHidden {
            contactEntity.isContactHidden = false
            
            let mediatorSyncableContacts = MediatorSyncableContacts()
            mediatorSyncableContacts.updateAcquaintanceLevel(
                identity: contactEntity.identity,
                value: NSNumber(integerLiteral: ContactAcquaintanceLevel.direct.rawValue)
            )
            mediatorSyncableContacts.syncAsync()
        }
        
        return conversation
    }

    /// create a text message in the one to one conversation with the provided contact
    ///
    /// isOwn: true if I sent the message, false of the provided contact sent the message
    private func addOneToOneTextMessage(
        _ text: String,
        quoteID: Data? = nil,
        isOwn: Bool,
        contact: ContactEntity,
        entityManager: EntityManager
    ) {
        entityManager.performAndWaitSave {
            let conversation = self.getOrCreateDuplicateOneToOneConversation(
                forContact: contact,
                entityManager: entityManager
            )
            let message = entityManager.entityCreator.textMessage(for: conversation, setLastUpdate: true)!
            
            message.text = text
            
            message.date = Date()
            message.sent = true
            message.remoteSentDate = Date()
            message.delivered = true
            message.deliveryDate = Date()
            
            message.quotedMessageID = quoteID
            
            if isOwn {
                message.isOwn = true
            }
            else {
                message.isOwn = false
            }
        }
    }

    @discardableResult private func addGroupTextMessage(
        _ text: String,
        quoteID: Data? = nil,
        sender: ContactEntity? = nil,
        in group: Group,
        entityManager: EntityManager
    ) -> TextMessage {
        entityManager.performAndWaitSave {
            let message = entityManager.entityCreator.textMessage(
                for: group.conversation,
                setLastUpdate: true
            )! as TextMessage
            
            message.text = text

            message.date = Date()
            message.sent = true
            message.remoteSentDate = Date()
            message.delivered = true
            message.deliveryDate = Date()
            
            message.quotedMessageID = quoteID
            
            if let sender {
                message.isOwn = false
                message.sender = sender
            }
            else {
                message.isOwn = true
            }
            
            return message
        }
    }
    
    // MARK: - Migration test
    
    func testAddTextMessagesForMigration() throws {
        let numberOfMessages = 200_000
        
        let testBundle = Bundle(for: DBLoadTests.self)
        let textsPath = try XCTUnwrap(testBundle.url(forResource: "test_texts", withExtension: "json"))
        let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: textsPath))
        
        var conversation: Conversation?
        
        _ = createContacts(for: ["ECHOECHO"])
        
        let entityManager = EntityManager()
        entityManager.performAndWaitSave {
            if let contact = entityManager.entityFetcher.contact(for: "ECHOECHO") {
                conversation = entityManager.conversation(forContact: contact, createIfNotExisting: true)
            }
        }
        
        entityManager.performAndWaitSave {
            for index in 0..<(numberOfMessages / 2) {
                let calendar = Calendar.current
                let date = calendar.date(byAdding: .hour, value: -(index * 8), to: Date())
                let message = entityManager.entityCreator.textMessage(for: conversation, setLastUpdate: true)!
                message.text = "\(index) - \(texts[index % texts.count])"
                message.isOwn = false
                message.sender = conversation?.contact

                message.sent = true
                message.remoteSentDate = date
                message.date = Date()
                message.delivered = true
                message.deliveryDate = Date()
                message.read = true
                message.readDate = Date()
                
                print("Batch 1: \(index)/\(numberOfMessages / 2)")
            }
        }
        
        entityManager.performAndWaitSave {
            for index in 0..<(numberOfMessages / 2) {
                let calendar = Calendar.current
                let date = calendar.date(byAdding: .hour, value: -(index * 8), to: Date())!
                let message = entityManager.entityCreator.textMessage(for: conversation, setLastUpdate: true)!
                message.text = "\(index) - \(texts[index % texts.count])"
                message.isOwn = true

                message.date = date
                message.sent = true
                message.remoteSentDate = calendar.date(byAdding: .hour, value: +1, to: date)!
                message.delivered = true
                message.deliveryDate = calendar.date(byAdding: .hour, value: +2, to: date)!
                
                print("Batch 2: \(index)/\(numberOfMessages / 2)")
            }
        }
    }
}
