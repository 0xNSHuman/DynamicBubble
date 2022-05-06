//
//  ViewController.swift
//  DynamicBubbleDemo
//
//  Created by 0xNSHuman on 21/02/2017.
//  Copyright © 2017 0xNSHuman. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation

enum ControlsMode: Int {
    case off = 0, on, debug
    
    func toggle() -> ControlsMode {
        if self.rawValue == 2 {
            return ControlsMode(rawValue: 0)!
        } else {
            return ControlsMode(rawValue: self.rawValue + 1)!
        }
    }
}

class ViewController: UIViewController {
    var bubbles: Set<DynamicBubble>
    private var mapView: MKMapView?
    var controlsModeButton: UIButton?
    var controlsMode = ControlsMode.on
    
    // MARK: Initializers
    
    required init?(coder aDecoder: NSCoder) {
        bubbles = Set<DynamicBubble>()
        super.init(coder: aDecoder)
    }

    // MARK: View life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupView()
    }
    
    // MARK: View customization
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    func setupView() {
        mapView = MKMapView(frame: view.bounds)
        mapView?.mapType = .hybrid
        mapView?.showsUserLocation = true
        view.addSubview(mapView!)
        showAddressOnMap("Tokyo")
        
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor(white: 0.0, alpha: 0.30)
        view.addSubview(overlayView)
        
        let addButton = defaultButtonWithTitle("Add", selector: #selector(addBubble))
        addButton.frame = CGRect(x: view.bounds.size.width - 100 - 10,
                                 y: view.bounds.size.height - 44 - 10,
                                 width: 100, height: 44)
        view.addSubview(addButton)
        
        controlsModeButton = defaultButtonWithTitle("Bubble Mode: Controllable", selector: #selector(toggleControlsMode))
        controlsModeButton?.frame = CGRect(x: view.bounds.size.width / 2 - 150, y: 10, width: 300, height: 44)
        
        view.addSubview(controlsModeButton!)
    }
    
    func showAddressOnMap(_ addressString: String) {
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(addressString) { (placemarks, error) in
            if placemarks != nil && (placemarks?.count)! > 0 {
                let topResult = (placemarks?.first)!
                let coordRegion = MKCoordinateRegionMakeWithDistance((topResult.location?.coordinate)!, 1500, 1500)
                
                self.mapView?.setRegion(coordRegion, animated: true)
            }
        }
    }
    
    func randomizeAppearance(forBubble bubble: DynamicBubble) {
        bubble.textFont = randomFont()
        bubble.textColor = randomColor()
        bubble.fillColor = randomColor()
        bubble.strokeColor = randomColor()
        //bubble.controlsColor = randomControlsColor()
        
        bubble.setNeedsDisplay()
    }
    
    // MARK: Touch events
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
    }
    
    // MARK: Control events
    
    func addBubble() {
        let bubble = DynamicBubble(centerPoint: self.view.center, originSides: [.down, .up, .left, .right])
        bubble.addObserver(self, forKeyPath: "center", options: .new, context: nil)
        
        randomizeAppearance(forBubble: bubble)
        
        bubbles.insert(bubble)
        self.view.addSubview(bubble)
        
        updateBubblesWithNewControlsMode()
    }
    
    func toggleControlsMode() {
        controlsMode = controlsMode.toggle()
        updateBubblesWithNewControlsMode()
    }
    
    func updateBubblesWithNewControlsMode() {
        switch controlsMode {
        case .on:
            controlsModeButton?.setTitle("Bubble Mode: Controllable", for: .normal)
            bubbles.forEach({ (bubble) in
                bubble.reactsToControls = true
                bubble.debugMode = false
                bubble.setNeedsDisplay()
            })
            
        case .off:
            controlsModeButton?.setTitle("Bubble Mode: Locked", for: .normal)
            bubbles.forEach({ (bubble) in
                bubble.reactsToControls = false
                bubble.debugMode = false
                bubble.setNeedsDisplay()
            })
            
        case .debug:
            controlsModeButton?.setTitle("Bubble Mode: Debug", for: .normal)
            bubbles.forEach({ (bubble) in
                bubble.reactsToControls = true
                bubble.debugMode = true
                bubble.setNeedsDisplay()
            })
        }
    }
    
    // MARK: UI fabric
    
    private func defaultButtonWithTitle(_ title: String, selector: Selector) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: selector, for: .touchUpInside)
        
        button.backgroundColor = UIColor.black
        button.titleLabel?.textColor = UIColor.white
        button.layer.borderColor = UIColor.gray.cgColor
        button.layer.cornerRadius = 5.0
        button.layer.borderWidth = 1.0
        
        return button
    }
    
    // MARK: KVO
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        let bubble = object as! DynamicBubble
        
        if bubble.center.y < self.view.bounds.size.height / 2 {
            bubble.addTailAtSide(.down)
            bubble.removeTailAtSide(.up)
        } else {
            bubble.addTailAtSide(.up)
            bubble.removeTailAtSide(.down)
        }
        
        if bubble.center.x < self.view.bounds.size.width / 2 {
            bubble.addTailAtSide(.right)
            bubble.removeTailAtSide(.left)
        } else {
            bubble.addTailAtSide(.left)
            bubble.removeTailAtSide(.right)
        }
    }
    
    // MARK: Randomizers
    
    func randomFont() -> UIFont {
        let random = arc4random() % 3;
        switch random {
        case 0:
            return UIFont(name: "Helvetica-Bold", size: randomFontSize())!
        case 1:
            return UIFont(name: "Helvetica-Light", size: randomFontSize())!
        case 2:
            return UIFont(name: "Courier", size: randomFontSize())!
        default:
            break
        }
        
        return UIFont(name: "Helvetica-Bold", size: randomFontSize())!
    }
    
    func randomFontSize() -> CGFloat {
        let random = arc4random() % 10 + 12;
        return CGFloat(random)
    }
    
    func randomColor() -> UIColor {
        let hue = (CGFloat(arc4random() % 256) / 256.0)
        let saturation = (CGFloat(arc4random() % 128) / 256.0) + 0.5
        let brightness = (CGFloat(arc4random() % 128) / 256.0) + 0.5
        let color = UIColor.init(hue: hue,
                                 saturation: saturation,
                                 brightness: brightness, alpha: 1)
        
        return color
    }
    
    func randomControlsColor() -> UIColor {
        let hue = (CGFloat(arc4random() % 256) / 256.0)
        let saturation = (CGFloat(arc4random() % 256) / 256.0)
        let brightness = (CGFloat(arc4random() % 256) / 256.0)
        let color = UIColor.init(hue: hue,
                                 saturation: saturation,
                                 brightness: brightness, alpha: 1)
        
        return color
    }
}
