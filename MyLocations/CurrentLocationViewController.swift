//
//  FirstViewController.swift
//  MyLocations
//
//  Created by Vu Hoang Son on 12/7/17.
//  Copyright © 2017 Vu Hoang Son. All rights reserved.
//

import UIKit
import CoreLocation
import CoreData

class CurrentLocationViewController: UIViewController, CLLocationManagerDelegate {
    
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var latitudeLabel: UILabel!
    @IBOutlet weak var longitudeLabel: UILabel!
    @IBOutlet weak var addressLabel: UILabel!
    @IBOutlet weak var tagButton: UIButton!
    @IBOutlet weak var getButton: UIButton!
    
    let locationManager = CLLocationManager()
    var location: CLLocation?
    var updatingLocation = false
    var lastLocationError: Error?
    
    let geocoder = CLGeocoder()
    var placemark: CLPlacemark?
    var performingReverseGeocoding = false
    var lastGeocodingError: Error?
    
    var timer: Timer?
    var managedObjectContext: NSManagedObjectContext!
    
    @IBAction func getLocation() {
        let auth = CLLocationManager.authorizationStatus()
        if auth == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }
        if auth == .denied || auth == .restricted {
            showLocationServiceAlert()
            return
        }
        if updatingLocation {
            stopLocationManager()
        } else {
            location = nil
            lastLocationError = nil
            placemark = nil
            lastGeocodingError = nil
            startLocationManager()
        }
        updateLabels()
        configureGetButton()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        updateLabels()
        configureGetButton()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "TagLocation" {
            let navigationController = segue.destination as! UINavigationController
            let controller = navigationController.topViewController as! LocationDetailsViewController
            controller.coordinate = location!.coordinate
            controller.placemark = placemark
            controller.managedObjectContext = managedObjectContext
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Did fail with error: \(error)")
        
        if (error as NSError).code == CLError.locationUnknown.rawValue {
            return
        }
        lastLocationError = error
        stopLocationManager()
        updateLabels()
        configureGetButton()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let newLocation = locations.last!
        print("- Did update locations: \(newLocation)")
        //1
        if newLocation.timestamp.timeIntervalSinceNow < -5 {
            return
        }
        //2
        if newLocation.horizontalAccuracy < 0 {
            return
        }
        //new
        var distance = CLLocationDistance(Double.greatestFiniteMagnitude)
        if let location = location {
            distance = newLocation.distance(from: location)
        }
        //3
        if location == nil || location!.horizontalAccuracy > newLocation.horizontalAccuracy {
            location = newLocation
            lastLocationError = nil
            updateLabels()
            //5
            if newLocation.horizontalAccuracy <= locationManager.desiredAccuracy {
                print("*** We are done")
                stopLocationManager()
                configureGetButton()
                //new
                if distance > 0 {
                    performingReverseGeocoding = false
                }
            }
            
            if !performingReverseGeocoding {
                print("*** Going to geocode ")
                performingReverseGeocoding = true
                geocoder.reverseGeocodeLocation(newLocation, completionHandler: { (placemarks, error) in
                    print("*** Found placemarks: \(String(describing: placemarks)), error: \(String(describing: error))")
                    if error == nil, let p = placemarks, !p.isEmpty {
                        self.placemark = p.last
                    } else {
                        self.placemark = nil
                    }
                    self.performingReverseGeocoding = false
                    self.updateLabels()
                })
            }
            //new
            else if distance < 1 {
                let timeInterval = newLocation.timestamp.timeIntervalSince(location!.timestamp)
                if timeInterval > 10 {
                    print("*** Force Done")
                    stopLocationManager()
                    updateLabels()
                    configureGetButton()
                }
            }
        }
    }
    
    func startLocationManager() {
        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.startUpdatingLocation()
            updatingLocation = true
            timer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(didTimeOut), userInfo: nil, repeats: false)
        }
    }
    
    func stopLocationManager() {
        if updatingLocation {
            locationManager.stopUpdatingLocation()
            locationManager.delegate = nil
            updatingLocation = false
            if let timer = timer {
                timer.invalidate()
            }
        }
    }
    
    @objc func didTimeOut() {
        print("***Time out")
        if location == nil {
            stopLocationManager()
            lastLocationError = NSError(domain: "MyLocationErrorDoamin", code: 1, userInfo: nil)
            updateLabels()
            configureGetButton()
        }
    }
    
    func showLocationServiceAlert() {
        let alert = UIAlertController(title: "Location Service Disabled", message: "Please enable service in Settings", preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .default, handler: nil)
        alert.addAction(action)
        present(alert, animated: true, completion: nil)
    }
    
    func updateLabels() {
        if let location = location {
            latitudeLabel.text = String(format: "%.8f", location.coordinate.latitude)
            longitudeLabel.text = String(format: "%.8f", location.coordinate.longitude)
            tagButton.isHidden = false
            messageLabel.text = ""
            if let placemark = placemark {
                addressLabel.text = string(from: placemark)
            } else if performingReverseGeocoding {
                addressLabel.text = "Searching for address..."
            } else if lastGeocodingError != nil {
                addressLabel.text = "Error finding address"
            } else {
                addressLabel.text = "No address found"
            }
        } else {
            latitudeLabel.text = ""
            longitudeLabel.text = ""
            addressLabel.text = ""
            tagButton.isHidden = true
            //
            let statusMess: String
            if let error = lastLocationError as NSError? {
                if error.domain == kCLErrorDomain  && error.code == CLError.denied.rawValue {
                    statusMess = "Location Service Disabled"
                } else {
                    statusMess = "Error getting Location"
                }
            } else if !CLLocationManager.locationServicesEnabled() {
                statusMess = "Location Service Disabled"
            } else if updatingLocation {
                statusMess = "Searching..."
            } else {
                statusMess = "Tap 'Get My Location' to Start"
            }
            messageLabel.text = statusMess
        }
    }
    
    func configureGetButton() {
        if updatingLocation {
            getButton.setTitle("Stop", for: .normal)
        } else {
            getButton.setTitle("Get My Location", for: .normal)
        }
    }
    
    func string(from placemark: CLPlacemark) -> String {
        // 1
        var line1 = ""
        // 2
        if let s = placemark.subThoroughfare {
            line1 += s + " "
        }
        // 3
        if let s = placemark.thoroughfare {
            line1 += s }
        // 4
        var line2 = ""
        if let s = placemark.locality {
            line2 += s + " "
        }
        if let s = placemark.administrativeArea {
            line2 += s + " "
        }
        if let s = placemark.postalCode {
            line2 += s }
        // 5
        return line1 + "\n" + line2
    }
}

