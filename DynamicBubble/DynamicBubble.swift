//
//  DynamicBubble.swift
//
//  Created by 0xNSHuman (hello@vladaverin.me) on 21/02/2017.
//  Copyright © 2017 0xNSHuman. All rights reserved.
//
//  Distributed under the permissive zlib License
//  Get the latest version from here:
//
//  https://github.com/0xNSHuman/DynamicBubble
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.

import UIKit

private let defaultBubbleSize = CGSize(width: 200, height: 100)
private let defaultTailSize = CGSize(width: 30, height: 20)
private let defaultControlPointRadius: CGFloat = 3.0
private let defaultControlPointActiveAreaRadius: CGFloat = 30.0

private let defaultMinimumTailHeight: CGFloat = defaultTailSize.height - 5
private let defaultMinimumBubbleFrameSize: CGSize = CGSize(width: 60, height: 40)

private let defaultTextMargin: CGFloat = 5.0
private let defaultTextColor: UIColor = .darkGray

private let defaultFillColor = UIColor.lightGray
private let defaultStrokeColor = UIColor.darkGray
private let defaultControlPointColor = UIColor.green

enum TailOriginSide: Int {
    case up, right, down, left
}

private struct TailInfo: Hashable, Equatable {
    let pathPoints: (CGPoint, CGPoint, CGPoint)
    let originSide: TailOriginSide
    
    var hashValue: Int { return originSide.rawValue }
    
    init(vertices: (CGPoint, CGPoint, CGPoint), originSide: TailOriginSide) {
        pathPoints = vertices; self.originSide = originSide
    }
    
    static func ==(lhs: TailInfo, rhs: TailInfo) -> Bool {
        return lhs.originSide == rhs.originSide
    }
}

private enum ControlPointType: Int {
    case stretchUpLeft = 0, stretchUpRight, stretchDownLeft, stretchDownRight
    case moveTopTail, moveBottomTail, moveLeftTail, moveRightTail
    
    func isStretchControl() -> Bool {
        if self.rawValue < ControlPointType.moveTopTail.rawValue {
            return true
        }
        
        return false
    }
    
    func isTailControl() -> Bool {
        if self.rawValue > ControlPointType.stretchDownRight.rawValue {
            return true
        }
        
        return false
    }
}

private struct ControlPoint: Hashable, Equatable {
    let location: CGPoint
    let type: ControlPointType
    
    var hashValue: Int { return type.rawValue }
    
    init(location: CGPoint, type: ControlPointType) {
        self.location = location; self.type = type
    }
    
    func copy() -> ControlPoint {
        return ControlPoint(location: location, type: type)
    }
    
    static func ==(lhs: ControlPoint, rhs: ControlPoint) -> Bool {
        return lhs.type == rhs.type
    }
    
    func isPointInSurroundingArea(_ point: CGPoint) -> Bool {
        if (pow((point.x - self.location.x), 2.0) + pow((point.y - self.location.y), 2.0)) < pow(defaultControlPointActiveAreaRadius, 2.0) {
            
            return true
        }
        
        return false
    }
}

private enum ControlGestureType: Int {
    case none = 0
    case dragBubble
    case moveTailVertex
    case resizeBubble
}

private struct ControlGesture {
    let type: ControlGestureType
    var originalControlPoint: ControlPoint?
    var originalBubbleFrameSize: CGSize?
    let gestureOriginPoint: CGPoint
    
    init(type: ControlGestureType, gestureOrigin: CGPoint) {
        self.type = type
        gestureOriginPoint = gestureOrigin
    }
}

class DynamicBubble: UIView {
    fileprivate var canvas: DynamicBubbleCanvas?
    private var activeControlGesture: ControlGesture?
    
    var activeTails: Set<TailOriginSide> {
        var tailSides = Set<TailOriginSide>()
        for tail in (canvas?.tailsInfo)! { tailSides.insert(tail.originSide) }
        return tailSides
    }
    
    var fillColor: UIColor = defaultFillColor
    var strokeColor: UIColor = defaultStrokeColor
    
    // TODO: Add support of any rounding
    /*
    var rounding: CGFloat {
        get { return roundingFactor }
        set(newRounding) {
            roundingFactor = (newRounding <= 0.05) ? newRounding : 0.05
            canvas?.setNeedsDisplay()
        }
    }
    */
    
    fileprivate var roundingFactor: CGFloat = 0.05
    
    var textFont: UIFont {
        get { return (canvas?.textView.font)! }
        set(newFont) { canvas?.textView.font = newFont }
    }
    
    private(set) var textFrameMargin = defaultTextMargin
    
    var textAlignment: NSTextAlignment {
        get { return (canvas?.textView.textAlignment)! }
        set(newAlignment) { canvas?.textView.textAlignment = newAlignment }
    }
    
    var textColor: UIColor {
        get { return (canvas?.textView.textColor)! }
        set(newColor) { canvas?.textView.textColor = newColor }
    }
    
    var controlsColor: UIColor = defaultControlPointColor
    var controlsRadius: CGFloat = defaultControlPointRadius
    
    var showsControls = true
    var reactsToControls: Bool {
        get { return controlsEnabled }
        set(newValue) {
            controlsEnabled = newValue
            canvas?.setNeedsDisplay()
        }
    }
    
    fileprivate var controlsEnabled = true
    
    var bringToFrontWhenActive = true
    var startsWithActiveTextBox = false
    
    var debugMode = false
    
    // MARK: Private initializers
    
    private override init(frame: CGRect) {
        super.init(frame: frame)
        canvas = DynamicBubbleCanvas(bubbleView:self);
        
        if let c = canvas { self.addSubview(c) }
        self.clipsToBounds = false
        
        let doubleTapGesture = UITapGestureRecognizer(
            target: self, action: #selector(bubbleDoubleTapped(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        self.addGestureRecognizer(doubleTapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(bubbleDragged(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        self.addGestureRecognizer(panGesture)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Public initializers
    
    convenience init(centerPoint: CGPoint, originSides: Array<TailOriginSide>,
                     bubbleSize: CGSize) {
        
        /* Create tailless bubble frame */
        self.init(frame: CGRect(origin: CGPoint.zero, size: defaultBubbleSize))
        
        /* Add default frames and points info for requested tails */
        for side in originSides {
            canvas?.addTailToBubbleSide(side)
        }
        
        self.center = centerPoint
    }
    
    convenience init(centerPoint: CGPoint, originSides: Array<TailOriginSide>) {
        self.init(centerPoint: centerPoint,
                  originSides: originSides,
                  bubbleSize: defaultBubbleSize)
    }
    
    convenience init(centerPoint: CGPoint) {
        self.init(centerPoint: centerPoint, originSides: [.down])
    }
    
    // MARK: Life cycle
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if startsWithActiveTextBox { canvas?.startEditingText() }
    }
    
    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        canvas?.setNeedsDisplay()
    }
    
    // MARK: Tails control
    
    func removeTailAtSide(_ side: TailOriginSide) {
        guard activeTails.contains(side) else {
            return
        }
        
        canvas?.removeTailFromBubbleAtSide(side)
    }
    
    func addTailAtSide(_ side: TailOriginSide) {
        guard !activeTails.contains(side) else {
            return
        }
        
        canvas?.addTailToBubbleSide(side)
    }
    
    // MARK: Touch resolvers
    
    internal override func hitTest(_ point: CGPoint,
                                   with event: UIEvent?) -> UIView? {
        
        let hitView = super.hitTest(point, with: event)
        
        if (canvas?.pointIsInsideBubble(self.convert(point, to: canvas)))! {
            return self
        }
        
        return hitView
    }
    
    internal override func touchesBegan(_ touches: Set<UITouch>,
                                        with event: UIEvent?) {
        
        guard controlsEnabled else {
            return
        }
        
        if bringToFrontWhenActive {
            superview?.bringSubview(toFront: self)
        }
    }
    
    // MARK: Gestures
    
    internal func bubbleDoubleTapped(_ gesture: UITapGestureRecognizer) {
        guard controlsEnabled else {
            return
        }
        
        let pointOnCanvas = self.convert(gesture.location(in: self), to: canvas)
        
        guard !(canvas?.pointIsInControlArea(pointOnCanvas))! else {
            return
        }
        
        canvas?.startEditingText()
    }
    
    internal func bubbleDragged(_ gesture: UIPanGestureRecognizer) {
        guard controlsEnabled else {
            return
        }
        
        let pointOnCanvas = self.convert(gesture.location(in: self), to: canvas)
        
        if gesture.state == .began {
            if let control = canvas?.controlPointForPoint(pointOnCanvas) {
                if control.type.isTailControl() {
                    activeControlGesture = ControlGesture(type: .moveTailVertex,
                                                          gestureOrigin: control.location)
                    activeControlGesture?.originalControlPoint = control.copy()
                } else {
                    activeControlGesture = ControlGesture(type: .resizeBubble,
                                                          gestureOrigin: control.location)
                    activeControlGesture?.originalControlPoint = control.copy()
                    activeControlGesture?.originalBubbleFrameSize = canvas?.bubbleFrame.size
                }
            } else {
                activeControlGesture = ControlGesture(type: .dragBubble,
                                                      gestureOrigin: self.center)
            }
        }
        
        if gesture.state == .ended || gesture.state == .failed || gesture.state == .cancelled {
            activeControlGesture = nil
        }
        
        // While pan is ongoing
        
        let translation = gesture.translation(in: superview)
        
        guard let _ = activeControlGesture else {
            return
        }
        
        let panGestureOrigin = activeControlGesture?.gestureOriginPoint ?? CGPoint.zero
        
        switch (activeControlGesture?.type)! {
        case .dragBubble:
            self.center = CGPoint(x: panGestureOrigin.x + translation.x,
                                  y: panGestureOrigin.y + translation.y)
            
        case .moveTailVertex:
            guard let control = activeControlGesture?.originalControlPoint else {
                break
            }
            
            // Update tail with gesture data
            
            if let newTail = canvas?.updateTailInfoWithControlGesture(
                activeControlGesture!, translation: translation) {
                
                // Update gesture's control point copy for future reference
                let updatedControlPoint = ControlPoint(location: newTail.pathPoints.1,
                                                       type: control.type)
                activeControlGesture?.originalControlPoint = updatedControlPoint
            }
            
        case .resizeBubble:
            guard let control = activeControlGesture?.originalControlPoint else {
                break
            }
            
            if let newFrame = canvas?.updateBubbleFrameWithControlGesture(
                activeControlGesture!, translation: translation) {
                
                let updatedPoint: CGPoint
                
                switch control.type {
                case .stretchUpLeft:
                    updatedPoint = newFrame.origin
                    
                case .stretchUpRight:
                    updatedPoint = CGPoint(x: newFrame.origin.x + newFrame.size.width,
                                           y: newFrame.origin.y)
                    
                case .stretchDownLeft:
                    updatedPoint = CGPoint(x: newFrame.origin.x,
                                           y: newFrame.origin.y + newFrame.size.height)
                    
                case .stretchDownRight:
                    updatedPoint = CGPoint(x: newFrame.origin.x + newFrame.size.width,
                                           y: newFrame.origin.y + newFrame.size.height)
                    
                default:
                    updatedPoint = CGPoint.zero
                }
                
                // Update gesture's control point copy for future reference
                let updatedControlPoint = ControlPoint(location: updatedPoint,
                                                       type: control.type)
                activeControlGesture?.originalControlPoint = updatedControlPoint
            }
            
        default:
            break
        }
    }
}

private class DynamicBubbleCanvas: UIView, UITextViewDelegate {
    private weak var bubbleView: DynamicBubble?
    
    private(set) var tailsInfo = Set<TailInfo>()
    private var controlPoints = Set<ControlPoint>()
    private(set) var bubbleFrame: CGRect
    fileprivate var textView: UITextView
    private var bubblePath: UIBezierPath?
    
    // MARK: Initializers
    
    private override init(frame: CGRect) {
        bubbleFrame = CGRect(origin: CGPoint.zero, size: defaultBubbleSize)
        textView = UITextView()
        
        super.init(frame: frame)
        
        self.backgroundColor = UIColor.clear
        self.isOpaque = false
    }
    
    convenience init(bubbleView: DynamicBubble) {
        self.init(frame: CGRect(x: 0, y: 0,
                                width: UIScreen.main.bounds.size.width * 2,
                                height: UIScreen.main.bounds.size.height * 2))
        
        self.center = CGPoint(x: bubbleView.frame.size.width / 2,
                              y: bubbleView.frame.size.height / 2)
        
        self.bubbleView = bubbleView
        bubbleView.canvas = self
        
        bubbleFrame = bubbleView.convert(bubbleView.frame, to: self)
        
        textView.textAlignment = NSTextAlignment.center
        textView.backgroundColor = UIColor.clear
        textView.font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
        textView.textColor = defaultTextColor
        textView.returnKeyType = .done
        
        textView.delegate = self
        self.addSubview(textView)
        
        recalculateTextFrame()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Text
    
    private func recalculateTextFrame() {
        textView.frame = CGRect(
            x: bubbleFrame.origin.x + (bubbleView?.textFrameMargin)!,
            y: bubbleFrame.origin.y + (bubbleView?.textFrameMargin)!,
            width: bubbleFrame.size.width - (bubbleView?.textFrameMargin)! * 2,
            height: bubbleFrame.size.height - (bubbleView?.textFrameMargin)! * 2
        )
    }
    
    fileprivate func startEditingText() {
        textView.becomeFirstResponder()
    }
    
    fileprivate func finishEditingText() {
        textView.resignFirstResponder()
    }
    
    // MARK: Text view delegate
    
    fileprivate func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        
        if text == "\n"{
            finishEditingText()
            return false
        }
        
        return true
    }
    
    // MARK: Control points
    
    private func recalculateControlPoints() {
        // Update control points data
        
        controlPoints.removeAll()
        
        controlPoints.insert(ControlPoint(location: bubbleFrame.origin, type: .stretchUpLeft))
        
        controlPoints.insert(ControlPoint(location: CGPoint(x: bubbleFrame.origin.x + bubbleFrame.size.width, y: bubbleFrame.origin.y), type: .stretchUpRight))
        
        controlPoints.insert(ControlPoint(location: CGPoint(x: bubbleFrame.origin.x, y: bubbleFrame.origin.y + bubbleFrame.size.height), type: .stretchDownLeft))
        
        controlPoints.insert(ControlPoint(location: CGPoint(x: bubbleFrame.origin.x + bubbleFrame.size.width, y: bubbleFrame.origin.y + bubbleFrame.size.height), type: .stretchDownRight))
        
        for tail in tailsInfo {
            let controlVertex = tail.pathPoints.1
            let controlType: ControlPointType?
            
            switch tail.originSide {
            case .up:
                controlType = .moveTopTail
                
            case .down:
                controlType = .moveBottomTail
                
            case .left:
                controlType = .moveLeftTail
                
            case .right:
                controlType = .moveRightTail
            }
            
            controlPoints.insert(ControlPoint(location: controlVertex, type: controlType!))
        }
    }
    
    // MARK: Bubble frame
    
    fileprivate func updateBubbleFrameWithControlGesture(_ gesture: ControlGesture, translation: CGPoint) -> CGRect? {
        
        guard let originalFrameSize = gesture.originalBubbleFrameSize else {
            if (bubbleView?.debugMode)! { print("Original rect is lost while updating bubble frame!") }
            return nil
        }
        
        guard let control = gesture.originalControlPoint else {
            if (bubbleView?.debugMode)! { print("Control point is lost while updating bubble frame!") }
            return nil
        }
        
        // Stretch bubble frame, leaving it centered
        
        let updatedSize: CGSize
        
        switch control.type {
        case .stretchUpLeft:
            updatedSize = CGSize(width: originalFrameSize.width - translation.x,
                                 height: originalFrameSize.height - translation.y)
            
        case .stretchUpRight:
            updatedSize = CGSize(width: originalFrameSize.width + translation.x,
                                 height: originalFrameSize.height - translation.y)
            
        case .stretchDownLeft:
            updatedSize = CGSize(width: originalFrameSize.width - translation.x,
                                 height: originalFrameSize.height + translation.y)
            
        case .stretchDownRight:
            updatedSize = CGSize(width: originalFrameSize.width + translation.x,
                                 height: originalFrameSize.height + translation.y)
            
        default:
            updatedSize = CGSize.zero
        }
        
        let updatedBubbleFrame = CGRect(x: bounds.size.width / 2 - updatedSize.width / 2, y: bounds.size.height / 2 - updatedSize.height / 2, width: updatedSize.width, height: updatedSize.height)
        
        
        if !doesBubbleFrameSatisfyMinimalConstraints(updatedBubbleFrame) {
            return nil
        }
        
        adaptTailsForNewFrameIfNeeded(bubbleFrame)
        
        bubbleFrame = updatedBubbleFrame
        
        // Recalculate text frame and existing tails to be re-attached to new frame
        
        recalculateTextFrame()
        recalculateExistingTailsInfo()
        
        // Recalculate control points
        
        recalculateControlPoints()
        setNeedsDisplay()
        
        return bubbleFrame
    }
    
    // MARK: Tails
    
    fileprivate func addTailToBubbleSide(_ side: TailOriginSide) {
        let tail = defaultTailInfoForSide(side)
        tailsInfo.insert(tail)
        recalculateControlPoints()
        setNeedsDisplay()
    }
    
    fileprivate func removeTailFromBubbleAtSide(_ side: TailOriginSide) {
        var tailToRemove: TailInfo?
        
        for tail in tailsInfo {
            if tail.originSide == side {
                tailToRemove = tail
            }
        }
        
        if let _ = tailToRemove {
            tailsInfo.remove(tailToRemove!)
            recalculateControlPoints()
            setNeedsDisplay()
        }
    }
    
    fileprivate func updateTailInfoWithControlGesture(_ gesture: ControlGesture, translation: CGPoint) -> TailInfo? {
        
        let gestureOrigin = gesture.gestureOriginPoint
        
        guard let control = gesture.originalControlPoint else {
            if (bubbleView?.debugMode)! { print("Control point is lost while updating tail!") }
            return nil
        }
        
        if let tailInfo = tailInfoForControlPoint(control) {
            // Update tail control vertex
            let updatedControlVertex = CGPoint(x: gestureOrigin.x + translation.x,
                                               y: gestureOrigin.y + translation.y)
            
            if !tail(tailInfo, isAllowedToHaveControlVertex: updatedControlVertex) {
                return nil
            }
            
            let updatedVertices = (tailInfo.pathPoints.0,
                                   updatedControlVertex,
                                   tailInfo.pathPoints.2)
            
            // Update tail info and recalculate control points
            let newTailInfo = TailInfo(vertices: updatedVertices,
                                       originSide: tailInfo.originSide)
            
            tailsInfo.update(with: newTailInfo)
            recalculateControlPoints()
            setNeedsDisplay()
            
            return newTailInfo
        }
        
        return nil
    }
    
    private func recalculateExistingTailsInfo() {
        for tail in tailsInfo {
            var x: CGFloat?, y: CGFloat?
            
            switch tail.originSide {
            case .up:
                y = bubbleFrame.origin.y
                
            case .down:
                y = bubbleFrame.origin.y + bubbleFrame.size.height
                
            case .left:
                x = bubbleFrame.origin.x
                
            case .right:
                x = bubbleFrame.origin.x + bubbleFrame.size.width
            }
            
            let newPath = (
                CGPoint(x: x ?? tail.pathPoints.0.x, y: y ?? tail.pathPoints.0.y),
                tail.pathPoints.1,
                CGPoint(x: x ?? tail.pathPoints.2.x, y: y ?? tail.pathPoints.2.y)
            )
            
            // Update tail info and recalculate control points
            let newTailInfo = TailInfo(vertices: newPath,
                                       originSide: tail.originSide)
            
            tailsInfo.update(with: newTailInfo)
        }
    }
    
    private func defaultTailInfoForSide(_ side: TailOriginSide) -> TailInfo {
        let originX: CGFloat, originY: CGFloat, sizeW: CGFloat, sizeH: CGFloat
        let pathVertices: (CGPoint, CGPoint, CGPoint)
        
        switch side {
        case .up:
            originX = bubbleFrame.size.width / 2 + bubbleFrame.origin.x
                - defaultTailSize.width / 2
            originY = bubbleFrame.origin.y - defaultTailSize.height
            sizeW = defaultTailSize.width
            sizeH = defaultTailSize.height
            
            let ver1 = CGPoint(x: originX, y: originY + sizeH)
            let ver2 = CGPoint(x: originX + sizeW / 2, y: originY)
            let ver3 = CGPoint(x: originX + sizeW, y: originY + sizeH)
            
            pathVertices = (ver1, ver2, ver3)
        case .down:
            originX = bubbleFrame.size.width / 2 + bubbleFrame.origin.x
                - defaultTailSize.width / 2
            originY = bubbleFrame.origin.y + bubbleFrame.size.height
            sizeW = defaultTailSize.width
            sizeH = defaultTailSize.height
            
            let ver1 = CGPoint(x: originX, y: originY)
            let ver2 = CGPoint(x: originX + sizeW / 2, y: originY + sizeH)
            let ver3 = CGPoint(x: originX + sizeW, y: originY)
            
            pathVertices = (ver1, ver2, ver3)
        case .left:
            originX = bubbleFrame.origin.x - defaultTailSize.height
            originY = bubbleFrame.origin.y + bubbleFrame.size.height / 2
                - defaultTailSize.width / 2
            sizeW = defaultTailSize.height
            sizeH = defaultTailSize.width
            
            let ver1 = CGPoint(x: originX + sizeW, y: originY)
            let ver2 = CGPoint(x: originX, y: originY + sizeH / 2)
            let ver3 = CGPoint(x: originX + sizeW, y: originY + sizeH)
            
            pathVertices = (ver1, ver2, ver3)
        case .right:
            originX = bubbleFrame.origin.x + bubbleFrame.size.width
            originY = bubbleFrame.origin.y + bubbleFrame.size.height / 2
                - defaultTailSize.width / 2
            sizeW = defaultTailSize.height
            sizeH = defaultTailSize.width
            
            let ver1 = CGPoint(x: originX, y: originY)
            let ver2 = CGPoint(x: originX + sizeW, y: originY + sizeH / 2)
            let ver3 = CGPoint(x: originX, y: originY + sizeH)
            
            pathVertices = (ver1, ver2, ver3)
        }
        
        return TailInfo(vertices: pathVertices, originSide: side)
    }
    
    // MARK: Touch resolvers
    
    fileprivate func pointIsInsideBubble(_ p: CGPoint) -> Bool {
        /* Check if point is either part of bubble frame or one of the tails */
        if bubbleFrame.contains(p) { return true }
        
        for tail in tailsInfo {
            if does(tail: tail, containPoint: p) { return true }
        }
        
        for control in controlPoints {
            if does(controlPoint: control, containPoint: p) { return true }
        }
        
        return false
    }
    
    fileprivate func pointIsInControlArea(_ p: CGPoint) -> Bool {
        for control in controlPoints {
            if control.isPointInSurroundingArea(p) {
                return true
            }
        }
        
        return false
    }
    
    fileprivate func controlPointForPoint(_ p: CGPoint) -> ControlPoint? {
        for control in controlPoints {
            if control.isPointInSurroundingArea(p) {
                return control
            }
        }
        
        return nil
    }
    
    fileprivate func tailInfoForControlPoint(_ p: ControlPoint) -> TailInfo? {
        for tail in tailsInfo {
            if tail.pathPoints.1.equalTo(p.location) { return tail }
        }
        
        return nil
    }
    
    fileprivate func does(tail: TailInfo, containPoint p: CGPoint) -> Bool {
        let pathToTest = UIBezierPath()
        pathToTest.move(to: tail.pathPoints.0)
        pathToTest.addLine(to: tail.pathPoints.1)
        pathToTest.addLine(to: tail.pathPoints.2)
        pathToTest.close()
        
        return pathToTest.contains(p)
    }
    
    fileprivate func does(controlPoint: ControlPoint, containPoint p: CGPoint) -> Bool {
        return controlPoint.isPointInSurroundingArea(p)
    }
    
    // MARK: Constraints
    
    fileprivate func tail(_ tail: TailInfo,
                          isAllowedToHaveControlVertex vertex: CGPoint) -> Bool {
        
        switch tail.originSide {
        case .up:
            return vertex.y + defaultMinimumTailHeight < bubbleFrame.origin.y
            
        case .down:
            return vertex.y - defaultMinimumTailHeight > bubbleFrame.origin.y + bubbleFrame.size.height
            
        case .left:
            return vertex.x + defaultMinimumTailHeight < bubbleFrame.origin.x
            
        case .right:
            return vertex.x - defaultMinimumTailHeight > bubbleFrame.origin.x + bubbleFrame.size.width
        }
    }
    
    fileprivate func doesBubbleFrameSatisfyMinimalConstraints(_ newFrame: CGRect) -> Bool {
        if newFrame.width < defaultMinimumBubbleFrameSize.width && newFrame.size.width < bubbleFrame.size.width { return false }
        if newFrame.height < defaultMinimumBubbleFrameSize.height && newFrame.size.height < bubbleFrame.size.height { return false }
        
        return true
    }
    
    fileprivate func adaptTailsForNewFrameIfNeeded(_ newFrame: CGRect) {
        for tailInfo in tailsInfo {
            var translationToApply: CGPoint?
            
            switch tailInfo.originSide {
            case .up:
                if tailInfo.pathPoints.1.y + defaultMinimumTailHeight >= newFrame.origin.y {
                    
                    translationToApply = CGPoint(
                        x: 0.0, y: -defaultMinimumTailHeight
                    )
                }
            case .down:
                if tailInfo.pathPoints.1.y - defaultMinimumTailHeight <= newFrame.origin.y + newFrame.size.height {
                    
                    translationToApply = CGPoint(
                        x: 0.0, y: defaultMinimumTailHeight
                    )
                }
                
            case .left:
                if tailInfo.pathPoints.1.x + defaultMinimumTailHeight >= newFrame.origin.x {
                    
                    translationToApply = CGPoint(
                        x: -defaultMinimumTailHeight, y: 0.0
                    )
                }
                
            case .right:
                if tailInfo.pathPoints.1.x - defaultMinimumTailHeight <= newFrame.origin.x + newFrame.size.width {
                    
                    translationToApply = CGPoint(
                        x: defaultMinimumTailHeight, y: 0.0
                    )
                }
            }
            
            if let translation = translationToApply {
                let updatedControlVertex = CGPoint(x: tailInfo.pathPoints.1.x + translation.x,
                                                   y: tailInfo.pathPoints.1.y + translation.y)
                
                let updatedVertices = (tailInfo.pathPoints.0,
                                       updatedControlVertex,
                                       tailInfo.pathPoints.2)
                
                let newTailInfo = TailInfo(vertices: updatedVertices,
                                           originSide: tailInfo.originSide)
                
                tailsInfo.update(with: newTailInfo)
            }
        }
    }
    
    private func animateTailConstraintConflict(_ tail: TailInfo) {
        // TODO: Constraint conflicts animation
    }
    
    private func animateBubbleFrameConstraintConflict() {
        // TODO: Constraint conflicts animation
    }
    
    // MARK: Drawing
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        
        guard let ctx = context else {
            return;
        }
        
        ctx.clear(rect)
        ctx.setLineWidth(1.0)
        
        drawBubbleFrame(ctx: ctx)
        drawTails(ctx: ctx)
        
        if (bubbleView?.showsControls)! && (bubbleView?.controlsEnabled)! {
            for controlPoint in controlPoints {
                drawControlPoint(point: controlPoint.location, context: ctx)
            }
        }
    }
    
    private func drawBubbleFrame(ctx: CGContext) {
        bubblePath = UIBezierPath(roundedRect: bubbleFrame, byRoundingCorners: UIRectCorner.allCorners, cornerRadii: CGSize(width: bubbleFrame.size.width * (bubbleView?.roundingFactor)!, height: bubbleFrame.size.height * (bubbleView?.roundingFactor)!))
        
        bubbleView?.strokeColor.setStroke()
        bubbleView?.fillColor.setFill()
        
        bubblePath?.lineWidth = 2.0
        
        bubblePath?.stroke()
        bubblePath?.fill()
    }
    
    private func drawTails(ctx: CGContext) {
        for tail in tailsInfo {
            
            // Tail outline
            
            ctx.beginPath()
            ctx.move(to: tail.pathPoints.0)
            ctx.addLine(to: tail.pathPoints.1)
            ctx.addLine(to: tail.pathPoints.2)
            
            ctx.setStrokeColor((bubbleView?.strokeColor.cgColor)!)
            ctx.setFillColor((bubbleView?.fillColor.cgColor)!)
            
            ctx.drawPath(using: .fillStroke)
            
            // 'Erase' border line between tail and bubble using fill color
            
            ctx.beginPath()
            ctx.move(to: tail.pathPoints.0)
            ctx.addLine(to: tail.pathPoints.2)
            
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setStrokeColor((bubbleView?.fillColor.cgColor)!)
            ctx.strokePath()
        }
    }
    
    private func drawControlPoint(point: CGPoint, context ctx: CGContext) {
        ctx.beginPath()
        ctx.addArc(center: point, radius: (bubbleView?.controlsRadius)!, startAngle: 0.0, endAngle: CGFloat(M_2_PI), clockwise: true)
        ctx.closePath()
        
        ctx.setLineWidth(2.0)
        ctx.setLineDash(phase: 0, lengths: []);
        ctx.setStrokeColor((bubbleView?.controlsColor.cgColor)!)
        ctx.strokePath()
        
        ctx.setLineWidth(1.0)
        
        if (bubbleView?.debugMode)! {
            drawControlTouchableAreaAroundPoint(point, ctx)
        }
    }
    
    // MARK: Debug mode
    
    private func drawControlTouchableAreaAroundPoint(_ point: CGPoint, _ ctx: CGContext) {
        ctx.beginPath()
        ctx.addArc(center: point, radius: defaultControlPointActiveAreaRadius, startAngle: 0.0, endAngle: CGFloat(M_2_PI), clockwise: true)
        ctx.closePath()
        
        ctx.setLineDash(phase: 1.0, lengths: [5.0])
        ctx.setStrokeColor(UIColor.red.cgColor)
        ctx.strokePath()
    }
}
