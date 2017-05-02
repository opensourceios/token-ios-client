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
import EtherealCereal
import HDWallet

/// An EtherealCereal wrapper. Generates the address and public key for a given private key. Signs messages.
public class Cereal: NSObject {

    static var shared: Cereal = Cereal()

    let entropyByteCount = 16

    lazy var cereal: EtherealCereal = {
        // Base path is m/44'/60'/0'/0/, we use m/44'/60'/0'/0/0 as the id address.
        // If we add support for multiple addresses, we just move on to the next one, m/44'/60'/0'/0/1, m/44'/60'/0'/0/2 and so on.
        let keychain = self.mnemonic.keychain.derivedKeychain(withPath: "m/44'/60'/0'/0/0")
        let privateKey = keychain.key.privateKey.hexadecimalString()

        return EtherealCereal(privateKey: privateKey)
    }()

    var mnemonic: BTCMnemonic

    private static let collectionKey = "cerealPrivateKey"

    public var address: String {
        return self.cereal.address
    }

    public var legacyAddress: String {
        let keychain = self.mnemonic.keychain.derivedKeychain(withPath: "0'/1/0")
        let privateKey = keychain.key.privateKey.hexadecimalString()

        return EtherealCereal(privateKey: privateKey).address
    }

    // restore from words
    public init?(words: [String]) {
        guard let mnemonic = BTCMnemonic(words: words, password: nil, wordListType: .english) else { return nil }
        self.mnemonic = mnemonic

        Yap.sharedInstance.insert(object: self.mnemonic.words.joined(separator: " "), for: Cereal.collectionKey)
    }

    // restore from local user or create new
    public override init() {
        if let words = Yap.sharedInstance.retrieveObject(for: Cereal.collectionKey) as? String {
            self.mnemonic = BTCMnemonic(words: words.components(separatedBy: " "), password: nil, wordListType: .english)!
        } else {
            var entropy = Data(count: self.entropyByteCount)
            // This creates the private key inside a block, result is of internal type ResultType.
            // We just need to check if it's 0 to ensure that there were no errors.
            let result = entropy.withUnsafeMutableBytes { mutableBytes in
                SecRandomCopyBytes(kSecRandomDefault, entropy.count, mutableBytes)
            }
            guard result == 0 else { fatalError("Failed to randomly generate and copy bytes for entropy generation. SecRandomCopyBytes error code: (\(result)).") }

            self.mnemonic = BTCMnemonic(entropy: entropy, password: nil, wordListType: .english)!

            Yap.sharedInstance.insert(object: self.mnemonic.words.joined(separator: " "), for: Cereal.collectionKey)
        }
    }

    public func sign(message: String) -> String {
        return self.cereal.sign(message: message)
    }

    public func sign(hex: String) -> String {
        return self.cereal.sign(hex: hex)
    }

    public func sha3(string: String) -> String {
        return self.cereal.sha3(string: string)
    }

    public func sha3(data: Data) -> String {
        return self.cereal.sha3(data: data)
    }
}
