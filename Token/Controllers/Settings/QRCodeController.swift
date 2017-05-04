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
import CoreImage

class QRCodeController: UIViewController {

    static let addUsernameBasePath = "https://app.tokenbrowser.com/add/"

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    lazy var qrCodeImageView: UIImageView = {
        let view = UIImageView(withAutoLayout: true)
        view.set(height: 300)
        view.set(width: 300)

        return view
    }()


    convenience init(for username: String) {
        self.init(nibName: nil, bundle: nil)

        self.title = "My QR Code"

        self.qrCodeImageView.image = UIImage.imageQRCode(for: "\(QRCodeController.addUsernameBasePath)\(username)", resizeRate: 20.0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = Theme.viewBackgroundColor
        self.view.addSubview(self.qrCodeImageView)

        self.qrCodeImageView.set(height: 300)
        self.qrCodeImageView.set(width: 300)
        self.qrCodeImageView.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        self.qrCodeImageView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor).isActive = true
    }
}

extension QRCodeController: UIToolbarDelegate {

    func position(for _: UIBarPositioning) -> UIBarPosition {
        return .topAttached
    }
}
