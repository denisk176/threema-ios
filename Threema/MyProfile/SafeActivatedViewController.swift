//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2018-2025 Threema GmbH
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

import ThreemaMacros
import UIKit

class SafeActivatedViewController: ThemedTableViewController {
    
    let refreshViewNotificationName = Notification.Name(kSafeBackupUIRefresh)
    
    @IBOutlet var backupNowCell: UITableViewCell!

    @IBOutlet var serverNameLabel: UILabel!
    @IBOutlet var serverNameValueLabel: UILabel!
    @IBOutlet var maxBackupBytesLabel: UILabel!
    @IBOutlet var maxBackupBytesValueLabel: UILabel!
    @IBOutlet var retentionDaysLabel: UILabel!
    @IBOutlet var retentionDaysValueLabel: UILabel!
    @IBOutlet var lastBackupLabel: UILabel!
    @IBOutlet var lastBackupValueLabel: UILabel!
    @IBOutlet var backupSizeLabel: UILabel!
    @IBOutlet var backupSizeValueLabel: UILabel!
    @IBOutlet var lastResultLabel: UILabel!
    @IBOutlet var lastResultValueLabel: UILabel!
    
    @IBOutlet var explainButton: UIButton!
    @IBOutlet var backupNowButtonLabel: UILabel!
    @IBOutlet var changePasswordButtonLabel: UILabel!
    
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    
    var tapGestureRecognizer: UITapGestureRecognizer!
    
    private var backupTimer: Timer?
    private var mdmSetup: MDMSetup
    
    required init?(coder aDecoder: NSCoder) {
        self.mdmSetup = MDMSetup(setup: false)
        
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        serverNameLabel.text = #localize("safe_server_name")
        maxBackupBytesLabel.text = #localize("safe_max_backup_size")
        retentionDaysLabel.text = #localize("safe_retention")
        lastBackupLabel.text = #localize("safe_last_backup")
        backupSizeLabel.text = #localize("safe_size")
        lastResultLabel.text = #localize("safe_result")

        explainButton.accessibilityLabel = #localize("safe_learn_more")
        backupNowButtonLabel.text = #localize("safe_backup_now")
        changePasswordButtonLabel.text = #localize("safe_change_password")
        
        activityIndicator.hidesWhenStopped = true
        
        serverNameLabel.textColor = .label
        maxBackupBytesLabel.textColor = .label
        retentionDaysLabel.textColor = .label
        lastBackupLabel.textColor = .label
        backupSizeLabel.textColor = .label
        lastResultLabel.textColor = .label
        
        serverNameValueLabel.textColor = .secondaryLabel
        maxBackupBytesValueLabel.textColor = .secondaryLabel
        retentionDaysValueLabel.textColor = .secondaryLabel
        lastBackupValueLabel.textColor = .secondaryLabel
        backupSizeValueLabel.textColor = .secondaryLabel
        lastResultValueLabel.textColor = .secondaryLabel
        
        backupNowButtonLabel.textColor = .tintColor
        changePasswordButtonLabel.textColor = .tintColor
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshViewNotification(notification:)),
            name: refreshViewNotificationName,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: self.refreshViewNotificationName, object: nil)
    }
    
    // MARK: - Public
    
    func backupNow() {
        // object: 0 -> 0s backup delay and force it
        
        // show activity on backup cell
        activityIndicator.startAnimating()
        backupNowButtonLabel.isHidden = true
        backupNowCell.isUserInteractionEnabled = false
        
        // start timer to hide activity on backup cell if backup is to fast
        backupTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(maybeHideActivityIndicator),
            userInfo: nil,
            repeats: false
        )
        
        NotificationCenter.default.post(name: NSNotification.Name(kSafeBackupTrigger), object: 0)
    }
    
    @objc func refreshViewNotification(notification: Notification) {
        refreshView(updateCell: true)
    }
        
    @objc func refreshView(updateCell: Bool) {
        let hyphen = "-"
        let safeConfigManager = SafeConfigManager()
        let safeStore = SafeStore(
            safeConfigManager: safeConfigManager,
            serverApiConnector: ServerAPIConnector(),
            groupManager: BusinessInjector.ui.groupManager
        )
        let safeManager = SafeManager(
            safeConfigManager: safeConfigManager,
            safeStore: safeStore,
            safeApiService: SafeApiService()
        )

        if updateCell {
            if safeManager.isBackupRunning {
                activityIndicator.startAnimating()
                backupNowButtonLabel.isHidden = true
                backupNowCell.isUserInteractionEnabled = false
            }
            else {
                if backupTimer == nil {
                    activityIndicator.stopAnimating()
                    backupNowButtonLabel.isHidden = false
                    backupNowCell.isUserInteractionEnabled = true
                }
            }
        }

        guard safeConfigManager.getKey() != nil else {
            serverNameValueLabel.text = hyphen
            maxBackupBytesValueLabel.text = hyphen
            retentionDaysValueLabel.text = hyphen
            lastBackupValueLabel.text = hyphen
            lastResultValueLabel.text = hyphen

            return
        }
        
        serverNameValueLabel.text = safeStore.getSafeServerToDisplay()

        maxBackupBytesValueLabel.text = safeConfigManager.getMaxBackupBytes() != nil ? String
            .localizedStringWithFormat("%1.2f KB", Float(safeConfigManager.getMaxBackupBytes()!) / 1024) : hyphen
        retentionDaysValueLabel.text = safeConfigManager.getRetentionDays() != nil ? String.localizedStringWithFormat(
            #localize("number_of_days"),
            safeConfigManager.getRetentionDays()!
        ) : hyphen
        backupSizeValueLabel.text = safeConfigManager.getBackupSize() != nil ? String.localizedStringWithFormat(
            "%1.2f KB",
            Float(safeConfigManager.getBackupSize()!) / 1024
        ) : hyphen
        lastBackupValueLabel.text = safeConfigManager.getLastBackup() != nil ? DateFormatter
            .mediumStyleDateShortStyleTime(safeConfigManager.getLastBackup()!) : hyphen
        lastResultValueLabel.text = safeConfigManager.getLastResult() != nil ? safeConfigManager
            .getLastResult()! : hyphen
        
        if lastResultValueLabel.text == #localize("safe_successful") {
            lastResultValueLabel.textColor = .systemGreen
        }
        else if lastResultValueLabel.text != "-" {
            lastResultValueLabel.textColor = .systemRed
        }
        
        tableView.reloadData()
    }
    
    @objc private func maybeHideActivityIndicator() {
        let safeConfigManager = SafeConfigManager()
        let safeStore = SafeStore(
            safeConfigManager: safeConfigManager,
            serverApiConnector: ServerAPIConnector(),
            groupManager: BusinessInjector.ui.groupManager
        )
        let safeManager = SafeManager(
            safeConfigManager: safeConfigManager,
            safeStore: safeStore,
            safeApiService: SafeApiService()
        )
        if !safeManager.isBackupRunning {
            activityIndicator.stopAnimating()
            backupNowButtonLabel.isHidden = false
            backupNowCell.isUserInteractionEnabled = true
        }
        backupTimer = nil
    }
    
    // MARK: UITableViewDelegates

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case 2:
            indexPath.row == 2 && mdmSetup.isSafeBackupPasswordPreset() ? 0.0 : UITableView.automaticDimension
        default:
            UITableView.automaticDimension
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        if indexPath.section == 2 {
            switch indexPath.row {
            case 0:
                UIAlertTemplate.showAlert(
                    owner: self,
                    title: String.localizedStringWithFormat(
                        #localize("safe_setup_backup_title"),
                        TargetManager.localizedAppName
                    ),
                    message: String.localizedStringWithFormat(
                        #localize("safe_enable_explain"),
                        TargetManager.localizedAppName
                    )
                )
            case 1:
                backupNow()
            case 2:
                if !mdmSetup.isSafeBackupPasswordPreset(),
                   let safeSetupViewController = parent as? SafeSetupViewController {
                    
                    safeSetupViewController.performSegue(withIdentifier: "SafeSetupPassword", sender: nil)
                }
            default: break
            }
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
    
    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        super.tableView(tableView, willDisplay: cell, forRowAt: indexPath)
        
        let safeManager = SafeManager(groupManager: BusinessInjector.ui.groupManager)
        if indexPath.section == 2, indexPath.row == 2, safeManager.isSafePasswordDefinedByAdmin() {
            cell.isUserInteractionEnabled = false
            changePasswordButtonLabel.isEnabled = false
            changePasswordButtonLabel.text = #localize("safe_change_password_disabled")
        }
    }
}

extension SafeActivatedViewController {
    
    @IBAction func touchDownExplainButton(_ sender: UIButton, forEvent event: UIEvent) {
        UIAlertTemplate.showAlert(
            owner: self,
            title: String.localizedStringWithFormat(
                #localize("safe_setup_backup_title"),
                TargetManager.localizedAppName
            ),
            message: String.localizedStringWithFormat(
                #localize("safe_enable_explain"),
                TargetManager.localizedAppName
            )
        )
    }
}
