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

#import <UIKit/UIKit.h>
#import "SZTextView.h"
#import "Old_ThemedViewController.h"

@class BallotEntity, BallotChoiceEntity;

@interface BallotCreateViewController : Old_ThemedViewController

@property (weak, nonatomic) IBOutlet UIBarButtonItem *cancelButton;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *sendButton;

@property (weak, nonatomic) IBOutlet UIButton *addButton;

@property (weak, nonatomic) IBOutlet UIButton *optionsButton;

@property (weak, nonatomic) IBOutlet SZTextView *titleTextView;

@property (weak, nonatomic) IBOutlet UIView *headerView;
@property (weak, nonatomic) IBOutlet UIView *buttonView;
@property (weak, nonatomic) IBOutlet UIView *hairlineTop;

@property (weak, nonatomic) IBOutlet UITableView *choiceTableView;

+ (instancetype) ballotCreateViewControllerForConversation:(ConversationEntity *)conversation;

+ (instancetype) ballotCreateViewControllerForBallot:(BallotEntity *)ballot;

@end
