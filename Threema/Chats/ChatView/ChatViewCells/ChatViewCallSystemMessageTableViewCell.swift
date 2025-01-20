//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2025 Threema GmbH
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

import CocoaLumberjackSwift
import ThreemaFramework
import ThreemaMacros
import UIKit

/// Display a call message
final class ChatViewCallSystemMessageTableViewCell: ChatViewBaseTableViewCell, MeasurableCell {
    static var sizingCell = ChatViewCallSystemMessageTableViewCell()
    
    /// Call message to display
    ///
    /// Reset it when the message had any changes to update data shown in the views (e.g. date or status symbol).
    var callMessageAndNeighbors: (message: SystemMessageEntity, neighbors: ChatViewDataSource.MessageNeighbors)? {
        didSet {
            updateCell(for: callMessageAndNeighbors?.message)
            
            super.setMessage(to: callMessageAndNeighbors?.message, with: callMessageAndNeighbors?.neighbors)
        }
    }
    
    // MARK: - Views
    
    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.preferredSymbolConfiguration = ChatViewConfiguration.Text.symbolConfiguration
        imageView.accessibilityElementsHidden = true
        return imageView
    }()
    
    private lazy var messageTextView = MessageTextView(messageTextViewDelegate: nil)
    private lazy var metaDataLabel: UILabel = {
        let label = UILabel(frame: .zero)
        label.numberOfLines = 0
        label.font = ChatViewConfiguration.MessageMetadata.font
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        return label
    }()
    
    private lazy var stateAndDateView = MessageDateAndStateView()
    
    /// Stack view containing metaDataLabel and the dateAndStateView
    private lazy var metaDataStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [metaDataLabel, stateAndDateView])
        stackView.alignment = .firstBaseline
        stackView.distribution = .fill
        
        // We switch from horizontal to vertical if accessibility fonts are enabled
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            stackView.axis = .vertical
        }
        else {
            stackView.spacing = ChatViewConfiguration.MessageMetadata.minimalInBetweenSpace
            stackView.axis = .horizontal
        }
                
        return stackView
    }()
    
    private lazy var iconMessageContentView = IconMessageContentView(iconView: iconView, arrangedSubviews: [
        messageTextView,
        metaDataStackView,
    ]) { [weak self] in
        guard let strongSelf = self else {
            return
        }
        
        strongSelf.chatViewTableViewCellDelegate?.didTap(
            message: strongSelf.callMessageAndNeighbors?.message,
            in: strongSelf
        )
    }
    
    // MARK: - Configuration
    
    override func configureCell() {
        super.configureCell()
         
        messageTextView.isUserInteractionEnabled = false
        super.addContent(rootView: iconMessageContentView)
    }
    
    // MARK: - Updates
    
    override func updateColors() {
        super.updateColors()
        if case let .callMessage(type: call) = callMessageAndNeighbors?.message.systemMessageType {
            iconView.image = call.symbol
        }
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        iconMessageContentView.isUserInteractionEnabled = !editing
    }
    
    private func updateCell(for callMessage: SystemMessageEntity?) {
        // By accepting an optional the data is automatically reset when the text message is set to `nil`
        guard case let .callMessage(type: call) = callMessage?.systemMessageType else {
            return
        }

        iconView.image = call.symbol
        messageTextView.text = call.localizedMessage
        stateAndDateView.message = callMessage
        
        // We remove the duration label if there is no call time, OR statements are not possible with if case, so we use
        // else if
        if case let .endedIncomingSuccessful(duration: timeString) = call {
            metaDataLabel.attributedText = duration(callTime: timeString)
            metaDataStackView.insertArrangedSubview(metaDataLabel, at: 0)
        }
        else if case let .endedOutgoingSuccessful(duration: timeString) = call {
            metaDataLabel.attributedText = duration(callTime: timeString)
            metaDataStackView.insertArrangedSubview(metaDataLabel, at: 0)
        }
        else {
            metaDataStackView.removeArrangedSubview(metaDataLabel)
            metaDataLabel.removeFromSuperview()
        }
        
        // Fixes an issue where the call icon could be miss-aligned
        iconMessageContentView.layoutIfNeeded()
        
        updateAccessibility()
    }
    
    /// Get NSAttributedString of style "􀐱 xx:xx" containing the duration of the call message
    /// - Parameter callTime: Duration of message
    /// - Returns: Attributed string
    private func duration(callTime: String?) -> NSMutableAttributedString? {
        
        guard let callTime else {
            return nil
        }
       
        let icon = UIImage(
            systemName: "timer",
            withConfiguration: ChatViewConfiguration.MessageMetadata.symbolConfiguration
        )?
            .withTintColor(.secondaryLabel)
        
        // Combine String
        let duration = NSMutableAttributedString(string: callTime)
        
        if let icon {
            let timerImage = NSTextAttachment()
            timerImage.image = icon
            let timerString = NSAttributedString(attachment: timerImage)
            let spaceString = NSAttributedString(string: " ")
            duration.insert(spaceString, at: 0)
            duration.insert(timerString, at: 0)
        }
        
        return duration
    }
    
    // MARK: - Accessibility
    
    private func updateAccessibility() {
        guard let callDuration = callMessageAndNeighbors?.message.callDuration() else {
            return
        }
    
        metaDataLabel.accessibilityLabel = String.localizedStringWithFormat(
            #localize("call_duration"),
            callDuration
        )
    }
}

// MARK: - Reusable

extension ChatViewCallSystemMessageTableViewCell: Reusable { }

// MARK: - ChatViewMessageActions

extension ChatViewCallSystemMessageTableViewCell: ChatViewMessageActions {
    
    func messageActionsSections() -> [ChatViewMessageActionsProvider.MessageActionsSection]? {
        
        guard let message = callMessageAndNeighbors?.message else {
            return nil
        }

        typealias Provider = ChatViewMessageActionsProvider
        
        // Details
        let detailsHandler: Provider.DefaultHandler = {
            self.chatViewTableViewCellDelegate?.showDetails(for: message.objectID)
        }
        
        // Select
        let selectHandler: Provider.DefaultHandler = {
            self.chatViewTableViewCellDelegate?.startMultiselect(with: message.objectID)
        }
        
        // Delete
        
        let willDelete: Provider.DefaultHandler = {
            self.chatViewTableViewCellDelegate?.willDeleteMessage(with: message.objectID)
        }
        
        let didDelete: Provider.DefaultHandler = {
            self.chatViewTableViewCellDelegate?.didDeleteMessages()
        }
        
        // Build menu

        let basicActions = Provider.defaultBasicActions(
            message: message,
            popOverSource: chatBubbleContentView,
            detailsHandler: detailsHandler,
            selectHandler: selectHandler,
            willDelete: willDelete,
            didDelete: didDelete
        )
        
        return [.init(sectionType: .inline, actions: basicActions)]
    }
    
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            buildAccessibilityCustomActions(reactionsManager: reactionsManager)
        }
        set {
            // No-op
        }
    }
}
