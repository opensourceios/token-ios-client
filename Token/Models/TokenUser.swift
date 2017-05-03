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

import Foundation
import SweetSwift
import KeychainSwift

public protocol JSONDataSerialization {
    var JSONData: Data { get }
}

extension Notification.Name {
    public static let CurrentUserDidUpdateAvatarNotification = Notification.Name(rawValue: "CurrentUserDidUpdateAvatarNotification")
    public static let TokenContactDidUpdateAvatarNotification = Notification.Name(rawValue: "TokenContactDidUpdateAvatarNotification")
}

public class TokenUser: NSObject, JSONDataSerialization, NSCoding {

    struct Constants {
        static let name = "name"
        static let username = "username"
        static let address = "token_id"
        static let paymentAddress = "payment_address"
        static let location = "location"
        static let about = "about"
        static let avatar = "avatar"
        static let avatarDataHex = "avatarDataHex"
        static let isApp = "is_app"
    }

    static let didUpdateContactInfoNotification = Notification.Name(rawValue: "DidUpdateContactInfo")
    static let viewExtensionName = "TokenContactsDatabaseViewExtensionName"
    static let collectionKey: String = "TokenContacts"

    private static let storedUserKey = "StoredUser"

    private static let storedContactKey = "storedContactKey"

    var category = ""

    var balance = NSDecimalNumber.zero

    private(set) var name = ""

    var displayUsername: String {
        return "@\(self.username)"
    }
    private(set) var username = ""
    private(set) var about = ""
    private(set) var location = ""
    private(set) var avatarPath = ""
    private(set) var address = ""
    private(set) var paymentAddress = ""
    private(set) var isApp: Bool = false

    private(set) var avatar: UIImage? {
        didSet {
            self.postAvatarUpdateNotification()
        }
    }

    private static var _current: TokenUser?
    static var current: TokenUser? {
        get {
            if let userData = (Yap.sharedInstance.retrieveObject(for: TokenUser.storedUserKey) as? Data), self._current == nil,
                let deserialised = (try? JSONSerialization.jsonObject(with: userData, options: [])),
                let json = deserialised as? [String: Any] {

                self._current = TokenUser(json: json)
            }

            return self._current
        }
        set {
            guard let newPaymentAddress = newValue?.paymentAddress, Cereal.shared.paymentAddress == newPaymentAddress else {
                fatalError("Tried to set contact as current user.")
            }

            newValue?.update()

            if let user = newValue {
                let keychain = KeychainSwift()
                keychain.set(user.paymentAddress, forKey: "CurrentUserPaymentAddress")
                user.saveIfNeeded()
            }

            self._current = newValue
        }
    }

    var isBlocked: Bool {
        let blockingManager = OWSBlockingManager.shared()

        return blockingManager.blockedPhoneNumbers().contains(self.address)
    }

    var isCurrentUser: Bool {
        return self.address == Cereal.shared.address
    }

    public var JSONData: Data {
        return try! JSONSerialization.data(withJSONObject: self.asDict, options: [])
    }

    init(json: [String: Any], shouldUpdate: Bool = true) {
        super.init()

        self.address = json[Constants.address] as! String
        self.paymentAddress = (json[Constants.paymentAddress] as? String) ?? (json[Constants.address] as! String)
        self.username = json[Constants.username] as! String
        self.name = json[Constants.name] as? String ?? ""
        self.location = json[Constants.location] as? String ?? ""
        self.about = json[Constants.about] as? String ?? ""
        self.avatarPath = json[Constants.avatar] as? String ?? ""

        if let avatarDataHex = (json[Constants.avatarDataHex] as? String), avatarDataHex.length > 0, let hexData = avatarDataHex.hexadecimalData {
            self.avatar = UIImage(data: hexData)
        }

        if self.avatarPath.length > 0 {
            if self.isApp {
                AppsAPIClient.shared.downloadImage(for: self) { image in
                    self.avatar = image
                }
            } else {
                IDAPIClient.shared.downloadAvatar(path: self.avatarPath) { image in
                    self.avatar = image
                }
            }
        }

        if shouldUpdate {
            self.update()
        }

        self.setupNotifications()
    }

    static func name(from username: String) -> String {
        return username.hasPrefix("@") ? username.substring(from: username.index(after: username.startIndex)) : username
    }

    static func user(with data: Data, shouldUpdate: Bool = true) -> TokenUser? {
        guard let deserialised = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard let json = deserialised as? [String: Any] else { return nil }

        return TokenUser(json: json, shouldUpdate: shouldUpdate)
    }

    func update(avatar: UIImage, avatarPath: String) {
        self.avatarPath = avatarPath
        self.avatar = avatar
        saveIfNeeded()
    }

    func update(username: String? = nil, name: String? = nil, about: String? = nil, location: String? = nil) {
        self.username = username ?? self.username
        self.name = name ?? self.name
        self.about = about ?? self.about
        self.location = location ?? self.location

        self.saveIfNeeded()
    }

    public required convenience init?(coder aDecoder: NSCoder) {
        guard let jsonData = aDecoder.decodeObject(forKey: "jsonData") as? Data else { return nil }
        guard let deserialised = try? JSONSerialization.jsonObject(with: jsonData, options: []), let json = deserialised as? [String: Any] else { return nil }

        self.init(json: json)
    }

    @objc(encodeWithCoder:) public func encode(with aCoder: NSCoder) {
        aCoder.encode(self.JSONData, forKey: "jsonData")
    }

    public override var description: String {
        return "<User: address: \(self.address), payment address: \(self.paymentAddress), name: \(self.name), username: \(username)>"
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.updateIfNeeded), name: IDAPIClient.didFetchContactInfoNotification, object: nil)
    }

    @objc private func updateIfNeeded(_ notification: Notification) {
        guard let tokenContact = notification.object as? TokenUser else { return }
        guard tokenContact.address == self.address else { return }

        if self.name == tokenContact.name && self.username == tokenContact.username && self.location == tokenContact.location && self.about == tokenContact.about {
            return
        }

        self.update(username: tokenContact.username, name: tokenContact.name, about: tokenContact.about, location: tokenContact.location)
    }

    private func saveIfNeeded() {
        if self.isCurrentUser {
            Yap.sharedInstance.insert(object: self.JSONData, for: TokenUser.storedUserKey)
        } else {
            Yap.sharedInstance.insert(object: self.JSONData, for: TokenUser.storedContactKey)
        }
    }

    private func postAvatarUpdateNotification() {
        if self.isCurrentUser {
            NotificationCenter.default.post(name: .CurrentUserDidUpdateAvatarNotification, object: self)
        } else {
            NotificationCenter.default.post(name: .TokenContactDidUpdateAvatarNotification, object: self)
        }
    }

    var asDict: [String: Any] {
        var imageDataString = ""
        if let image = self.avatar, let data = (UIImagePNGRepresentation(image) ?? UIImageJPEGRepresentation(image, 1.0)) {
            imageDataString = data.hexadecimalString
        }

        return [
            Constants.address: self.address,
            Constants.paymentAddress: self.paymentAddress,
            Constants.username: self.username,
            Constants.about: self.about,
            Constants.location: self.location,
            Constants.name: self.name,
            Constants.avatar: self.avatarPath,
            Constants.avatarDataHex: imageDataString,
            Constants.isApp: self.isApp,
        ]
    }
}
