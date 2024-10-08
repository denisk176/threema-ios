//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2014-2024 Threema GmbH
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

#import "BallotCreateViewController.h"
#import "BallotCreateTableCell.h"
#import "BallotChoice.h"
#import "Ballot.h"
#import "AppDelegate.h"
#import "NaClCrypto.h"
#import "ProtocolDefines.h"
#import "MyIdentityStore.h"
#import "RectUtil.h"
#import "BallotCreateDetailViewController.h"
#import "ContactStore.h"
#import "AppGroup.h"
#import "BundleUtil.h"
#import "ThreemaFramework.h"
#import <ThreemaFramework/ThreemaFramework-Swift.h>

#define MIN_NUMBER_CHARACTERS 0
#define MIN_NUMBER_CHOICES 2
#define BALLOT_CREATE_TABLE_CELL_ID @"BallotCreateTableCellId"

// note: the new ballot object is created on a temorary NSManagedObjectContext, on save it is moved to the main context and saved there
// - the conversation object might get updated while editing the ballot
// - if using the main context a unwanted save may occur while the ballot is in in invalid state

@interface BallotCreateViewController ()  <UITableViewDelegate, UITableViewDataSource, BallotCreateTableCellDelegate>

@property NSMutableArray *choices;
@property EntityManager *entityManager;

@property BOOL isNewBallot;
@property Ballot *ballot;
@property Conversation *conversation;
@property (nonatomic, strong) NSIndexPath *indexPathForPicker;
@property (nonatomic, strong) NSDate *lastSelectedDate;
@property (nonatomic) BOOL lastPickerWithoutTime;

@end

@implementation BallotCreateViewController

+ (instancetype) ballotCreateViewControllerForConversation:(Conversation *)conversation {
    BallotCreateViewController *viewController = [self ballotCreateViewController];
    
    [viewController.entityManager performBlockAndWait:^{
        Conversation *ownContextConversation = (Conversation *)[viewController.entityManager.entityFetcher existingObjectWithID:conversation.objectID];
        viewController.conversation = ownContextConversation;
        viewController.ballot = [viewController newBallot];
        viewController.ballot.conversation = ownContextConversation;
        viewController.isNewBallot = YES;
    }];
    
    return viewController;
}

+ (instancetype) ballotCreateViewControllerForBallot:(Ballot *)ballot {
    BallotCreateViewController *viewController = [self ballotCreateViewController];

    [viewController.entityManager performBlockAndWait:^{
        viewController.ballot = (Ballot *)[viewController.entityManager.entityFetcher existingObjectWithID:ballot.objectID];
        viewController.conversation = viewController.ballot.conversation;
        viewController.isNewBallot = NO;
    }];
    
    return viewController;
}

+ (instancetype) ballotCreateViewController {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Ballot" bundle:nil];
    
    BallotCreateViewController *viewController = (BallotCreateViewController *) [storyboard instantiateViewControllerWithIdentifier:@"BallotCreateViewController"];

    // Special config DB child context on main queue.
    viewController.entityManager = [[EntityManager alloc] initWithChildContextForBackgroundProcess:NO];
    
    return viewController;
}

-(void)dealloc {
    [self removeFromObserver];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self dismissPicker];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(applicationDidEnterBackground:) name: UIApplicationDidEnterBackgroundNotification object: nil];
    
    _cancelButton.target = self;
    _cancelButton.action = @selector(cancelPressed);

    _sendButton.target = self;
    _sendButton.action = @selector(sendPressed);

    [_addButton addTarget:self action:@selector(addPressed) forControlEvents:UIControlEventTouchUpInside];

    _choiceTableView.delegate = self;
    _choiceTableView.dataSource = self;
    
    [self updateUIStrings];
    
    if (_isNewBallot == NO) {
        [self setOnlyEditing];
    }

    [self registerForKeyboardNotifications];
    
    [_titleTextView becomeFirstResponder];
}

- (void)refresh {
    [super refresh];
    
    [self updateColors];
}

- (void)updateColors {
    self.view.backgroundColor = Colors.backgroundGroupedViewController;
    _buttonView.backgroundColor = Colors.backgroundGroupedViewController;
    
    _hairlineTop.backgroundColor = Colors.textLight;
    _hairlineTop.frame = [RectUtil setHeightOf:_hairlineTop.frame height:0.5];

    _headerView.backgroundColor = Colors.backgroundHeaderView;
    
    self.titleTextView.backgroundColor = [UIColor clearColor];
    self.titleTextView.placeholderTextColor = Colors.textVeryLight;
    
    [Colors updateKeyboardAppearanceFor:_titleTextView];
}

- (void)setOnlyEditing {
    _optionsButton.enabled = NO;
    _addButton.enabled = NO;
}
     
- (void)viewWillAppear:(BOOL)animated {
    [self updateContent];
        
    _indexPathForPicker = nil;
    
    [super viewWillAppear:animated];
    
    [self updateColors];
}

- (void)updateUIStrings {
    if (_isNewBallot) {
        [_sendButton setTitle:[BundleUtil localizedStringForKey:@"send"]];
    } else {
        [_sendButton setTitle:[BundleUtil localizedStringForKey:@"save"]];
    }
    
    UIFontDescriptor *fontDescriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleHeadline];
    _titleTextView.attributedPlaceholder =[[NSAttributedString alloc] initWithString:[BundleUtil localizedStringForKey:@"ballot_placeholder_title"] attributes:@{NSFontAttributeName : [UIFont systemFontOfSize:fontDescriptor.pointSize]}];
    
    [_optionsButton setTitle:[BundleUtil localizedStringForKey:@"ballot_options"] forState:UIControlStateNormal];
    
    _addButton.accessibilityValue = [BundleUtil localizedStringForKey:@"ballot_add_choice"];

    [self setTitle:[BundleUtil localizedStringForKey:@"ballot_create"]];
}

- (void)updateContent {
    [_entityManager performBlockAndWait:^{
        [_titleTextView setText:_ballot.title];

        NSArray *sortedChoices = [_ballot choicesSortedByOrder];
        if (_choices != nil) {
            for (BallotChoice *choice in _choices) {
                if ([sortedChoices containsObject: choice] == NO) {
                    [choice.managedObjectContext deleteObject: choice];
                }
            }
        }

        _choices = [NSMutableArray arrayWithArray: sortedChoices];
    }];

    /* show at least two cells */
    for (NSInteger i=[_choices count]; i<MIN_NUMBER_CHOICES; i++) {
        [self addChoice];
    }
    
    if (_conversation == nil) {
        //ballot has no conversation
        self.sendButton.enabled = NO;
    }
    
    [_choiceTableView reloadData];
}

- (void)addChoice {
    [_entityManager performBlockAndWait:^{
        BallotChoice *choice = [_entityManager.entityCreator ballotChoice];

        [_choices addObject: choice];
    }];
}


- (void)updateEntityObjects {
    [_entityManager performBlockAndWait:^{
        _ballot.title = _titleTextView.text;

        NSSet *verifiedChoices = [self verifiedChoices];
        NSInteger i=0;
        for (BallotChoice *choice in _choices) {
            if ([verifiedChoices containsObject:choice]) {
                choice.ballot = _ballot;
                choice.orderPosition = [NSNumber numberWithInteger: i];
                i++;
            } else {
                [choice.managedObjectContext deleteObject: choice];
            }

        }
        
        _ballot.choices = verifiedChoices;
    }];
}

- (NSSet *)verifiedChoices {
    NSMutableSet *verifiedChoices = [NSMutableSet set];
    [_entityManager performBlockAndWait:^{
        for (BallotChoice *choice in _choices) {
            if (choice.name && [choice.name length] > MIN_NUMBER_CHARACTERS) {
                [verifiedChoices addObject:choice];
            }
        }
    }];
    return verifiedChoices;
}

- (BOOL)isContentValid {
    if ([[self verifiedChoices] count] < MIN_NUMBER_CHOICES) {
        NSString *message = [BundleUtil localizedStringForKey:@"ballot_validation_not_enough_choices"];
        [self showAlert: message];
        return NO;
    } else if (_titleTextView.text <= MIN_NUMBER_CHARACTERS) {
        NSString *message = [BundleUtil localizedStringForKey:@"ballot_validation_title_missing"];
        [self showAlert: message];
        return NO;
    }
    
    return YES;
}

- (void)showAlert:(NSString *)message {
    NSString *title = [BundleUtil localizedStringForKey:@"ballot_validation_error_title"];
    [UIAlertTemplate showAlertWithOwner:self title:title message:message actionOk:nil];
}

- (Ballot *)newBallot {
    Ballot *ballot = [_entityManager.entityCreator ballot];
    ballot.id = [[NaClCrypto sharedCrypto] randomBytes:kBallotIdLen];
    ballot.createDate = [NSDate date];
    ballot.creatorId = [MyIdentityStore sharedMyIdentityStore].identity;

    NSUserDefaults *defaults = [AppGroup userDefaults];
    NSNumber *type = [defaults objectForKey:@"ballotLastType"];
    if (type) {
        ballot.type = type;
    }

    NSNumber *assessmentType = [defaults objectForKey:@"ballotLastAssessmentType"];
    if (assessmentType) {
        ballot.assessmentType = assessmentType;
    }
    
    // Clients will always send DisplayListMode, SummaryMode is only for Broadcast
    ballot.ballotDisplayMode = BallotDisplayModeList;
    
    return ballot;
}

- (void)addChoiceToTable {
    [_choiceTableView beginUpdates];
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[_choices count] inSection:0];
    [self addChoice];
    [_choiceTableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
    
    [_choiceTableView endUpdates];
}

- (void)updateAvailableCells {
    NSSet *verifiedChoices = [self verifiedChoices];
    if ([verifiedChoices count] >= [_choices count]) {
        [self addChoiceToTable];
    }
}

- (void)dismissPicker {
    if (_indexPathForPicker) {
        BallotCreateTableCell *selectedCell = [_choiceTableView cellForRowAtIndexPath:_indexPathForPicker];
        [selectedCell showDatePicker:nil];
        _indexPathForPicker = nil;
    }
}

#pragma mark - button actions

- (void)addPressed {
    [self addChoiceToTable];
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    [self setFirstResponderAfterIndexPath: indexPath];
}

- (void)sendPressed {
    if ([self isContentValid] == NO) {
        return;
    }
    
    [self updateEntityObjects];
    
    NSUserDefaults *defaults = [AppGroup userDefaults];
    [_entityManager performBlockAndWait:^{
        [defaults setObject:_ballot.type forKey:@"ballotLastType"];
        [defaults setObject:_ballot.assessmentType forKey:@"ballotLastAssessmentType"];
    }];
    
    
    [_entityManager performSyncBlockAndSafe:nil];

    [[[[BusinessInjector alloc] initWithEntityManager:_entityManager] messageSenderObjC] sendBallotMessageFor:_ballot];

    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancelPressed {
    [_entityManager performBlockAndWait:^{
        [_entityManager rollback];
    }];
    
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - table cell callback

- (void)didChangeChoiseText:(NSString *)text on:(BallotCreateTableCell *)cell {
    NSIndexPath *indexPath = [_choiceTableView indexPathForCell: cell];

    [_entityManager performBlockAndWait:^{
        ((BallotChoice *)_choices[indexPath.row]).name = text;
    }];
}

- (void)didUpdateCell:(BallotCreateTableCell *)cell {
    NSIndexPath *indexPath = [_choiceTableView indexPathForCell: cell];
    
    if ([cell.choiceTextField isFirstResponder]) {
        [self updateAvailableCells];
        [self setFirstResponderAfterIndexPath: indexPath];
    }
}

- (void)showPickerForCell:(BallotCreateTableCell *)cell {
    if (_indexPathForPicker) {
        BallotCreateTableCell *lastCell = [_choiceTableView cellForRowAtIndexPath:_indexPathForPicker];
        [lastCell showDatePicker:nil];
    }
    
    [_choiceTableView endEditing:YES];
    [_choiceTableView resignFirstResponder];
    [_titleTextView resignFirstResponder];
    
    if (_lastSelectedDate) {
        [cell setInputText:_lastSelectedDate allDay:_lastPickerWithoutTime];
    }
    
    [_choiceTableView beginUpdates];
    _indexPathForPicker = [_choiceTableView indexPathForCell:cell];
    [_choiceTableView endUpdates];
    
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

- (void)hidePickerForCell:(BallotCreateTableCell *)cell {
    _lastSelectedDate = cell.datePicker.date;
    _lastPickerWithoutTime = cell.allDaySwitch.on;
    [_choiceTableView beginUpdates];
    _indexPathForPicker = nil;
    [_choiceTableView endUpdates];
    
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

- (void)setFirstResponderAfterIndexPath:(NSIndexPath *)indexPath {
    NSInteger index = indexPath.row;
    while (index < [_choices count]) {
        NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:index inSection:0];
        BallotCreateTableCell *nextCell = (BallotCreateTableCell *)[_choiceTableView cellForRowAtIndexPath: newIndexPath];
        if ([nextCell.choiceTextField.text length] <= 0) {
            [nextCell.choiceTextField becomeFirstResponder];
            
            break;
        }

        index++;
    }
}

#pragma mark - table view data source / delegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    [Colors updateWithCell:cell setBackgroundColor:true];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_indexPathForPicker && indexPath.section == _indexPathForPicker.section && indexPath.row == _indexPathForPicker.row) {
        if (UITraitCollection.currentTraitCollection.preferredContentSizeCategory >= UIContentSizeCategoryAccessibilityExtraExtraLarge) {
            return 750;
        }
        else if (UITraitCollection.currentTraitCollection.preferredContentSizeCategory >= UIContentSizeCategoryAccessibilityMedium) {
            return 650;
        }
        else if (UITraitCollection.currentTraitCollection.preferredContentSizeCategory >= UIContentSizeCategoryExtraLarge) {
            return 550.0;
        }
        
        return 450.0;
    }

    return UITableViewAutomaticDimension;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_choices count];
}

- (UITableViewCell *)tableView: (UITableView *) tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    BallotCreateTableCell *cell = [tableView dequeueReusableCellWithIdentifier: BALLOT_CREATE_TABLE_CELL_ID];
    if (cell == nil) {
        //Fallback
        cell = [[BallotCreateTableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier: BALLOT_CREATE_TABLE_CELL_ID];
    }

    cell.delegate = self;
    
    [_entityManager performBlockAndWait:^{
        cell.choiceTextField.text = ((BallotChoice *) _choices[indexPath.row]).name;
    }];
    
    if (_isNewBallot == NO) {
        cell.userInteractionEnabled = NO;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [_entityManager performBlockAndWait:^{
            BallotChoice *choice = [_choices objectAtIndex:indexPath.row];
            [[_entityManager entityDestroyer] deleteWithBallotChoice:choice];

            [_choices removeObjectAtIndex: indexPath.row];
        }];
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_isNewBallot) {
        return UITableViewCellEditingStyleDelete;
    } else {
        return UITableViewCellEditingStyleNone;
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    [self dismissPicker];
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    BallotChoice *choiceToMove = [_choices objectAtIndex:sourceIndexPath.row];
    [_choices removeObjectAtIndex:sourceIndexPath.row];
    [_choices insertObject:choiceToMove atIndex:destinationIndexPath.row];
}

# pragma mark Keyboard Notifications

- (void)registerForKeyboardNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification object:nil];
}

- (void)removeFromObserver {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (void)keyboardWillShow: (NSNotification*) aNotification {
    NSDictionary* info = [aNotification userInfo];
    
    CGRect keyboardRect = [[info objectForKey: UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardRectConverted = [_choiceTableView convertRect: keyboardRect fromView: nil];
    CGSize keyboardSize = keyboardRectConverted.size;
 
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardSize.height, 0.0);
    _choiceTableView.contentInset = contentInsets;
    _choiceTableView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardDidShow:(NSNotification *)aNotification {
    if (_indexPathForPicker) {
        BallotCreateTableCell *lastCell = [_choiceTableView cellForRowAtIndexPath:_indexPathForPicker];
        if (!lastCell.choiceTextField.isFirstResponder) {
            [_choiceTableView scrollToRowAtIndexPath:_indexPathForPicker atScrollPosition:UITableViewScrollPositionBottom animated:true];
        }
        [lastCell showDatePicker:nil];
    }
}
                            
- (void)keyboardWillHide:(NSNotification*)aNotification
{
    _choiceTableView.contentInset = UIEdgeInsetsZero;
    _choiceTableView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"ballotOptionsSegue"]) {
        [self updateEntityObjects];
        
        BallotCreateDetailViewController *controller = (BallotCreateDetailViewController*)segue.destinationViewController;
        controller.ballot = _ballot;
        controller.entityManager = _entityManager;
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    if ([[KKPasscodeLock sharedLock] isPasscodeRequired]) {
        [_entityManager rollback];
    }
}


@end
