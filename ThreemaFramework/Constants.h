//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2014-2025 Threema GmbH
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

#import <Contacts/Contacts.h>

#ifndef Threema_Constants_h
#define Threema_Constants_h

#pragma mark - iOS version makros

#define SYSTEM_VERSION_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

#define SYSTEM_IS_IPAD ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)

#define SYSTEM_IS_IPHONE_X (([[UIDevice currentDevice]userInterfaceIdiom] == UIUserInterfaceIdiomPhone) && ((int)[[UIScreen mainScreen] nativeBounds].size.height) == 2436)

#define THREEMA_FRAMEWORK_IDENTIFIER @"ch.threema.ThreemaFramework"

#define SHARE_FILE_PREFIX @"share"

#define THREEMA_ID_SHARE_LINK @"https://threema.id/"

#define MEDIA_EXTENSION_AUDIO @"m4a"
#define MEDIA_EXTENSION_IMAGE @"jpg"
#define MEDIA_EXTENSION_VIDEO @"mp4"
#define MEDIA_EXTENSION_GIF @"gif"

#pragma mark - notifications

#define kNotificationShowConversation @"ThreemaShowConversation"
#define kNotificationDeletedConversation @"ThreemaDeletedConversation"

#define kNotificationShowContact @"ThreemaShowContact"
#define kNotificationDeletedContact @"ThreemaDeletedContact"
#define kNotificationBlockedContact @"ThreemaBlockedContact"

#define kNotificationBatchDeletedAllConversationMessages @"ThreemaBatchDeletedAllConversationMessages"
#define kNotificationBatchDeletedOldMessages @"ThreemaBatchDeletedOldMessages"

#define kNotificationShowGroup @"ThreemaShowGroup"
#define kNotificationShowDistributionList @"ThreemaShowDistributionList"
#define kNotificationShowSafeSetup @"ThreemaShowSafeSetup"
#define kShowNotificationSettings @"ThreemaShowNotificationSettings"

#define kNotificationMessagesCountChanged @"ThreemaUnreadMessagesCountChanged"

#define kNotificationCreatedIdentity @"ThreemaCreatedIdentity"
#define kNotificationDestroyedIdentity @"ThreemaDestroyedIdentity"

#define kNotificationLicenseMissing @"ThreemaLicenseMissing"
#define kNotificationLicenseCheckSuccess @"ThreemaLicenseCeckSuccess"

#define kNotificationWallpaperChanged @"ThreemaWallpaperChanged"
#define kNotificationColorThemeChanged @"ThreemaColorThemeChanged"
#define kNotificationShowProfilePictureChanged @"ShowProfilePictureChanged"
#define kNotificationIncomingProfileSynchronization @"IncomingProfileSynchronization"
#define kNotificationIncomingSettingsSynchronization @"IncomingSettingsSynchronization"
#define kNotificationSettingStoreSynchronization @"NotificationSettingStoreSynchronization"
#define kNotificationNavigationBarColorShouldChange @"NavigationBarColorShouldChange"
#define kNotificationNavigationItemPromptShouldChange @"NavigationItemPromptShouldChange"
#define kNotificationMultiDeviceWizardDidUpdate @"MultiDeviceWizardDidUpdate"

#define kNotificationUpdateDraftForCell @"ThreemaUpdateDraftForCell"

#define kPushNotificationDeviceToken @"PushNotificationDeviceToken"
#define kVoIPPushNotificationDeviceToken @"VoIPPushNotificationDeviceToken"
#define kPushNotificationEncryptionKey @"PushNotificationEncryptionKey"

#define kNotificationServerMessage @"ThreemaServerMessage"
#define kNotificationQueueSendComplete @"ThreemaQueueSendComplete"
#define kNotificationErrorConnectionFailed @"ThreemaErrorConnectionFailed"
#define kNotificationErrorPublicKeyMismatch @"ThreemaErrorPublicKeyMismatch"
#define kNotificationErrorRogueDevice @"ThreemaErrorRogueDevice"

#define kNotificationDBRefreshedDirtyObject @"ThreemaDBRefreshedDirtyObject"
#define kNotificationDBRefreshedDirtyObjects @"ThreemaDBRefreshedDirtyObjects"

#define kNotificationRefreshWorkContactTableView @"RefreshWorkContactTableView"
#define kNotificationAddressbookSyncronized @"AddressbookSyncronized"
#define kNotificationRefreshContactSortIndices @"RefreshContactSortIndices"
#define kNotificationChangedHidePrivateChat @"ChangedHidePrivateChat"
#define kNotificationChangedPushSetting @"ChangedPushSetting"

#define kNotificationLoadWorkContacts @"LoadWorkContacts"

#define kVoIPCallStartRinging @"ThreemaVoIPCallStartRinging"
#define kVoIPCallStatusChanged @"ThreemaVoIPCallStatusChanged"
#define kVoIPCallIncomingCall @"ThreemaVoIPCallIncomingCall"
#define kVoIPCallStartDebugMode @"ThreemaVoIPCallStartDebugMode"

#define kAppClosedByUserBackgroundTask @"ThreemaAppClosedByUserBackgroundTask"
#define kAppVoIPBackgroundTask @"ThreemaVoIPBackgroundTask"
#define kAppVoIPIncomCallBackgroundTask @"ThreemaVoIPIncomCallBackgroundTask"
#define kAppWCBackgroundTask @"ThreemaWCBackgroundTask"
#define kAppSendingBackgroundTask @"ThreemaSendingBackgroundTask"
#define kAppAckBackgroundTask @"ThreemaAckBackgroundTask"
#define kAppPushReplyBackgroundTask @"ThreemaPushReplyBackgroundTask"
#define kAppCoreDataSaveBackgroundTask @"ThreemaCoreDataSaveBackgroundTask"
#define kAppCoreDataProcessMessageBackgroundTask @"ThreemaCoreDataProcessMessageTask"
#define kSafeBackgroundTask @"ThreemaSafeBackgroundTask"

#define kMediaPreviewPauseVideo @"MediaPreviewPauseVideo"

#define kAppClosedByUserBackgroundTaskTime 5
#define kAppPushBackgroundTaskTime 40
#define kAppWCBackgroundTaskTime 90
#define kAppPushReplyBackgroundTaskTime 30
#define kAppVoIPBackgroundTaskTime 5
#define kAppAckBackgroundTaskTime 2
#define kAppCoreDataSaveBackgroundTaskTime 15
#define kAppSendingBackgroundTaskTime 170
#define kAppVoIPIncomCallBackgroundTaskTime 80
#define kAppCoreDataProcessMessageBackgroundTaskTime 10

static NSString * const kNotificationProfilePictureChanged = @"ProfilePictureChanged";
static NSString * const kNotificationProfileNicknameChanged = @"ProfileNicknameChanged";

static NSString * const kNotificationChatMessageAck = @"ChatMessageAck";
static NSString * const kNotificationMediatorMessageAck = @"MediatorMessageAck";


#pragma mark - notification info keys

#define kKeyContact @"contact"
#define kKeyContactIdentity @"contactIdentity"
#define kKeyGroup @"group"
#define kKeyDistributionList @"distributionList"
#define kKeyConversation @"conversation"
#define kKeyForceCompose @"forceCompose"
#define kKeyText @"text"
#define kKeyImage @"image"
#define kKeyMessage @"message"
#define kKeyUnread @"unread"
#define kKeyTitle @"title"

#define kKeyObjectID @"objectID"
#define kKeyObjectIDs @"objectIDs"

// Also update Constants.cnContactKeys
#define kCNContactKeys @[CNContactFamilyNameKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactImageDataKey, CNContactImageDataAvailableKey, CNContactThumbnailImageDataKey, [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName]]

#pragma mark - ThreemaWeb

#define kWebPageSize 50

#pragma mark - ThreemaSAFE

static NSString * const kSafeBackupTrigger = @"ThreemaSafeBackupTrigger";
static NSString * const kSafeBackupUIRefresh = @"ThreemaSafeBackupUIRefresh";
static NSString * const kSafeBackupPasswordCheck = @"ThreemaSafeBackupPasswordCheck";
static NSString * const kRevocationPasswordUIRefresh = @"ThreemaRevocationPasswordUIRefresh";
static NSString * const kLinkedPhoneUIRefresh = @"ThreemaLinkedPhoneUIRefresh";
static NSString * const kLinkedEmailUIRefresh = @"ThreemaLinkedEmailUIRefresh";

#define kSafeSetupUI @"ThreemaSafeSetupUI"

#pragma mark - Threema Calls
static NSString * const kThreemaVideoCallsQualitySettingChanged = @"ThreemaVideoCallsQualitySettingChanged";


#pragma mark - UserDefault Keys
#define kLastPushOverrideSendDate @"LastPushOverrideSendDate"
#define kShowedTestFlightFeedbackView @"ShowedTestFlightFeedbackView"
#define kWallpaperKey @"Wallpapers"
#define kShowed10YearsAnniversaryView @"Showed10YearsAnniversaryView"
#define kShowedNotificationTypeSelectionView @"showedNotificationTypeSelectionView"
#define kAppSetupStateKey @"AppSetupState"

#pragma mark - Push notification keys

typedef NSString *ThreemaPushNotificationDictionary NS_STRING_ENUM;

extern ThreemaPushNotificationDictionary const ThreemaPushNotificationDictionaryKey;

extern ThreemaPushNotificationDictionary const ThreemaPushNotificationDictionaryCommandKey;
extern ThreemaPushNotificationDictionary const ThreemaPushNotificationDictionaryFromKey;
extern ThreemaPushNotificationDictionary const ThreemaPushNotificationDictionaryNicknameKey;
extern ThreemaPushNotificationDictionary const ThreemaPushNotificationDictionaryMessageIDKey;
extern ThreemaPushNotificationDictionary const ThreemaPushNotificationDictionaryVOIPKey;

typedef NSString *ThreemaPushNotificationDictionaryBool NS_STRING_ENUM NS_SWIFT_NAME(ThreemaPushNotificationDictionary.Bool);
extern ThreemaPushNotificationDictionaryBool const ThreemaPushNotificationDictionaryBoolTrue;
extern ThreemaPushNotificationDictionaryBool const ThreemaPushNotificationDictionaryBoolFalse;

typedef NSString *ThreemaPushNotificationDictionaryCommand NS_STRING_ENUM NS_SWIFT_NAME(ThreemaPushNotificationDictionary.Command);
extern ThreemaPushNotificationDictionaryCommand const ThreemaPushNotificationDictionaryCommandNewMessage;
extern ThreemaPushNotificationDictionaryCommand const ThreemaPushNotificationDictionaryCommandNewGroupMessage;

#pragma mark - Max lengths

static NSInteger const kMaxFirstOrLastNameLength = 256;
static NSInteger const kMaxGroupNameLength = 256;
static NSInteger const kMaxNicknameLength = 32;

#pragma mark - Beta Feedback ID

static NSString * const kBetaFeedbackIdentity = @"*BETAFBK";

#pragma mark - System Message Keys
enum {
    kSystemMessageRenameGroup = 1, // The admin has renamed the group
    kSystemMessageGroupMemberLeave = 2, // Another member has left the group
    kSystemMessageGroupMemberAdd = 3, // The admin has added a member to the group
    kSystemMessageGroupMemberForcedLeave = 4, // Another member was removed from the group
    kSystemMessageGroupSelfAdded = 5, // I was added to the group
    kSystemMessageGroupSelfRemoved = 6, // I was removed from the group
    kSystemMessageGroupSelfLeft = 16, // I have left the group
    kSystemMessageGroupCreatorLeft = 19, // Creator has left the group
    kSystemMessageStartNoteGroupInfo = 17, // This is a note group without members
    kSystemMessageEndNoteGroupInfo = 18, // This is no note group anymore
    kSystemMessageVote = 20,
    kSystemMessageVoteUpdated = 30,
    kSystemMessageCallMissed = 7,
    kSystemMessageCallRejected = 8,
    kSystemMessageCallRejectedBusy = 9,
    kSystemMessageCallRejectedTimeout = 10,
    kSystemMessageCallEnded = 11,
    kSystemMessageCallRejectedDisabled = 12,
    kSystemMessageCallRejectedUnknown = 13,
    kSystemMessageContactOtherAppInfo = 14,
    kSystemMessageCallRejectedOffHours = 15,
    kSystemMessageFsMessageWithoutForwardSecurity = 21,
    kSystemMessageFsSessionEstablished = 22,
    kSystemMessageFsSessionEstablishedRcvd = 23, // As of version 1.1. this status is not created anymore
    kSystemMessageFsMessagesSkipped = 24,
    kSystemMessageFsSessionReset = 25,
    kSystemMessageFsOutOfOrder = 26,
    kSystemMessageFsEnabledOutgoing = 27,
    kSystemMessageFsDisabledOutgoing = 28,
    kSystemMessageFsNotSupportedAnymore = 29,
    kSystemMessageUnsupportedType = 31,
    kSystemMessageGroupProfilePictureChanged = 32,
    kSystemMessageGroupCallStartedBy = 33,
    kSystemMessageGroupCallStarted = 34,
    kSystemMessageGroupCallEnded = 35,
    kFsDebugMessage = 36,
    kSystemMessageFsIllegalSessionState = 37,
};
#endif
