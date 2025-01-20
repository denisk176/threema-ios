//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2019-2025 Threema GmbH
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

#import <XCTest/XCTest.h>
#import "ThreemaUtilityObjC.h"

@interface UtilsTests : XCTestCase

@end

@implementation UtilsTests

- (void)testEmailValidation {
    XCTAssertFalse([ThreemaUtilityObjC isValidEmail:nil]);
    XCTAssertFalse([ThreemaUtilityObjC isValidEmail:@""]);
    XCTAssertFalse([ThreemaUtilityObjC isValidEmail:@"asfasf"]);
    XCTAssertFalse([ThreemaUtilityObjC isValidEmail:@"a@a"]);
    XCTAssertFalse([ThreemaUtilityObjC isValidEmail:@"@"]);
    XCTAssertFalse([ThreemaUtilityObjC isValidEmail:@"a@a@a"]);

    XCTAssertTrue([ThreemaUtilityObjC isValidEmail:@"test@gaga.com"]);
    XCTAssertTrue([ThreemaUtilityObjC isValidEmail:@"a.b@xx.com"]);
}


@end
