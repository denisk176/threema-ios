//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2012-2023 Threema GmbH
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

#ifndef Threema_ProtocolDefines_h
#define Threema_ProtocolDefines_h

#define kCookieLen 16
#define kIdentityLen 8
#define kLoginAckReservedLen 16
#define kMessageIdLen 8
#define kNonceLen 24
#define kClientVersionLen 32
#define kPushFromNameLen 32
#define kBlobIdLen 16
#define kBlobKeyLen 32
#define kGroupIdLen 8
#define kGroupCreatorLen 8
#define kBallotIdLen 8
#define kDeviceGroupKeyLen 32
#define kDeviceIdLen 8
#define kExtensionTypeLength = 1
#define kExtensionLengthLength = 2
#define kExtensionDataMaxLength = 256
#define kVouchLen 32
#define kEphemeralKeyHashLen 32
#define kGCKLen 32
#define kConnectTimeout 15
#define kReadTimeout 20
#define kWriteTimeout 20
#define kDisconnectTimeout 3
#define kReconnectBaseInterval 2
#define kReconnectMaxInterval 10
#define kEchoRequestInterval 60
#define kEchoRequestMDInterval 15
#define kEchoRequestTimeout 10
#define kErrorDisplayInterval 30
#define kBlobLoadTimeout 180
#define kBlobUploadTimeout 120
#define kConnectionIdleTimeout 120 // min 30, max 600
#define kConnectionIdleMDTimeout 30 // min 30, max 600

#define kMaxMessageLen 7000 // text message size limit (bytes, not characters!); must comfortably fit in maximum packet length (including 360 bytes overhead and padding)
#define kMaxCaptionLen 1000
#define kMaxPktLen 8192
#define kMinMessagePaddedLen 32

static NSInteger const kMaxFileSize = 100*1024*1024;
static NSInteger const kWebClientAvatarSize = 48;
static Float32  const kWebClientAvatarQuality = 0.6;
static NSInteger const kWebClientAvatarHiResSize = 512;
static Float32  const kWebClientAvatarHiResQuality = 0.75;
static NSInteger const kWebClientMediaPreviewSize = 50;
static NSInteger const kWebClientMediaThumbnailSize = 350;
static Float32 const kWebClientMediaQuality = 0.6;

#define kMaxVideoDurationLowMinutes 15
#define kMaxVideoDurationHighMinutes 3
#define kMaxVideoSizeLow 480
#define kMaxVideoSizeHigh 848
#define kVideoBitrateLow 384000
#define kVideoBitrateMedium 1500000
#define kVideoBitrateHigh 2000000
#define kAudioBitrateLow 32000
#define kAudioBitrateMedium 64000
#define kAudioBitrateHigh 128000
#define kAudioChannelsLow 1
#define kAudioChannelsHigh 2

#define kGroupPeriodicSyncInterval 7*86400
#define kGroupSyncRequestInterval 1*86400

#define MSGTYPE_TEXT 0x01
#define MSGTYPE_IMAGE 0x02
#define MSGTYPE_LOCATION 0x10
#define MSGTYPE_VIDEO 0x13
#define MSGTYPE_AUDIO 0x14
#define MSGTYPE_BALLOT_CREATE 0x15
#define MSGTYPE_BALLOT_VOTE 0x16
#define MSGTYPE_FILE 0x17
#define MSGTYPE_CONTACT_SET_PHOTO 0x18
#define MSGTYPE_CONTACT_DELETE_PHOTO 0x19
#define MSGTYPE_CONTACT_REQUEST_PHOTO 0x1a
#define MSGTYPE_GROUP_TEXT 0x41
#define MSGTYPE_GROUP_LOCATION 0x42
#define MSGTYPE_GROUP_IMAGE 0x43
#define MSGTYPE_GROUP_VIDEO 0x44
#define MSGTYPE_GROUP_AUDIO 0x45
#define MSGTYPE_GROUP_FILE 0x46
#define MSGTYPE_GROUP_CREATE 0x4a
#define MSGTYPE_GROUP_RENAME 0x4b
#define MSGTYPE_GROUP_LEAVE 0x4c
#define MSGTYPE_GROUP_SET_PHOTO 0x50
#define MSGTYPE_GROUP_REQUEST_SYNC 0x51
#define MSGTYPE_GROUP_BALLOT_CREATE 0x52
#define MSGTYPE_GROUP_BALLOT_VOTE 0x53
#define MSGTYPE_GROUP_DELETE_PHOTO 0x54
#define MSGTYPE_VOIP_CALL_OFFER 0x60
#define MSGTYPE_VOIP_CALL_ANSWER 0x61
#define MSGTYPE_VOIP_CALL_ICECANDIDATE 0x62
#define MSGTYPE_VOIP_CALL_HANGUP 0x63
#define MSGTYPE_VOIP_CALL_RINGING 0x64
#define MSGTYPE_DELIVERY_RECEIPT 0x80
#define MSGTYPE_GROUP_DELIVERY_RECEIPT 0x81
#define MSGTYPE_TYPING_INDICATOR 0x90
#define MSGTYPE_EDIT 0x91
#define MSGTYPE_DELETE 0x92
#define MSGTYPE_GROUP_EDIT 0x93
#define MSGTYPE_GROUP_DELETE 0x94
#define MSGTYPE_FORWARD_SECURITY 0xa0
#define MSGTYPE_AUTH_TOKEN 0xff
#define MSGTYPE_GROUP_CALL_START 0x4f
#define MSGTYPE_EMPTY 0xfc

#define MESSAGE_FLAG_SEND_PUSH 0x01
#define MESSAGE_FLAG_DONT_QUEUE 0x02
#define MESSAGE_FLAG_DONT_ACK 0x04
#define MESSAGE_FLAG_GROUP 0x10
#define MESSAGE_FLAG_IMMEDIATE_DELIVERY 0x20
// Note: This flag will only be set from server
#define MESSAGE_FLAG_NO_DELIVERY_RECEIPT 0x80

#define DELIVERYRECEIPT_MSGRECEIVED 0x01
#define DELIVERYRECEIPT_MSGREAD 0x02
#define DELIVERYRECEIPT_MSGUSERACK 0x03
#define DELIVERYRECEIPT_MSGUSERDECLINE 0x04
#define DELIVERYRECEIPT_MSGCONSUMED 0x05

#define PLTYPE_ECHO_REQUEST 0x00
#define PLTYPE_ECHO_RESPONSE 0x80
#define PLTYPE_OUTGOING_MESSAGE 0x01
#define PLTYPE_OUTGOING_MESSAGE_ACK 0x81
#define PLTYPE_INCOMING_MESSAGE 0x02
#define PLTYPE_INCOMING_MESSAGE_ACK 0x82
#define PLTYPE_UNBLOCK_INCOMING_MESSAGES 0x03
#define PLTYPE_PUSH_NOTIFICATION_TOKEN 0x20
#define PLTYPE_VOIP_PUSH_NOTIFICATION_TOKEN 0x24
#define PLTYPE_SET_CONNECTION_IDLE_TIMEOUT 0x30
#define PLTYPE_QUEUE_SEND_COMPLETE 0xd0
#define PLTYPE_DEVICE_COOKIE_CHANGE_INDICATION 0xd2
#define PLTYPE_CLEAR_DEVICE_COOKIE_CHANGE_INDICATION 0xd3
#define PLTYPE_ERROR 0xe0
#define PLTYPE_ALERT 0xe1

#define PUSHTOKEN_TYPE_NONE				0x00
#define PUSHTOKEN_TYPE_APPLE_PROD		0x01
#define PUSHTOKEN_TYPE_APPLE_SANDBOX	0x02
#define PUSHTOKEN_TYPE_APPLE_PROD_MC    0x05
#define PUSHTOKEN_TYPE_APPLE_SANDBOX_MC 0x06

#define FEATURE_MASK_AUDIO_MSG          0x01
#define FEATURE_MASK_GROUP_CHAT         0x02
#define FEATURE_MASK_BALLOT             0x04
#define FEATURE_MASK_FILE_TRANSFER      0x08
#define FEATURE_MASK_VOIP               0x10
#define FEATURE_MASK_VOIP_VIDEO         0x20
#define FEATURE_MASK_FORWARD_SECURITY   0x40
#define FEATURE_MASK_EDIT_MESSAGE       0x100
#define FEATURE_MASK_DELETE_MESSAGE     0x200

#define PUSHFILTER_TYPE_NONE            0
#define PUSHFILTER_TYPE_ALLOW_LISTED	1
#define PUSHFILTER_TYPE_BLOCK_LISTED	2

#define kJPEGCompressionQualityLow 0.8
#define kJPEGCompressionQualityHigh 0.81

#define kNSETimeout 25.0


static Float64 const kShareExtensionMaxImagePreviewSize = 15*1024*1024;
static Float64 const kShareExtensionMaxFileShareSize = 45*1024*1024;
static Float64 const kShareExtensionMaxImageShareSize = 30*1024*1024;

static unsigned char kNonce_1[] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01};
static unsigned char kNonce_2[] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02};

#pragma pack(push, 1)
#pragma pack(1)

struct plError {
    uint8_t reconnect_allowed;
    char err_message[];
};

struct plMessage {
    char from_identity[kIdentityLen];
    char to_identity[kIdentityLen];
    char message_id[kMessageIdLen];
    uint32_t date;
    uint8_t flags;
    uint8_t reserved;
    uint16_t metadata_len;
    char push_from_name[kPushFromNameLen];
    char metadata_nonce_box[];
};

struct plMessageAck {
    char from_identity[kIdentityLen];
    char message_id[kMessageIdLen];
};

struct plOutgoingMessageAck {
    char to_identity[kIdentityLen];
    char message_id[kMessageIdLen];
};

typedef NS_ENUM(NSUInteger, ForwardSecurityMode) {
    /// No FS applied
    ///
    /// Incoming: Message received without FS
    ///
    /// Outgoing:
    ///  - 1:1: Not sent or sent without FS
    ///  - Group: Not sent. Otherwise this should be set to any of the `.outgoingGroupXY` cases.
    kForwardSecurityModeNone = 0,
    
    /// Sent or received with 2DH
    ///
    /// This can only apply to 1:1 messages
    kForwardSecurityModeTwoDH = 1,
    
    /// Sent or received with 4DH
    ///
    /// This can apply to 1:1 or _incoming_ group messages
    kForwardSecurityModeFourDH = 2,
    
    /// Sent group message with no FS
    ///
    /// None of the receivers got the message with FS (i.e. none has a FS >= 1.2 session with this contact).
    /// This can only apply to outgoing group messages.
    kForwardSecurityModeOutgoingGroupNone = 3,
    
    /// Sent group message partially with FS
    ///
    /// Some of the receivers got the message with FS (i.e. some have a FS >= 1.2 session with this contact).
    /// This can only apply to outgoing group messages.
    kForwardSecurityModeOutgoingGroupPartial = 4,
    
    /// Sent group message fully with FS
    ///
    /// All of the receivers got the message with FS (i.e. all have a FS >= 1.2 session with this contact).
    /// This can only apply to outgoing group messages.
    kForwardSecurityModeOutgoingGroupFull = 5
};

typedef NS_ENUM(NSUInteger, ForwardSecurityState) {
    kForwardSecurityStateOff = 0,
    kForwardSecurityStateOn = 1
};

#pragma pack(pop)

#endif
