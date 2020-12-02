//
//  ViewController.swift
//  NaverMapA
//
//  Created by 채훈기 on 2020/11/17.
//

import UIKit
import NMapsMap
import CoreData

class MainViewController: UIViewController {
    
    var mapView: NMFMapView!
    var viewModel: MainViewModel?
    var clusterMarkers = [NMFMarker]()
    var clusterObjects = [Cluster]()
    var prevZoomLevel: Double = 18
    lazy var dataProvider: PlaceProvider = {
        let provider = PlaceProvider.shared
        provider.fetchedResultsController.delegate = self
        return provider
    }()
    
    private lazy var handler = { (overlay: NMFOverlay?) -> Bool in
        if let marker = overlay as? NMFMarker {
            for cluster in self.clusterObjects {
                if cluster.latitude == marker.position.lat && cluster.longitude == marker.position.lng {
                    self.moveCamera(to: cluster)
                    break
                }
            }
        }
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //viewModel = MainViewModel(algorithm: ScaleBasedClustering())
        viewModel = MainViewModel(algorithm: KMeansClustering())
        bindViewModel()
        setupMapView()
        if dataProvider.objectCount == 0 {
            dataProvider.insert(completionHandler: handleBatchOperationCompletion)
        }
    }
    
    func setupMapView() {
        mapView = NMFMapView(frame: view.frame)
        mapView.addCameraDelegate(delegate: self)
        mapView.moveCamera(NMFCameraUpdate(position: NMFCameraPosition(NMGLatLng(lat: 37.5655271, lng: 126.9904267), zoom: 18)))
        view.addSubview(mapView)
    }
    
    func deleteBeforeMarkers() {
        for clusterMarker in self.clusterMarkers {
            clusterMarker.mapView = nil
        }
        self.clusterMarkers.removeAll()
        self.clusterObjects.removeAll()
    }
    
    func configureNewMarkers(afterClusters: [Cluster]) {
        for cluster in afterClusters {
            let lat = cluster.latitude
            let lng = cluster.longitude
            let marker = NMFMarker(position: NMGLatLng(lat: lat, lng: lng))
            marker.iconImage = NMF_MARKER_IMAGE_BLACK
            if cluster.places.count == 1 {
                marker.iconTintColor = .green
            } else {
                marker.iconTintColor = .red
            }
            marker.captionText = "\(cluster.places.count)"
            marker.zIndex = 1
            marker.mapView = self.mapView
            marker.touchHandler = self.handler
            self.clusterMarkers.append(marker)
            self.clusterObjects.append(cluster)
        }
    }
    
    func bindViewModel() {
        if let viewModel = viewModel {
            viewModel.animationMarkers.bind({ (beforeClusters, afterClusters) in
                DispatchQueue.main.async {
                    self.deleteBeforeMarkers()
                    self.markerAnimation(beforeClusters: beforeClusters, afterClusters: afterClusters)
                }
            })
            
            viewModel.markers.bind({ afterClusters in
                DispatchQueue.main.async {
                    self.deleteBeforeMarkers()
                    self.configureNewMarkers(afterClusters: afterClusters)
                }
            })
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let _ = NMFAuthManager.shared().clientId else {
            let okAction = UIAlertAction(title: "OK", style: .destructive) { _ in
                UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
            }
            showAlert(title: "에러", message: "ClientID가 없습니다.", preferredStyle: UIAlertController.Style.alert, action: okAction)
            return
        }
    }
    
    // MARK: - Methods
    
    private func showAlert(title: String?, message: String?, preferredStyle: UIAlertController.Style, action: UIAlertAction) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(action)
        present(alert, animated: false, completion: nil)
    }
    
    private func handleBatchOperationCompletion(error: Error?) {
        if let error = error {
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            showAlert(title: "Executing batch operation error!", message: error.localizedDescription, preferredStyle: .alert, action: okAction)
        } else {
            dataProvider.resetAndRefetch()
        }
    }
    
    private func markerAnimation(beforeClusters: [Cluster], afterClusters: [Cluster]) {
        beforeClusters.forEach { beforeCluster in
            afterClusters.forEach { afterCluster in
                for beforePlace in beforeCluster.places {
                    if afterCluster.placesDictionary[Point(latitude: beforePlace.latitude, longitude: beforePlace.longitude)] == nil {
                        continue
                    }
                    let startPoint = mapView.projection.point(from: NMGLatLng(lat: beforeCluster.latitude, lng: beforeCluster.longitude))
                    let endPoint = mapView.projection.point(from: NMGLatLng(lat: afterCluster.latitude, lng: afterCluster.longitude))
                    let markerColor = (beforeClusters.count > 1) ? UIColor.red : UIColor.green
                    startMarkerAnimation(startPoint: startPoint, endPoint: endPoint, markerColor: markerColor, afterClusters: afterClusters)
                    break
                }
            }
        }
    }
    
    private func moveCamera(to cluster: Cluster) {
        var minLatitude = Double.greatestFiniteMagnitude
        var maxLatitude = Double.leastNormalMagnitude
        var minLongitude = Double.greatestFiniteMagnitude
        var maxLongitude = Double.leastNormalMagnitude
        for place in cluster.places {
            if minLatitude > place.latitude {
                minLatitude = place.latitude
            }
            if maxLatitude < place.latitude {
                maxLatitude = place.latitude
            }
            if minLongitude > place.longitude {
                minLongitude = place.longitude
            }
            if maxLongitude < place.longitude {
                maxLongitude = place.longitude
            }
        }
        mapView.moveCamera(NMFCameraUpdate(fit: NMGLatLngBounds(southWest: NMGLatLng(lat: minLatitude, lng: maxLongitude), northEast: NMGLatLng(lat: maxLatitude, lng: minLongitude)), padding: 50))
    }
    
    private func startMarkerAnimation(startPoint: CGPoint, endPoint: CGPoint, markerColor: UIColor, afterClusters: [Cluster]) {
        let marker = NMFMarker()
        marker.iconTintColor = markerColor
        let markerView = self.view(with: marker)
        markerView.frame.origin = CGPoint(x: -100, y: -100)
        mapView.addSubview(markerView)
        let markerViewLayer = markerView.layer
        markerViewLayer.anchorPoint = CGPoint(x: 0.5, y: 1)
        DispatchQueue.global().async {
            CATransaction.begin()
            let markerAnimation = CABasicAnimation(keyPath: "position")
            markerAnimation.duration = 0.3
            markerAnimation.fromValue = CGPoint(x: startPoint.x, y: startPoint.y)
            markerAnimation.toValue = CGPoint(x: endPoint.x, y: endPoint.y)
            CATransaction.setCompletionBlock({
                markerView.removeFromSuperview()
                self.configureNewMarkers(afterClusters: afterClusters)
            })
            markerViewLayer.add(markerAnimation, forKey: "position")
            CATransaction.commit()
        }
    }
    
}

extension MainViewController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    }
}
