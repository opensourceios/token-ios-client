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
import AwesomeCache
import Teapot
import UIKit

public class AppsAPIClient: NSObject, CacheExpiryDefault {
    static let shared: AppsAPIClient = AppsAPIClient()

    private var teapot: Teapot

    private var imageCache = try! Cache<UIImage>(name: "appImageCache")

    override init() {
        self.teapot = Teapot(baseURL: URL(string: TokenDirectoryServiceBaseURLPath)!)
    }

    func getFeaturedApps(completion: @escaping (_ apps: [TokenUser], _ error: Error?) -> Void) {
        self.teapot.get("/v1/apps/featured") { (result: NetworkResult) in
            switch result {
            case .success(let json, let response):
                print(response)
                guard let json = json?.dictionary else { fatalError("No apps json!") }

                let appsJSON = json["results"] as! [[String: Any]]
                let apps = appsJSON.map { json -> TokenUser in
                    let app = TokenUser(json: json)

                    return app
                }

                completion(apps, nil)
            case .failure(let json, let response, let error):
                print(json ?? "")
                print(response)
                completion([TokenUser](), error)
            }
        }
    }

    func downloadImage(for app: TokenUser, completion: @escaping (_ image: UIImage?) -> Void) {
        guard let pathURL = URL(string: app.avatarPath) else { return }
        self.imageCache.setObject(forKey: app.avatarPath, cacheBlock: { success, failure in
            Teapot(baseURL: pathURL).get { (result: NetworkImageResult) in
                switch result {
                case .success(let image, let response):
                    print(response)
                    success(image, self.cacheExpiry)
                case .failure(let response, let error):
                    print(response)
                    print(error)
                    failure(error as NSError)
                }
            }
        }) { image, _, _ in
            completion(image)
        }
    }

    func search(_ searchTerm: String, completion: @escaping (_ apps: [TokenUser], _ error: Error?) -> Void) {
        guard searchTerm.length > 0 else {
            completion([TokenUser](), nil)
            return
        }

        self.teapot.get("/v1/search/apps/?query=\(searchTerm)") { (result: NetworkResult) in
            switch result {
            case .success(let json, _):
                guard let json = json?.dictionary else {
                    completion([], nil)

                    return
                }

                guard let appsJSON = json["results"] as? [[String: Any]] else {
                    completion([TokenUser](), nil)
                    return
                }

                let apps = appsJSON.map { json -> TokenUser in
                    return TokenUser(json: json)
                }

                completion(apps, nil)
            case .failure(_, _, let error):
                completion([TokenUser](), error)
            }
        }
    }
}
