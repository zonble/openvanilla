// Copyright (c) 2022 and onwards The McBopomofo Authors.
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

import Cocoa

@objc(VTCandidateKeyLabel)
public class CandidateKeyLabel: NSObject {
    @objc public private(set) var key: String
    @objc public private(set) var displayedText: String

    @objc public init(key: String, displayedText: String) {
        self.key = key
        self.displayedText = displayedText
        super.init()
    }
}

@objc(VTCandidateControllerDelegate)
public protocol CandidateControllerDelegate: AnyObject {
    func candidateCountForController(_ controller: CandidateController) -> UInt
    func candidateController(_ controller: CandidateController, candidateAtIndex index: UInt) -> String
    func candidateController(_ controller: CandidateController, requestExplanationFor candidate: String) -> String?
    func candidateController(_ controller: CandidateController, didSelectCandidateAtIndex index: UInt)
}

@objc(VTCandidateController)
public class CandidateController: NSWindowController {
    @objc public weak var delegate: CandidateControllerDelegate? {
        didSet {
            reloadData()
        }
    }

    @objc public var selectedCandidateIndex: UInt = .max
    @objc public var visible: Bool = false {
        didSet {
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            guard let window else {
                return
            }
            let alreadyVisible = window.isVisible
            if visible {
                window.perform(#selector(NSWindow.orderFront(_:)), with: self, afterDelay: 0.0)
                if !alreadyVisible {
                    NSAccessibility.post(element: window, notification: .created)
                    NSAccessibility
                        .post(element: window, notification: .focusedWindowChanged)
                }
            } else {
                window.perform(#selector(NSWindow.orderOut(_:)), with: self, afterDelay: 0.0)
            }
        }
    }

    @objc public var windowTopLeftPoint: NSPoint {
        get {
            guard let frameRect = window?.frame else {
                return NSPoint.zero
            }
            return NSPoint(x: frameRect.minX, y: frameRect.maxY)
        }
        set {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()) {
                self.set(windowTopLeftPoint: newValue, bottomOutOfScreenAdjustmentHeight: 0)
            }
        }
    }

    @objc public var keyLabels: [CandidateKeyLabel] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"].map {
        CandidateKeyLabel(key: $0, displayedText: $0)
    }

    @objc public var keyLabelFont: NSFont = .systemFont(ofSize: 14)
    @objc public var candidateFont: NSFont = .systemFont(ofSize: 18)
    @objc public var tooltip: String = ""

    @objc public func reloadData() {}

    @objc public func showNextPage() -> Bool {
        false
    }

    @objc public func showPreviousPage() -> Bool {
        false
    }

    @objc public func highlightNextCandidate() -> Bool {
        false
    }

    @objc public func highlightPreviousCandidate() -> Bool {
        false
    }

    @objc public func candidateIndexAtKeyLabelIndex(_: UInt) -> UInt {
        UInt.max
    }

    /// Sets the location of the candidate window.
    ///
    /// Please note that the method has side effects that modifies
    /// `windowTopLeftPoint` to make the candidate window to stay in at least
    /// in a screen.
    ///
    /// - Parameters:
    ///   - windowTopLeftPoint: The given location.
    ///   - height: The height that helps the window not to be out of the bottom
    ///     of a screen.
    @objc(setWindowTopLeftPoint:bottomOutOfScreenAdjustmentHeight:)
    public func set(windowTopLeftPoint: NSPoint, bottomOutOfScreenAdjustmentHeight height: CGFloat) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now()) {
            self.doSet(windowTopLeftPoint: windowTopLeftPoint, bottomOutOfScreenAdjustmentHeight: height)
        }
    }

    func doSet(windowTopLeftPoint: NSPoint, bottomOutOfScreenAdjustmentHeight height: CGFloat) {
        var adjustedPoint = windowTopLeftPoint
        var adjustedHeight = height

        var screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        for screen in NSScreen.screens {
            let frame = screen.visibleFrame
            if windowTopLeftPoint.x >= frame.minX,
               windowTopLeftPoint.x <= frame.maxX,
               windowTopLeftPoint.y >= frame.minY,
               windowTopLeftPoint.y <= frame.maxY
            {
                screenFrame = frame
                break
            }
        }

        if adjustedHeight > screenFrame.size.height / 2.0 {
            adjustedHeight = 0.0
        }

        let windowSize = window?.frame.size ?? NSSize.zero

        // bottom beneath the screen?
        if adjustedPoint.y - windowSize.height < screenFrame.minY {
            adjustedPoint.y = windowTopLeftPoint.y + adjustedHeight + windowSize.height
        }

        // top over the screen?
        if adjustedPoint.y >= screenFrame.maxY {
            adjustedPoint.y = screenFrame.maxY - 1.0
        }

        // right
        if adjustedPoint.x + windowSize.width >= screenFrame.maxX {
            adjustedPoint.x = screenFrame.maxX - windowSize.width
        }

        // left
        if adjustedPoint.x < screenFrame.minX {
            adjustedPoint.x = screenFrame.minX
        }

        window?.setFrameTopLeftPoint(adjustedPoint)
    }
}
