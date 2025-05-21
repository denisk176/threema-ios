//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2025 Threema GmbH
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
import PromiseKit
import ThreemaFramework
import ThreemaMacros

@objc class EditProfileViewController: ThemedTableViewController {
    
    @IBOutlet var avatarView: EditableAvatarView!
    
    @IBOutlet var nickNameTitleLabel: UILabel!
    @IBOutlet var nickNameTextField: UITextField!
    
    @IBOutlet var contactsSettingValue: UILabel!
    
    @IBOutlet var profileCell: UITableViewCell!
    @IBOutlet var profilePictureSettingCell: UITableViewCell!
    @IBOutlet var releaseProfileTo: UILabel!
    
    private let mdmSetup = MDMSetup(setup: false)
    private let profileStore: ProfileStore
    private var profile: ProfileStore.Profile
    private var newImage: Data?

    @objc var sendProfilePicture: SendProfilePicture {
        didSet {
            checkDismissOnTapOutside()
        }
    }
    
    @objc var shareWith: [String] {
        didSet {
            checkDismissOnTapOutside()
        }
    }
    
    required init?(coder: NSCoder) {
        self.profileStore = ProfileStore()
        self.profile = profileStore.profile()
        self.sendProfilePicture = profile.sendProfilePicture
        self.newImage = profile.profileImage
        self.shareWith = profile.profilePictureContactList
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        releaseProfileTo.text = #localize("release_profilepicture_to")
        avatarView?.presentingViewController = self
        avatarView?.delegate = self
        avatarView?.canDeleteImage = !(mdmSetup?.readonlyProfile() ?? false)
        avatarView?.canChooseImage = !(mdmSetup?.readonlyProfile() ?? false)
        
        profileCell?.contentView.isAccessibilityElement = false
        profileCell?.contentView.accessibilityLabel = nil
        
        nickNameTextField?.delegate = self
        nickNameTextField?.text = profile.nickname
        
        setupColors()
        
        profilePictureSettingCell?.isUserInteractionEnabled = !(mdmSetup?.disableSendProfilePicture() ?? false)
        
        if mdmSetup?.readonlyProfile() ?? false {
            nickNameTextField?.isEnabled = false
        }
        else {
            if !UIAccessibility.isVoiceOverRunning {
                nickNameTextField?.becomeFirstResponder()
            }
        }
        
        nickNameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }
    
    @objc func textFieldDidChange() {
        checkDismissOnTapOutside()
    }
    
    @objc func cancelPressed() {
        navigationController?.dismiss(animated: true, completion: nil)
    }
    
    @objc func savePressed() {
        attemptSave()
    }
    
    private func checkDismissOnTapOutside() {
        guard let nav = navigationController as? ModalNavigationController else {
            return
        }
        
        if (profile.sendProfilePicture != sendProfilePicture) || (profile.nickname != nickNameTextField.text) ||
            (profile.profileImage != newImage) || profile.profilePictureContactList != shareWith {
            
            nav.dismissOnTapOutside = false
            navigationItem.rightBarButtonItem?.isEnabled = true
        }
        else {
            nav.dismissOnTapOutside = true
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }
    
    func attemptSave() {
        func successHandler() {
            updateView()
            navigationController?.dismiss(animated: true, completion: nil)
        }
        profile.nickname = nickNameTextField.text
        profile.profileImage = newImage
        profile.sendProfilePicture = sendProfilePicture
        profile.profilePictureContactList = shareWith
               
        if BusinessInjector.ui.settingsStore.isMultiDeviceRegistered {
            let progressString = #localize("syncing_profile")
            let syncHelper = UISyncHelper(viewController: self, progressString: progressString)
            syncHelper.execute(profile: profile)
                .done {
                    successHandler()
                }
                .catch { _ in
                    self.navigationController?.dismiss(animated: true, completion: nil)
                }
        }
        else {
            profileStore.save(profile)
            successHandler()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let rightButton = UIBarButtonItem(
            title: #localize("Save"),
            style: .done,
            target: self,
            action: #selector(savePressed)
        )
        navigationItem.rightBarButtonItem = rightButton
        
        let leftButton = UIBarButtonItem(
            title: #localize("cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelPressed)
        )
        navigationItem.leftBarButtonItem = leftButton
        
        updateView()
        checkDismissOnTapOutside()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        LicenseStore.shared().performUpdateWorkInfo()
        nickNameTextField?.resignFirstResponder()
    }
        
    private func setupColors() {
        nickNameTextField?.textColor = .label
        nickNameTitleLabel.textColor = .secondaryLabel
        nickNameTitleLabel?.shadowColor = nil
        
        releaseProfileTo.textColor = .label
        
        contactsSettingValue.textColor = .secondaryLabel
    }
    
    private func updateView() {
        if newImage != nil {
            avatarView?.imageData = newImage
            avatarView?.canDeleteImage = !(mdmSetup?.readonlyProfile() ?? false)
        }
        else {
            avatarView?.imageData = nil
            avatarView?.canDeleteImage = false
        }
        
        nickNameTextField?.placeholder = MyIdentityStore.shared()?.identity
        nickNameTextField?.accessibilityLabel = #localize("id_completed_nickname")
        
        contactsSettingValue?.text = getLabelForSendProfilePicture(sendProfilePicture: sendProfilePicture)
        
        disabledCellsForMDM()
    }
    
    override func resignFirstResponder() -> Bool {
        nickNameTextField?.resignFirstResponder()
        return true
    }
    
    func getLabelForSendProfilePicture(sendProfilePicture: SendProfilePicture) -> String {
        switch sendProfilePicture {
        case SendProfilePictureNone:
            #localize("send_profileimage_off")
        case SendProfilePictureAll:
            #localize("send_profileimage_on")
        case SendProfilePictureContacts:
            #localize("send_profileimage_contacts")
        default:
            ""
        }
    }
    
    func disabledCellsForMDM() {
        profilePictureSettingCell?.isUserInteractionEnabled = !(mdmSetup?.disableSendProfilePicture() ?? false)
        profilePictureSettingCell?.textLabel?.isEnabled = !(mdmSetup?.disableSendProfilePicture() ?? false)
    }
}

extension EditProfileViewController {
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        var footer = #localize("edit_profile_footer")
        
        if (mdmSetup?.readonlyProfile() ?? false) || (mdmSetup?.disableSendProfilePicture() ?? false) {
            footer.append("\n\n")
            footer.append(#localize("disabled_by_device_policy"))
        }
        return footer
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "profilePictrueSendOptions",
           let dest = segue.destination as? ProfilePictureSettingViewController {
            dest.editProfileVC = self
        }
    }
}

// MARK: - EditableAvatarViewDelegate

extension EditProfileViewController: EditableAvatarViewDelegate {
    func avatarImageUpdated(_ newImageData: Data!) {
        newImage = newImageData
        checkDismissOnTapOutside()
        updateView()
    }
}

// MARK: - UITextFieldDelegate

extension EditProfileViewController: UITextFieldDelegate {
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let currentText = textField.text ?? ""
        guard let rangeToBeReplaced = Range(range, in: currentText) else {
            return false
        }
        let newText = currentText.replacingCharacters(in: rangeToBeReplaced, with: string)
        return newText.utf8.count <= kMaxNicknameLength
    }
    
    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        checkDismissOnTapOutside()
        return true
    }
}
