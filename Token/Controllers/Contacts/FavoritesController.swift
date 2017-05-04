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
import SweetFoundation
import SweetSwift

public extension Array {
    public var any: Element? {
        return self[Int(arc4random_uniform(UInt32(self.count)))] as Element
    }
}

open class FavoritesController: SweetTableController {

    let selectedContactKey = "SelectedContact"

    lazy var mappings: YapDatabaseViewMappings = {
        let mappings = YapDatabaseViewMappings(groups: [TokenUser.collectionKey], view: TokenUser.viewExtensionName)
        mappings.setIsReversed(true, forGroup: TokenUser.collectionKey)

        return mappings
    }()

    lazy var uiDatabaseConnection: YapDatabaseConnection = {
        let database = Yap.sharedInstance.database
        let dbConnection = database.newConnection()
        dbConnection.beginLongLivedReadTransaction()

        return dbConnection
    }()

    fileprivate var chatAPIClient: ChatAPIClient {
        return ChatAPIClient.shared
    }

    fileprivate var idAPIClient: IDAPIClient {
        return IDAPIClient.shared
    }

    var searchContacts = [TokenUser]()

    lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.dimsBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false

        controller.searchBar.delegate = self
        controller.searchBar.barTintColor = Theme.viewBackgroundColor
        controller.searchBar.tintColor = Theme.tintColor
        controller.searchBar.searchBarStyle = .minimal

        controller.searchBar.layer.borderWidth = 1.0 / UIScreen.main.scale
        controller.searchBar.layer.borderColor = Theme.borderColor.cgColor

        let searchField = controller.searchBar.value(forKey: "searchField") as? UITextField
        searchField?.backgroundColor = Theme.inputFieldBackgroundColor

        return controller
    }()

    public init() {
        super.init(style: .plain)

        self.registerTokenContactsDatabaseView()

        self.uiDatabaseConnection.asyncRead { transaction in
            self.mappings.update(with: transaction)
        }

        self.title = "Favorites"

        self.registerNotifications()
    }

    public required init?(coder _: NSCoder) {
        fatalError("")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(ContactCell.self)
        self.tableView.register(ChatCell.self)

        self.tableView.dataSource = self
        self.tableView.delegate = self

        self.tableView.backgroundColor = Theme.viewBackgroundColor
        self.tableView.separatorStyle = .none
        self.tableView.tableHeaderView = self.searchController.searchBar

        self.definesPresentationContext = true

        let appearance = UIButton.appearance(whenContainedInInstancesOf: [UISearchBar.self])
        appearance.setTitleColor(Theme.greyTextColor, for: .normal)

        self.displayContacts()

        if let address = UserDefaults.standard.string(forKey: self.selectedContactKey) {
            // This doesn't restore a contact if they are not our contact, but a search result
            DispatchQueue.main.asyncAfter(seconds: 0.0) {
                guard let contact = self.contact(with: address) else { return }

                if contact.isApp {
                    let appController = AppController(app: contact)
                    self.navigationController?.pushViewController(appController, animated: false)
                } else {
                    let contactController = ContactController(contact: contact)
                    self.navigationController?.pushViewController(contactController, animated: false)
                }
            }
        }
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.navigationItem.rightBarButtonItem = nil
    }

    func contactSorting() -> YapDatabaseViewSorting {
        let viewSorting = YapDatabaseViewSorting.withObjectBlock { (_, _, _, _, object1, _, _, object2) -> ComparisonResult in
            guard let data1 = object1 as? Data else { fatalError() }
            guard let data2 = object2 as? Data else { fatalError() }

            let contact1 = TokenUser.user(with: data1)
            let contact2 = TokenUser.user(with: data2)

            return contact1!.username.compare(contact2!.username)
        }

        return viewSorting
    }

    @discardableResult
    func registerTokenContactsDatabaseView() -> Bool {
        // Check if it's already registered.
        guard Yap.sharedInstance.database.registeredExtension(TokenUser.viewExtensionName) == nil else { return true }

        let viewGrouping = YapDatabaseViewGrouping.withObjectBlock { (_, _, _, object) -> String? in
            if let _ = object as? Data {
                return TokenUser.collectionKey
            }

            return nil
        }

        let viewSorting = self.contactSorting()

        let options = YapDatabaseViewOptions()
        options.isPersistent = false
        options.allowedCollections = YapWhitelistBlacklist(whitelist: Set([TokenUser.collectionKey]))

        let databaseView = YapDatabaseView(grouping: viewGrouping, sorting: viewSorting, versionTag: "1", options: options)

        return Yap.sharedInstance.database.register(databaseView, withName: TokenUser.viewExtensionName)
    }

    func displayContacts() {
        self.searchController.isActive = false
        self.tableView.reloadData()
    }

    func registerNotifications() {
        let notificationController = NotificationCenter.default
        notificationController.addObserver(self, selector: #selector(yapDatabaseDidChange(notification:)), name: .YapDatabaseModified, object: nil)
    }

    func yapDatabaseDidChange(notification _: NSNotification) {
        let notifications = self.uiDatabaseConnection.beginLongLivedReadTransaction()

        // If changes do not affect current view, update and return without updating collection view
        let viewConnection = self.uiDatabaseConnection.ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewConnection
        let hasChangesForCurrentView = viewConnection.hasChanges(for: notifications)
        if !hasChangesForCurrentView {
            self.uiDatabaseConnection.read { transaction in
                self.mappings.update(with: transaction)
            }

            // unlike most yap-connected views, this one is always in the hierarchy, so we reload data if we don't need to live-update
            self.tableView.reloadData()

            return
        }

        var messageRowChanges = NSArray()
        var sectionChanges = NSArray()

        viewConnection.getSectionChanges(&sectionChanges, rowChanges: &messageRowChanges, for: notifications, with: self.mappings)

        if sectionChanges.count == 0 && messageRowChanges.count == 0 {
            return
        }

        guard !self.searchController.isActive else { return }

        self.tableView.beginUpdates()

        for rowChange in messageRowChanges as! [YapDatabaseViewRowChange] {

            switch rowChange.type {
            case .delete:
                self.tableView.deleteRows(at: [rowChange.indexPath], with: .left)
            case .insert:
                self.updateContactIfNeeded(at: rowChange.newIndexPath)
                self.tableView.insertRows(at: [rowChange.newIndexPath], with: .right)
            case .move:
                self.tableView.deleteRows(at: [rowChange.indexPath], with: .left)
                self.tableView.insertRows(at: [rowChange.newIndexPath], with: .right)
            case .update:
                self.tableView.reloadRows(at: [rowChange.indexPath], with: .middle)
            }
        }

        self.tableView.endUpdates()
    }

    func updateContactIfNeeded(at indexPath: IndexPath) {
        let contact = self.contact(at: indexPath)
        let address = contact.address

        print("Updating contact infor for address: \(address).")

        self.idAPIClient.findContact(name: address) { contact in
            if let contact = contact {
                print("Added contact info for \(contact.username)")

                self.tableView.beginUpdates()
                self.tableView.reloadRows(at: [indexPath], with: .automatic)
                self.tableView.endUpdates()
            }
        }
    }

    func contact(at indexPath: IndexPath) -> TokenUser {
        var contact: TokenUser?

        self.uiDatabaseConnection.read { transaction in
            guard let dbExtension: YapDatabaseViewTransaction = transaction.extension(TokenUser.viewExtensionName) as? YapDatabaseViewTransaction else { fatalError() }

            guard let data = dbExtension.object(at: indexPath, with: self.mappings) as? Data else { fatalError() }

            contact = TokenUser.user(with: data, shouldUpdate: false)
        }

        return contact!
    }

    func contact(with address: String) -> TokenUser? {
        var contact: TokenUser?

        self.uiDatabaseConnection.read { transaction in
            if let data = transaction.object(forKey: address, inCollection: TokenUser.collectionKey) as? Data {
                contact = TokenUser.user(with: data)
            }
        }

        return contact
    }
}

extension FavoritesController: UITableViewDataSource {

    open func numberOfSections(in _: UITableView) -> Int {
        if self.searchController.isActive {
            return 1
        }

        return Int(self.mappings.numberOfSections())
    }

    open func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.searchController.isActive {
            return self.searchContacts.count
        }

        return Int(self.mappings.numberOfItems(inSection: UInt(section)))
    }

    open func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeue(ContactCell.self, for: indexPath)

        if self.searchController.isActive {
            cell.contact = self.searchContacts[indexPath.row]
        } else {
            cell.contact = self.contact(at: indexPath)
        }

        return cell
    }
}

extension FavoritesController: UITableViewDelegate {

    public func tableView(_: UITableView, heightForRowAt _: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }

    public func tableView(_: UITableView, estimatedHeightForRowAt _: IndexPath) -> CGFloat {
        return UITableViewAutomaticDimension
    }

    public func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.searchController.searchBar.resignFirstResponder()

        let contact = self.searchController.isActive ? self.searchContacts[indexPath.row] : self.contact(at: indexPath)

        if contact.isApp {
            let appController = AppController(app: contact)
            self.navigationController?.pushViewController(appController, animated: true)
        } else {
            let contactController = ContactController(contact: contact)
            self.navigationController?.pushViewController(contactController, animated: true)
        }

        UserDefaults.standard.setValue(contact.address, forKey: self.selectedContactKey)
    }
}

extension FavoritesController: UISearchBarDelegate {

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        self.displayContacts()
    }
}

extension FavoritesController: UISearchResultsUpdating {

    public func updateSearchResults(for searchController: UISearchController) {
        guard let text = searchController.searchBar.text else { return }

        if text.length == 0 {
            self.searchContacts = []
            self.tableView.reloadData()
        } else {
            self.idAPIClient.searchContacts(name: text) { contacts in
                self.searchContacts = contacts
                self.tableView.reloadData()
            }
        }
    }
}
