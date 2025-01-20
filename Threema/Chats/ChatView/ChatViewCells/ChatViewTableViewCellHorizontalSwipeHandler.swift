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
import Foundation
import UIKit

protocol ChatViewTableViewCellHorizontalSwipeHandlerDelegate: NSObject {
    var canQuote: Bool { get }
    
    func swipe(with recognizer: UIPanGestureRecognizer)
    func showQuoteView()
    func configure(swipeGestureRecognizer: UIPanGestureRecognizer)
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
}

/// Handles horizontal swipe interactions for mentions and cell details
class ChatViewTableViewCellHorizontalSwipeHandler: NSObject {
    typealias Config = ChatViewConfiguration.ChatBubble.SwipeInteraction
    
    // MARK: - Private Properties
    
    // State for swipe interactions
    private var swipeForCellDetail = false
    private var prevDisplacement: CGFloat = 0.0
    private var activated = false
    
    private weak var swipeGesture: UIPanGestureRecognizer?
    private var originalCellCenter: CGPoint?
    
    private weak var cell: UITableViewCell?
    private weak var delegate: ChatViewTableViewCellHorizontalSwipeHandlerDelegate?
    
    private lazy var quoteSymbolView: UIImageView = {
        let quoteImage = UIImage(systemName: Config.quoteSymbolName)?
            .withRenderingMode(.alwaysOriginal)
        
        let quoteImageView = UIImageView(image: quoteImage)
        quoteImageView.alpha = 0.0
        quoteImageView.tintColor = .secondaryLabel
        
        return quoteImageView
    }()
    
    // MARK: - Lifecycle
    
    init(cell: UITableViewCell, delegate: ChatViewTableViewCellHorizontalSwipeHandlerDelegate) {
        self.cell = cell
        self.delegate = delegate
        
        super.init()
        
        configure(with: cell)
        addInteractions()
    }
    
    // MARK: - Configuration Functions
    
    private func configure(with cell: UITableViewCell) {
        // Add images for quote interaction
        // They might not be needed but at this point the message might not have been set yet. And the message might not
        // be quotable after all.
        quoteSymbolView.translatesAutoresizingMaskIntoConstraints = false
        
        cell.contentView.addSubview(quoteSymbolView)
        
        NSLayoutConstraint.activate([
            quoteSymbolView.leadingAnchor.constraint(
                equalTo: cell.contentView.leadingAnchor,
                constant: -Config.iconInset
            ),
            quoteSymbolView.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
        ])
    }
        
    // MARK: Private functions
    
    private func addInteractions() {
        let newSwipeGesture = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        
        newSwipeGesture.delegate = self
        newSwipeGesture.cancelsTouchesInView = false
        
        cell?.addGestureRecognizer(newSwipeGesture)
        
        swipeGesture = newSwipeGesture
    }
    
    // MARK: Action Functions
    
    @objc func swiped(_ gestureRecognizer: UIPanGestureRecognizer) {
        
        guard !(cell?.isEditing ?? false) else {
            return
        }
        
        switch gestureRecognizer.state {
        case .began:
            swipeBegan()
        case .changed:
            swipeChanged(gestureRecognizer)
        case .ended:
            swipeEnded()
        case .failed, .cancelled:
            swipeEnded()
        case .possible:
            break
        @unknown default:
            let msg = "Unhandled case in swipe gesture recognizer."
            assertionFailure(msg)
            DDLogError(msg)
        }
        
        if swipeForCellDetail {
            delegate?.swipe(with: gestureRecognizer)
        }
    }
    
    private func swipeBegan() {
        originalCellCenter = cell?.center
    }
    
    private func swipeChanged(_ gestureRecognizer: UIPanGestureRecognizer) {
        let translation: CGPoint = gestureRecognizer.translation(in: cell)
        let displacement = CGPoint(x: translation.x, y: translation.y)
        
        defer {
            prevDisplacement = displacement.x
        }
        
        guard let originalCellCenter else {
            return
        }
        
        guard let cell else {
            return
        }
        
        cell.center = CGPoint(x: originalCellCenter.x, y: cell.center.y)

        // Move right to quote
        if displacement.x >= 0 {
            quoteSymbolView.alpha = displacement.x / Config.swipeActionOffsetThreshold
            
            if displacement.x > Config.swipeActionOffsetThreshold {
                if !activated {
                    performActivationAnimation()
                }
                cell.transform = cell.transform.translatedBy(
                    x: (displacement.x - prevDisplacement) * Config.bubbleSlowdownFactorQuote,
                    y: 0
                )
            }
            else {
                activated = false
                cell.transform = cell.transform.translatedBy(
                    x: displacement.x - prevDisplacement,
                    y: 0
                )
            }
        }
        // Move left to show details
        else {
            // Push view controller
            cell.transform = cell.transform.translatedBy(
                x: (displacement.x - prevDisplacement) * Config.bubbleSlowdownFactorDetails,
                y: 0
            )
        }
    }
    
    private func swipeEnded() {
        resetViewPositionAndTransformations()
        
        if activated, let delegate, delegate.canQuote {
            delegate.showQuoteView()
        }

        // Reset center after gesture to fix cell overlap that might have occurred when a snapshot was applied during
        // swipe
        if let cell = cell as? ChatViewBaseTableViewCell,
           let originalCellCenter {
            cell.center = CGPoint(x: originalCellCenter.x, y: originalCellCenter.y)
        }
        quoteSymbolView.alpha = 0.0
        
        prevDisplacement = 0.0
        activated = false
    }
    
    private func performActivationAnimation() {
        guard let delegate else {
            return
        }
        
        guard delegate.canQuote else {
            return
        }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        activated = true
        
        /// Visual Feedback
        /// Enlarge
        UIView.animate(withDuration: Config.startQuoteIconAnimationDuration) {
            self.quoteSymbolView.transform = self.quoteSymbolView.transform
                .concatenating(CGAffineTransform(
                    scaleX: Config.startQuoteAnimationScaleFactor,
                    y: Config.startQuoteAnimationScaleFactor
                ))
        } completion: { _ in
            /// Reset to original size
            UIView.animate(withDuration: Config.startQuoteIconAnimationDuration) {
                self.quoteSymbolView.transform = self.quoteSymbolView.transform
                    .concatenating(CGAffineTransform(
                        scaleX: 1 / Config.startQuoteAnimationScaleFactor,
                        y: 1 / Config.startQuoteAnimationScaleFactor
                    ))
            }
        }
        
        quoteSymbolView.alpha = 1.0
    }
    
    private func resetViewPositionAndTransformations() {
        guard let originalCellCenter else {
            return
        }
        
        UIView.animate(
            withDuration: Config.resetDuration,
            delay: 0.0,
            usingSpringWithDamping: Config.springDampening,
            initialSpringVelocity: 0.0,
            options: UIView.AnimationOptions(),
            animations: {
                self.cell?.center = originalCellCenter
                self.cell?.transform = .identity
            }
        )
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ChatViewTableViewCellHorizontalSwipeHandler: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let delegate else {
            return false
        }
        
        guard let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
            return delegate.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        
        guard gestureRecognizer == swipeGesture else {
            return delegate.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        
        guard panRecognizer.location(in: cell).x > Config.swipeDeadZone else {
            return false
        }
        
        // Ensure it's a horizontal drag
        let velocity = panRecognizer.velocity(in: cell)
        guard abs(velocity.y) < abs(velocity.x) else {
            return false
        }
        
        // Only allow swipe to quote (swipe right) if message can be quoted
        guard delegate.canQuote || velocity.x < 0 else {
            return false
        }
        
        swipeForCellDetail = velocity.x < 0
        
        return true
    }
}
