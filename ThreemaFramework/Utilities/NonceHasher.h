//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2020-2025 Threema GmbH
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

#import <Foundation/Foundation.h>
#import "MyIdentityStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface NonceHasher : NSObject

/// Hash nonce
/// - Parameters:
///   - nonce: Nonce to hash
///   - myIdentityStore: Information about our identity
/// - Returns: Hashed nonce if `myIdentityStore` has an `identity`, `nil` otherwise
+ (nullable NSData *)hashedNonce:(NSData *)nonce myIdentityStore:(id<MyIdentityStoreProtocol>)myIdentityStore;

@end

NS_ASSUME_NONNULL_END
