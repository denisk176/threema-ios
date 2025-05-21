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

import Foundation
import QuickLook

private class DisableShareUINavigationItem: UINavigationItem {
    override func setRightBarButtonItems(_ items: [UIBarButtonItem]?, animated: Bool) {
        // forbidden to add anything to right
    }
}

public class ThreemaQLPreviewController: QLPreviewController {
    
    private lazy var disableShareNavigationItem = { [self] in
        let navItem = DisableShareUINavigationItem(title: "")
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(donePressed))
        navItem.leftBarButtonItem = doneButton
        return navItem
    }()
    
    override public var navigationItem: UINavigationItem {
        if disableShareButton {
            return disableShareNavigationItem
        }
        else {
            var navItem: UINavigationItem?
            if Thread.isMainThread {
                return super.navigationItem
            }
            else {
                DispatchQueue.main.sync {
                    navItem = super.navigationItem
                }
                return navItem ?? disableShareNavigationItem
            }
        }
    }
        
    var observations: [NSKeyValueObservation] = []
    
    var mdmSetup = MDMSetup(setup: false)
    
    var disableShareButton = false
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        disableShareButton = mdmSetup?.disableShareMedia() ?? false
        
        if disableShareButton {
            navigationItem.setRightBarButton(UIBarButtonItem(), animated: false)
        }
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        removeToolbarItems()
    }
    
    @objc private func donePressed() {
        dismiss(animated: true)
    }
    
    private func removeToolbarItems() {
        if mdmSetup?.disableShareMedia() ?? false, let navigationToolbar = navigationController?.toolbar {
            navigationToolbar.isHidden = true
            let observation = navigationToolbar.observe(\.isHidden, changeHandler: observeNavigationToolbarHidden)
            observations.append(observation)
        }
    }
    
    func observeNavigationToolbarHidden(changed: UIView, change: NSKeyValueObservedChange<Bool>) {
        if navigationController?.toolbar.isHidden == false {
            navigationController?.toolbar.isHidden = true
        }
    }
}
