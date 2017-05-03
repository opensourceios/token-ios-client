// Copyright (c) 2017 Token Browser, Inc
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import UIKit
import SweetUIKit
import KeychainSwift

public extension NSNotification.Name {
    public static let UserDidSignOut = NSNotification.Name(rawValue: "UserDidSignOut")
}

open class SettingsController: UITableViewController {

    fileprivate var chatAPIClient: ChatAPIClient {
        return ChatAPIClient.shared
    }

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    public static let verificationStatusChanged = Notification.Name(rawValue: "VerificationStatusChanged")

    private let backupPhraseVerified = "BackupPhraseVerified"

    private var verificationStatus: VerificationStatus = .unverified {
        didSet {
            switch verificationStatus {
            case .correct:
                KeychainSwift().set(true, forKey: self.backupPhraseVerified)
            case .unverified, .tooShort, .incorrect:
                KeychainSwift().set(false, forKey: self.backupPhraseVerified)
            }
        }
    }

    @IBOutlet weak var ratingsView: UIView! {
        didSet {
            self.ratingsView.isHidden = true
        }
    }

    @IBOutlet weak var nameLabel: UILabel! {
        didSet {
            self.nameLabel.text = TokenUser.current?.name
        }
    }

    @IBOutlet weak var usernameLabel: UILabel! {
        didSet {
            self.usernameLabel.text = TokenUser.current?.displayUsername
        }
    }

    @IBOutlet weak var userAvatarImageVIew: UIImageView! {
        didSet {
            self.userAvatarImageVIew.image = TokenUser.current?.avatar
        }
    }

    @IBOutlet weak var balanceLabel: UILabel! {
        didSet {
            self.balanceLabel.attributedText = EthereumConverter.balanceSparseAttributedString(forWei: .zero, width: self.balanceLabel.frame.width)
            EthereumAPIClient.shared.getBalance(address: TokenUser.current?.address ?? "") { balance, _ in
                self.balanceLabel.attributedText = EthereumConverter.balanceSparseAttributedString(forWei: balance, width: self.balanceLabel.frame.width)
            }
        }
    }

    @IBOutlet weak var versionLabel: UILabel! {
        didSet {
            let info = Bundle.main.infoDictionary!
            let version = info["CFBundleShortVersionString"] as! String

            self.versionLabel.text = "Version \(version)"
        }
    }

    var didVerifyBackupPhrase: Bool {
        if let backupPhraseVerified = KeychainSwift().getBool(self.backupPhraseVerified) {
            self.verificationStatus = backupPhraseVerified ? .correct : .incorrect
        } else {
            self.verificationStatus = .unverified
        }

        return self.verificationStatus == .correct
    }

    static func instantiateFromNib() -> SettingsController {
        return UIStoryboard(name: "Settings", bundle: nil).instantiateInitialViewController() as! SettingsController
    }

    private init() {
        fatalError()
    }

    private override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    @objc private func updateVerificationStatus(_ notification: Notification) {
        if let verificationStatus = notification.object as? VerificationStatus {
            self.verificationStatus = verificationStatus
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(self.updateVerificationStatus(_:)), name: SettingsController.verificationStatusChanged, object: nil)
    }

    func handleSignOut() {
        guard let currentUser = TokenUser.current else {
            let alert = UIAlertController(title: "No user found!", message: "This is an error. Please report this.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { _ in
                fatalError()
            }))
            self.present(alert, animated: true)

            return
        }

        let alert = self.alertController(balance: currentUser.balance)
        // We dispatch it back to the main thread here, even tho we are already inside the main thread
        // to avoid some weird issue where the alert controller will take seconds to present, instead of being instant.
        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }

    func alertController(balance: NSDecimalNumber) -> UIAlertController {
        var alert: UIAlertController

        if self.didVerifyBackupPhrase {
            alert = UIAlertController(title: "Have you secured your backup phrase?", message: "Without this you will not be able to recover your account or sign back in.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

            alert.addAction(UIAlertAction(title: "Sign out", style: .destructive) { _ in
                NotificationCenter.default.post(name: .UserDidSignOut, object: nil)
            })
        } else if balance == .zero {
            alert = UIAlertController(title: "Are you sure you want to sign out?", message: "Since you have no funds and did not secure your account, it will be deleted.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                NotificationCenter.default.post(name: .UserDidSignOut, object: nil)
            })
        } else {
            alert = UIAlertController(title: "Sign out cancelled", message: "You need to complete at least one of the security steps to sign out.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .cancel))
        }

        return alert
    }

    // MARK: TableView methods

    /// This handles the actions for cell selection.
    ///
    /// There's unfortunatelly way to directly add IBActions for touching a cell.
    ///
    func performAction(for indexPath: IndexPath) {
        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                // go to user profile
                self.navigationController?.pushViewController(ProfileController(), animated: true)
            case 1:
                break // go to qr code
            default:
                break
            }
        case 1:
            switch indexPath.row {
            case 1:
                break // go to add money
            default:
                break
            }

        case 2:
            switch indexPath.row {
            case 0:
                // passphrase backup
                self.navigationController?.pushViewController(BackupPhraseEnableController(), animated: true)
            case 1:
                break // trusted frieds
            default:
                break
            }

        case 3:
            switch indexPath.row {
            case 0:
                break // change currency
            case 2:
                // go sign out
                self.handleSignOut()
            default:
                break
            }

        default:
            break
        }
    }

    open override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.performAction(for: indexPath)
    }

    open override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == 2 {
            let view = SettingsSectionHeader(title: "Security", error: "Your account is at risk")
            view.setErrorHidden(self.didVerifyBackupPhrase, animated: false)

            return view
        }

        return super.tableView(tableView, viewForHeaderInSection: section)
    }
}
