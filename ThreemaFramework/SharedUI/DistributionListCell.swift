//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2024-2025 Threema GmbH
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

import UIKit

/// Show a distribution list in a list
///
/// Whenever there is a list of distribution list use this cell for a consistent appearance
public final class DistributionListCell: ThemedCodeTableViewCell {
    
    // MARK: - Private configuration
    
    private lazy var configuration = CellConfiguration(size: size)
    
    // MARK: - Public properties
    
    public var size = CellConfiguration.Size.small {
        didSet {
            guard size != oldValue else {
                return
            }
            
            configuration = CellConfiguration(size: size)
            sizeDidChange()
        }
    }

    /// Distribution list to show
    @objc public var distributionList: DistributionList? {
        didSet {
            guard let distributionList, let name = distributionList.displayName else {
                return
            }
            
            nameLabel.text = name
            topMetadataLabel.text = distributionList.recipientCountString
            membersListLabel.text = distributionList.recipientsSummary
            
            profilePictureView.info = .distributionList(distributionList)
        }
    }
    
    // MARK: - Subviews

    private var profilePictureSizeConstraint: NSLayoutConstraint!
    
    private lazy var profilePictureView: ProfilePictureImageView = {
        let imageView = ProfilePictureImageView()
        
        profilePictureSizeConstraint = imageView.heightAnchor
            .constraint(lessThanOrEqualToConstant: configuration.maxProfilePictureSize)
        profilePictureSizeConstraint.isActive = true
        
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            imageView.isHidden = true
        }
        
        return imageView
    }()
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            label.numberOfLines = 2
        }
        
        return label
    }()
    
    private lazy var topMetadataLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        return label
    }()
    
    private lazy var membersListLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel

        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            label.numberOfLines = 2
        }
        
        return label
    }()
    
    // MARK: Layout stacks
    
    private lazy var firstLineStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [nameLabel, topMetadataLabel])
        
        stackView.axis = .horizontal
        stackView.alignment = .firstBaseline
        stackView.spacing = 8
        stackView.distribution = .equalSpacing
        
        // As view cells are recreated for each content size change so we can just set this here
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            stackView.axis = .vertical
            stackView.alignment = .leading
        }
        
        return stackView
    }()
    
    private lazy var textStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [firstLineStack, membersListLabel])

        stackView.spacing = configuration.verticalSpacing
        stackView.axis = .vertical
        stackView.distribution = .equalSpacing
        stackView.alignment = .fill

        return stackView
    }()
    
    private lazy var containerStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [profilePictureView, textStack])
        
        stackView.axis = .horizontal
        stackView.distribution = .fill
        stackView.alignment = .center
        
        return stackView
    }()
    
    // MARK: - Lifecycle
    
    override public func configureCell() {
        super.configureCell()
        
        sizeDidChange()
        
        contentView.addSubview(containerStack)
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            containerStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }
    
    @objc public func updateDistributionList(_ distList: DistributionList?) {
        guard let distList else {
            distributionList = nil
            return
        }
        distributionList = distList
    }
    
    // MARK: - Updates
    
    private func sizeDidChange() {
        nameLabel.font = configuration.nameLabelFont
        containerStack.spacing = configuration.horizontalSpacing
        
        // Note: We don't reload the profile picture here. So if the `content` is assigned before the `size`
        // we might have a blurry profile picture.
        profilePictureSizeConstraint.constant = configuration.maxProfilePictureSize
        
        updateSeparatorInset()
    }
    
    private func updateSeparatorInset() {
        guard !traitCollection.preferredContentSizeCategory.isAccessibilityCategory else {
            separatorInset = .zero
            return
        }
        
        let leftSeparatorInset = configuration.maxProfilePictureSize + configuration.horizontalSpacing
        separatorInset = UIEdgeInsets(top: 0, left: leftSeparatorInset, bottom: 0, right: 0)
    }
    
    // MARK: - Accessibility
    
    override public var accessibilityLabel: String? {
        get {
            nameLabel.accessibilityLabel
        }
        set { }
    }
    
    override public var accessibilityValue: String? {
        get {
            [
                topMetadataLabel.accessibilityLabel,
                membersListLabel.accessibilityLabel,
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        }
        set { }
    }
}

// MARK: - Reusable

extension DistributionListCell: Reusable { }
