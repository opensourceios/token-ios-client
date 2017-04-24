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

class BrowseController: SearchableCollectionController {
    static let cellHeight = CGFloat(220)
    static let cellWidth = CGFloat(90)

//    lazy var recommendedCollectionView: UICollectionView = {
//        let layout = UICollectionViewFlowLayout()
//        layout.scrollDirection = .horizontal
//        layout.itemSize = CGSize(width: BrowseController.cellWidth, height: BrowseController.cellHeight)
//        layout.sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
//        layout.minimumLineSpacing = 15
//
//        let view = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
//        view.translatesAutoresizingMaskIntoConstraints = false
//        view.showsHorizontalScrollIndicator = false
//        view.showsVerticalScrollIndicator = false
//
//        return view
//    }()
//
//    lazy var searchResultsView: SearchResultsView = {
//        let view = SearchResultsView(withAutoLayout: true)
//        view.selectionDelegate = self
//
//        return view
//    }()
//
//    fileprivate lazy var searchController: UISearchController = {
//        let searchController = UISearchController(searchResultsController: nil)
//        searchController.dimsBackgroundDuringPresentation = false
//        searchController.hidesNavigationBarDuringPresentation = false
//        searchController.delegate = self
//
//        searchController.searchBar.sizeToFit()
//        searchController.searchBar.tintColor = Theme.tintColor
//        searchController.searchBar.delegate = self
//
//        return searchController
//    }()

    var recommendedApps = [TokenContact]() {
        didSet {
            self.collectionView.reloadData()
        }
    }

    var appsAPIClient: AppsAPIClient

    init(appsAPIClient: AppsAPIClient = .shared) {
        self.appsAPIClient = appsAPIClient

        super.init(nibName: nil, bundle: nil)

        self.loadViewIfNeeded()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        self.collectionView.showsVerticalScrollIndicator = true
        self.collectionView.alwaysBounceVertical = true

        self.collectionView.register(AppCell.self)

        self.title = "Browse"
        self.appsAPIClient.getFeaturedApps { apps, error in
            if let error = error {
                let alertController = UIAlertController.errorAlert(error as NSError)
                self.present(alertController, animated: true, completion: nil)
            }

            var appss = apps
            appss.append(contentsOf: apps)
            appss.append(contentsOf: apps)
            appss.append(contentsOf: apps)
            self.recommendedApps = appss
        }
    }

//    func showSearchResultsView(shouldShow: Bool) {
//        self.containerView.isHidden = shouldShow
//        self.searchResultsView.isHidden = !shouldShow
//    }

    func reload(searchText: String) {
        self.appsAPIClient.search(searchText) { apps, error in
            if let error = error {
                let alertController = UIAlertController.errorAlert(error as NSError)
                self.present(alertController, animated: true, completion: nil)
            }

//            self.searchResultsView.results = apps
        }
    }
}

extension BrowseController {

    override func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        return self.recommendedApps.count
    }

    public override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeue(AppCell.self, for: indexPath)

        let app = self.recommendedApps[indexPath.row]
        cell.app = app

        return cell
    }

    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let app = self.recommendedApps[indexPath.row]
        let appController = AppController(app: app)
        self.navigationController?.pushViewController(appController, animated: true)
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate _: Bool) {
        let adjustedContentOffset = scrollView.contentOffset.y + scrollView.contentInset.top

        if adjustedContentOffset <= SearchBarView.height / 2 {
            scrollView.setContentOffset(CGPoint(x: 0.0, y: -scrollView.contentInset.top), animated: true)
        } else if adjustedContentOffset > SearchBarView.height / 2 && adjustedContentOffset < SearchBarView.height {
            scrollView.setContentOffset(CGPoint(x: 0.0, y: SearchBarView.height - scrollView.contentInset.top), animated: true)
        }
    }
}

extension BrowseController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 100, height: 220)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 10
    }
}

extension BrowseController: UISearchBarDelegate {
    func searchBar(_: UISearchBar, textDidChange searchText: String) {
//        if searchText.length == 0 {
//            self.searchResultsView.results = [TokenContact]()
//        }
//        self.showSearchResultsView(shouldShow: searchText.length > 0)

        // Throttles search to delay performing a search while the user is typing.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(reload(searchText:)), object: searchText)
        self.perform(#selector(reload(searchText:)), with: searchText, afterDelay: 0.5)
    }
}

extension BrowseController: UISearchControllerDelegate {

    func didDismissSearchController(_: UISearchController) {
//        self.showSearchResultsView(shouldShow: false)
    }
}

extension BrowseController: SearchResultsViewDelegate {

    func searchResultsView(_: SearchResultsView, didTapApp app: TokenContact) {
        let appController = AppController(app: app)
        self.navigationController?.pushViewController(appController, animated: true)
    }
}
