//
//  StationsViewController.swift
//  SwiftRadio
//
//  Created by Fethi El Hassasna on 2023-06-24.
//  Copyright © 2023 matthewfecher.com. All rights reserved.
//

import UIKit
import Combine

protocol StationsViewControllerDelegate: AnyObject {
    func pushNowPlayingController(_ stationsViewController: StationsViewController, newStation: Bool)
    func didTapInfoButton(_ stationsViewController: StationsViewController)
}

class StationsViewController: BaseController, Handoffable {
    
    // MARK: - Delegate
    weak var delegate: StationsViewControllerDelegate?
    
    // MARK: - Properties
    private let player = RadioPlayer.shared
    private let manager = StationsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - UI
    
    private lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        return refreshControl
    }()
    
    private let searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = true
        return controller
    }()
    
    private static let rowHeight: CGFloat = 140

    /// Two columns in a regular-width environment (the iPhone Duo's inner display, large
    /// phones in landscape), one otherwise. Apple's Duo guidance: use the extra width to show
    /// more rather than scaling text up, and prefer an even column count so the fold
    /// falls between columns.
    private static func columnCount(for traits: UITraitCollection) -> Int {
        traits.horizontalSizeClass == .regular ? 2 : 1
    }

    /// Space between the two columns.
    private static let columnGap: CGFloat = 12

    /// Below this, a column can't hold a station card, so the list stays single-column.
    private static let minimumColumnWidth: CGFloat = 200

    /// Where the two columns meet and how far in they start, in the collection view's
    /// coordinates.
    private struct ColumnSplit {
        var x: CGFloat
        var leftEdge: CGFloat
        var rightEdge: CGFloat
    }

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            let columns = Self.columnCount(for: environment.traitCollection)
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                   heightDimension: .absolute(Self.rowHeight))
            // The split comes from the size being laid out, not one cached in
            // viewDidLayoutSubviews: the collection view sits in a stack view, so at that
            // point it can still have its old (or initial, near-zero) width.
            let width = environment.container.contentSize.width
            guard columns == 2, let self = self,
                  let split = self.columnSplit(forWidth: width) else {
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                return NSCollectionLayoutSection(group: .horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 1))
            }
            // Frames are in full-width coordinates (no automatic safe-area inset), so the
            // gap between the columns can sit exactly on the split.
            let height = Self.rowHeight
            let left = CGRect(x: split.leftEdge, y: 0, width: split.x - Self.columnGap / 2 - split.leftEdge, height: height)
            let rightX = split.x + Self.columnGap / 2
            let right = CGRect(x: rightX, y: 0, width: split.rightEdge - rightX, height: height)
            let group = NSCollectionLayoutGroup.custom(layoutSize: groupSize) { _ in
                [NSCollectionLayoutGroupCustomItem(frame: left), NSCollectionLayoutGroupCustomItem(frame: right)]
            }
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsetsReference = .none
            return section
        }
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.register(StationCell.self, forCellWithReuseIdentifier: StationCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    /// Shown in place of the list until stations arrive.
    private let loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "Loading Stations..."
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = UIColor(white: 0.85, alpha: 1)
        label.textAlignment = .center
        return label
    }()
    
    private let nowPlayingView: NowPlayingView = {
        return NowPlayingView()
    }()
    
    override func loadView() {
        super.loadView()
        setupViews()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.prefersLargeTitles = true
        
        // NavigationBar items
        // Same About screen as the info button on Now Playing
        let infoItem = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(handleInfoTap))
        infoItem.accessibilityLabel = "About RadioSpiral"
        navigationItem.leftBarButtonItem = infoItem
        
        // Setup Player
        RadioPlayer.shared.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.startNowPlayingAnimation(self.player.isPlaying)
            }
            .store(in: &cancellables)
        manager.addObserver(self)

        // Keep the bottom bar's track info current while the station plays
        StationMetadataManager.shared.$currentMetadata
            .receive(on: DispatchQueue.main)
            .sink { [weak self] metadata in
                guard let self = self, let station = self.manager.currentStation else { return }
                self.updateNowPlayingButton(station: station, metadata: metadata)
            }
            .store(in: &cancellables)
        
        // Setup Handoff User Activity
        setupHandoffUserActivity()
        
        // Setup Search Bar
        setupSearchController()
        
        // Row shading depends on the column count, which changes with the size class.
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _: UITraitCollection) in
            self.collectionView.reloadData()
        }

        // Now Playing View
        nowPlayingView.tapHandler = { [weak self] in
            self?.nowPlayingBarButtonPressed()
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // Column edges follow the safe area, which can change without a size change.
        collectionView.collectionViewLayout.invalidateLayout()
    }

    /// Wide inner display: the gap sits on the fold (reported even while the device lies
    /// flat, via includeInactive), and each column stops at its own safe-area edge, so the
    /// side control strip narrows only its column.
    /// Otherwise (tall inner display, where the fold runs across the columns, or no fold):
    /// equal columns centered on the screen, with the larger side inset used on both sides.
    /// Nil when the width is too narrow for two usable columns.
    private func columnSplit(forWidth width: CGFloat) -> ColumnSplit? {
        let height = collectionView.bounds.height
        let safe = collectionView.safeAreaInsets
        var split: ColumnSplit
        if #available(iOS 27.1, *), width > height,
           let fold = collectionView.reservedRegions(kind: .division, options: .includeInactive).first {
            split = ColumnSplit(x: fold.frame.midX, leftEdge: safe.left, rightEdge: width - safe.right)
        } else {
            let inset = max(safe.left, safe.right)
            split = ColumnSplit(x: width / 2, leftEdge: inset, rightEdge: width - inset)
        }
        let narrowest = min(split.x - split.leftEdge, split.rightEdge - split.x) - Self.columnGap / 2
        return narrowest >= Self.minimumColumnWidth ? split : nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(false)
        title = "RadioSpiral streams"
        // A large title can't wrap, so the test-server label goes on its own line above it
        navigationItem.prompt = StationServer.current == .test ? "TEST SERVER" : nil
        showNowPlayingIfOnlyStation()
    }

    /// With a single station there's nothing to choose, so go straight to Now Playing.
    func showNowPlayingIfOnlyStation() {
        guard manager.stations.count == 1 else { return }
        pushNowPlayingController(with: manager.stations[0])
    }
    
    @objc func refresh(sender: AnyObject) {
        // Pull to Refresh
        manager.fetch()
        
        // Wait 2 seconds then refresh screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshControl.endRefreshing()
            self?.view.setNeedsDisplay()
        }
    }
    
    // Reset all properties to default
    private func resetCurrentStation() {
        nowPlayingView.reset()
        navigationItem.rightBarButtonItem = nil
    }
    
    // Update the now playing button title
    private func updateNowPlayingButton(station: RadioStation?, metadata: UnifiedMetadata? = StationMetadataManager.shared.getCurrentMetadata()) {
        
        guard let station = station else {
            print("no station, resetting")
            nowPlayingView.reset()
            return
        }
        
        var playingTitle: String?
        
        if let metadata, !metadata.trackName.isEmpty && !metadata.artistName.isEmpty {
            playingTitle = "\(metadata.trackName) + \(metadata.artistName)"
        }
        
        nowPlayingView.update(with: playingTitle, subtitle: station.name)
        createNowPlayingBarButton()
    }
    
    func startNowPlayingAnimation(_ animate: Bool) {
        animate ? nowPlayingView.startAnimating() : nowPlayingView.stopAnimating()
    }
    
    private func createNowPlayingBarButton() {
        guard navigationItem.rightBarButtonItem == nil else { return }
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "btn-nowPlaying"), style: .plain, target: self, action: #selector(nowPlayingBarButtonPressed))
    }
    
    @objc func nowPlayingBarButtonPressed() {
        pushNowPlayingController()
    }
    
    @objc func handleInfoTap() {
        delegate?.didTapInfoButton(self)
    }

    func pushNowPlayingController(with station: RadioStation? = nil) {
        title = ""
        
        let newStation: Bool
        
        if let station = station {
            // User clicked on row, load/reset station
            newStation = station != manager.currentStation
            if newStation {
                manager.set(station: station)
            }
        } else {
            // User clicked on Now Playing button
            newStation = false
        }
        
        delegate?.pushNowPlayingController(self, newStation: newStation)
    }
    
    override func setupViews() {
        super.setupViews()
        
        let stackView = UIStackView(arrangedSubviews: [collectionView, nowPlayingView])
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        collectionView.refreshControl = refreshControl
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        ])
    }
}

// MARK: - UICollectionViewDataSource

extension StationsViewController: UICollectionViewDataSource {
    
    private var displayedStations: [RadioStation] {
        searchController.isActive ? manager.searchedStations : manager.stations
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView.backgroundView = manager.stations.isEmpty ? loadingLabel : nil
        return displayedStations.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StationCell.reuseIdentifier, for: indexPath) as! StationCell
        
        // alternate background color by row
        let row = indexPath.item / Self.columnCount(for: collectionView.traitCollection)
        cell.backgroundColor = (row % 2 == 0) ? .clear : .black.withAlphaComponent(0.2)
        
        cell.configureStationCell(station: displayedStations[indexPath.item])
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension StationsViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        pushNowPlayingController(with: displayedStations[indexPath.item])
    }
}

// MARK: - UISearchControllerDelegate / Setup

extension StationsViewController: UISearchResultsUpdating {
    
    func setupSearchController() {
        guard Config.searchable else { return }
        
        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
    }
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let filter = searchController.searchBar.text else { return }
        manager.updateSearch(with: filter)
        collectionView.reloadData()
    }
}

extension StationsViewController: StationsManagerObserver {
    
    func stationsManager(_ manager: StationsManager, stationsDidUpdate stations: [RadioStation]) {
        collectionView.reloadData()
    }
    
    func stationsManager(_ manager: StationsManager, stationDidChange station: RadioStation?) {
        guard let station = station else {
            resetCurrentStation()
            return
        }
        
        updateNowPlayingButton(station: station)
    }
}
