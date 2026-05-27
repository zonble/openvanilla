//
// OVInputMethodController.swift
//
// Copyright (c) 2004-2012 Lukhnos Liu (lukhnos at openvanilla dot org)
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
//

import Cocoa
import CxxStdlib
import InputMethodKit
import LoaderService
import ModuleManager
import OpenVanilla
import OpenVanillaImpl
import TooltipUI

@objc(OVInputMethodController)
final class OVInputMethodController: IMKInputController {
    private var composingText = UnsafeMutablePointer<OVTextBufferImpl>.allocate(capacity: 1)
    private var readingText = UnsafeMutablePointer<OVTextBufferImpl>.allocate(capacity: 1)
    private var inputMethodContext: UnsafeMutablePointer<OVEventHandlingContext>?
    private var associatedPhrasesContext: UnsafeMutablePointer<OVEventHandlingContext>?
    private var associatedPhrasesContextInUse = false
    private weak var currentClient: AnyObject?

    private static let numKeys: [UInt16] = [
        0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5b, 0x5c, 0x41, 0x45, 0x4e, 0x43, 0x4b, 0x51,
    ]

    @objc(initWithServer:delegate:client:)
    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        composingText.initialize(to: OVTextBufferImpl())
        readingText.initialize(to: OVTextBufferImpl())

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInputMethodChange(_:)),
            name: NSNotification.Name(rawValue: OVModuleManagerDidUpdateActiveInputMethodNotification),
            object: OVModuleManager.default)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        stopAssociatedPhrasesContext()
        stopInputMethodContext()

        composingText.deinitialize(count: 1)
        composingText.deallocate()
        readingText.deinitialize(count: 1)
        readingText.deallocate()
    }

    @objc(menu)
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let manager = OVModuleManager.default

        let activeInputMethodIdentifier = manager.activeInputMethodIdentifier
        let inputMethodIdentifiers = manager.inputMethodIdentifiers
        let excludedIdentifiers = manager.excludedIdentifiers

        for identifier in inputMethodIdentifiers where !excludedIdentifiers.contains(identifier) {
            let item = NSMenuItem()
            item.title = manager.localizedInputMethodName(identifier)
            item.representedObject = identifier
            item.target = self
            item.action = #selector(changeInputMethodAction(_:))
            if activeInputMethodIdentifier == identifier {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let traditionalToSimplified = NSMenuItem(
            title: NSLocalizedString("Convert Traditional Chinese to Simplified", comment: ""),
            action: #selector(toggleTraditionalToSimplifiedChineseFilterAction(_:)),
            keyEquivalent: "g")
        traditionalToSimplified.keyEquivalentModifierMask = [.command, .control]
        traditionalToSimplified.state = manager.traditionalToSimplifiedChineseFilterEnabled ? .on : .off
        menu.addItem(traditionalToSimplified)

        let simplifiedToTraditional = NSMenuItem(
            title: NSLocalizedString("Convert Simplified Chinese to Traditional", comment: ""),
            action: #selector(toggleSimplifiedToTraditionalChineseFilterAction(_:)),
            keyEquivalent: "")
        simplifiedToTraditional.state = manager.simplifiedToTraditionalChineseFilterEnabled ? .on : .off
        menu.addItem(simplifiedToTraditional)

        let fullToHalf = NSMenuItem(
            title: NSLocalizedString("Convert Full-Width Punctuation to Half-Width", comment: ""),
            action: #selector(toggleFullWidthToHalfWidthFilterAction(_:)),
            keyEquivalent: "")
        fullToHalf.state = manager.fullWidthToHalfWidthFilterEnabled ? .on : .off
        menu.addItem(fullToHalf)

        let halfToFull = NSMenuItem(
            title: NSLocalizedString("Convert Half-Width Punctuation to Full-Width", comment: ""),
            action: #selector(toggleHalfWidthToFullWidthFilterAction(_:)),
            keyEquivalent: "")
        halfToFull.state = manager.halfWidthToFullWidthFilterEnabled ? .on : .off
        menu.addItem(halfToFull)

        let associatedPhrases = NSMenuItem(
            title: NSLocalizedString("Associated Phrases", comment: ""),
            action: #selector(toggleAssociatedPhrasesAroundFilterEnabledAction(_:)),
            keyEquivalent: "")
        associatedPhrases.state = manager.associatedPhrasesAroundFilterEnabled ? .on : .off
        menu.addItem(associatedPhrases)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("OpenVanilla Preferences…", comment: ""),
            action: #selector(showPreferences(_:)),
            keyEquivalent: ""))
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("User Guide", comment: ""),
            action: #selector(openUserGuideAction(_:)),
            keyEquivalent: ""))
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("About OpenVanilla", comment: ""),
            action: #selector(showAboutAction(_:)),
            keyEquivalent: ""))

        return menu
    }

    @objc(activateServer:)
    override func activateServer(_ client: Any!) {
        let manager = OVModuleManager.default
        manager.candidateService?.resetAll()

        let activeInputMethodIdentifier = manager.activeInputMethodIdentifier
        let identifiers = manager.inputMethodIdentifiers
        let excludedIdentifiers = manager.excludedIdentifiers
        let availableInputMethods = identifiers.filter { !excludedIdentifiers.contains($0) }

        if availableInputMethods.isEmpty, let first = identifiers.first {
            var copy = excludedIdentifiers
            copy.removeAll { $0 == first }
            manager.excludedIdentifiers = copy
            manager.selectInputMethod(first)
        } else if !availableInputMethods.contains(activeInputMethodIdentifier ?? ""), let first = identifiers.first {
            manager.selectInputMethod(first)
        }

        let keyboardLayout = manager.alphanumericKeyboardLayout(forInputMethod: manager.activeInputMethodIdentifier)
        overrideKeyboardIfPossible(client, keyboardLayout: keyboardLayout)

        manager.synchronizeActiveInputMethodSettings()

        if inputMethodContext == nil, let activeInputMethod = manager.activeInputMethod {
            inputMethodContext = activeInputMethod.createContext()
        }

        if let context = inputMethodContext, let loader = manager.loaderService {
            context.pointee.startSession(loader)
        }

        startOrStopAssociatedPhrasesContext()
        currentClient = client as AnyObject?

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCandidateSelected(_:)),
            name: NSNotification.Name(rawValue: OVOneDimensionalCandidatePanelImplDidSelectCandidateNotification),
            object: nil)

        if UserDefaults.standard.bool(forKey: OVCheckForUpdateKey) {
            UpdateChecker.sharedInstance.checkForUpdateIfNeeded()
        }
    }

    @objc(deactivateServer:)
    override func deactivateServer(_ client: Any!) {
        let manager = OVModuleManager.default

        stopInputMethodContext()
        stopAssociatedPhrasesContext()

        if readingText.pointee.isEmpty() == false, let textInput = client as? IMKTextInput {
            let emptyReading = NSAttributedString(string: "")
            textInput.setMarkedText(
                emptyReading,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }

        composingText.pointee.commit()
        commitComposition(client)
        composingText.pointee.finishCommit()

        composingText.pointee.clear()
        readingText.pointee.clear()
        manager.candidateService?.resetAll()
        manager.toolTipWindowController.window?.orderOut(self)
        manager.writeOutActiveInputMethodSettings()

        currentClient = nil

        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name(rawValue: OVOneDimensionalCandidatePanelImplDidSelectCandidateNotification),
            object: nil)
    }

    @objc(showPreferences:)
    override func showPreferences(_ sender: Any!) {
        if IMKInputController.instancesRespond(to: #selector(IMKInputController.showPreferences(_:))) {
            super.showPreferences(sender)
        } else {
            (NSApp.delegate as? AppDelegate)?.showPreferences()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc(commitComposition:)
    override func commitComposition(_ sender: Any!) {
        guard composingText.pointee.isCommitted() else {
            return
        }

        let committed = String(cxxString: composingText.pointee.composedCommittedText())
        let filtered = OVModuleManager.default.filteredString(with: committed)
        (sender as? IMKTextInput)?.insertText(filtered, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    @objc(recognizedEvents:)
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    @objc(handleEvent:client:)
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else {
            return false
        }

        let manager = OVModuleManager.default

        if event.type == .flagsChanged {
            let shared = manager.sharedAlphanumericKeyboardLayoutIdentifier
            let inputMethodLayout = manager.alphanumericKeyboardLayout(forInputMethod: manager.activeInputMethodIdentifier)
            if event.modifierFlags.contains(.shift) && manager.fallbackToSharedAlphanumericKeyboardLayoutWhenShiftPressed {
                overrideKeyboardIfPossible(sender, keyboardLayout: shared)
                return false
            }
            overrideKeyboardIfPossible(sender, keyboardLayout: inputMethodLayout)
            return false
        }

        if event.type != .keyDown {
            return false
        }

        if !String(cxxString: readingText.pointee.toolTipText()).isEmpty
            || !String(cxxString: composingText.pointee.toolTipText()).isEmpty
        {
            readingText.pointee.clearToolTip()
            composingText.pointee.clearToolTip()
            manager.toolTipWindowController.window?.orderOut(self)
        }

        let chars = event.characters ?? ""
        let cocoaModifiers = event.modifierFlags
        let virtualKeyCode = event.keyCode

        let capsLock = cocoaModifiers.contains(.capsLock)
        let shift = cocoaModifiers.contains(.shift)
        let ctrl = cocoaModifiers.contains(.control)
        let opt = cocoaModifiers.contains(.option)
        let cmd = cocoaModifiers.contains(.command)
        let numLock = Self.numKeys.contains(virtualKeyCode)

        var unicodeScalar: UInt32 = 0
        if let scalar = chars.unicodeScalars.first {
            unicodeScalar = scalar.value

            if ctrl {
                if unicodeScalar < 27 {
                    unicodeScalar += UInt32(Character("a").unicodeScalars.first!.value - 1)
                } else {
                    switch unicodeScalar {
                    case 27:
                        unicodeScalar = shift ? UInt32(Character("{").unicodeScalars.first!.value) : UInt32(Character("[").unicodeScalars.first!.value)
                    case 28:
                        unicodeScalar = shift ? UInt32(Character("|").unicodeScalars.first!.value) : UInt32(Character("\\").unicodeScalars.first!.value)
                    case 29:
                        unicodeScalar = shift ? UInt32(Character("}").unicodeScalars.first!.value) : UInt32(Character("]").unicodeScalars.first!.value)
                    case 31:
                        unicodeScalar = shift ? UInt32(Character("_").unicodeScalars.first!.value) : UInt32(Character("-").unicodeScalars.first!.value)
                    default:
                        break
                    }
                }
            }

            switch Int(unicodeScalar) {
            case NSUpArrowFunctionKey: unicodeScalar = 30
            case NSDownArrowFunctionKey: unicodeScalar = 31
            case NSLeftArrowFunctionKey: unicodeScalar = 28
            case NSRightArrowFunctionKey: unicodeScalar = 29
            case NSDeleteFunctionKey: unicodeScalar = 127
            case NSHomeFunctionKey: unicodeScalar = 1
            case NSEndFunctionKey: unicodeScalar = 4
            case NSPageUpFunctionKey: unicodeScalar = 11
            case NSPageDownFunctionKey: unicodeScalar = 12
            case NSF1FunctionKey: unicodeScalar = 0x11001
            case NSF2FunctionKey: unicodeScalar = 0x11002
            case NSF3FunctionKey: unicodeScalar = 0x11003
            case NSF4FunctionKey: unicodeScalar = 0x11004
            case NSF5FunctionKey: unicodeScalar = 0x11005
            case NSF6FunctionKey: unicodeScalar = 0x11006
            case NSF7FunctionKey: unicodeScalar = 0x11007
            case NSF8FunctionKey: unicodeScalar = 0x11008
            case NSF9FunctionKey: unicodeScalar = 0x11009
            case NSF10FunctionKey: unicodeScalar = 0x11010
            default:
                break
            }
        }

        guard let loaderService = manager.loaderService else {
            return false
        }

        let key: OVKey
        if unicodeScalar < 128 {
            key = loaderService.pointee.makeOVKey(
                Int32(unicodeScalar),
                opt,
                opt,
                ctrl,
                shift,
                cmd,
                capsLock,
                numLock)
        } else {
            key = loaderService.pointee.makeOVKey(
                std.string(chars),
                opt,
                opt,
                ctrl,
                shift,
                cmd,
                capsLock,
                numLock)
        }

        return handleOVKey(key, client: sender as AnyObject?)
    }

    @objc(handleInputMethodChange:)
    private func handleInputMethodChange(_ notification: Notification) {
        let manager = OVModuleManager.default

        composingText.pointee.clear()
        readingText.pointee.clear()

        stopInputMethodContext()

        if let textInput = currentClient as? IMKTextInput {
            let emptyReading = NSAttributedString(string: "")
            textInput.setMarkedText(
                emptyReading,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }

        composingText.pointee.commit()
        commitComposition(currentClient)

        composingText.pointee.clear()
        readingText.pointee.clear()
        manager.candidateService?.resetAll()
        manager.toolTipWindowController.window?.orderOut(self)

        if inputMethodContext == nil, let activeInputMethod = manager.activeInputMethod {
            inputMethodContext = activeInputMethod.createContext()
        }

        if let context = inputMethodContext, let loader = manager.loaderService {
            context.pointee.startSession(loader)

            let keyboardLayout = manager.alphanumericKeyboardLayout(forInputMethod: manager.activeInputMethodIdentifier)
            overrideKeyboardIfPossible(currentClient, keyboardLayout: keyboardLayout)
        }
    }

    @objc(handleCandidateSelected:)
    private func handleCandidateSelected(_ notification: Notification) {
        guard let inputMethodContext, let candidate = notification.userInfo?[OVOneDimensionalCandidatePanelImplSelectedCandidateStringKey] as? String,
            let index = notification.userInfo?[OVOneDimensionalCandidatePanelImplSelectedCandidateIndexKey] as? NSNumber
        else {
            return
        }

        let manager = OVModuleManager.default
        guard let candidateService = manager.candidateService, let loaderService = manager.loaderService else {
            return
        }

        let panel = candidateService.pointee.currentCandidatePanel()

        let handled: Bool
        if associatedPhrasesContextInUse, let associatedPhrasesContext {
            handled = associatedPhrasesContext.pointee.candidateSelected(
                candidateService,
                std.string(candidate),
                index.uintValue,
                readingText,
                composingText,
                loaderService)
            associatedPhrasesContextInUse = false
        } else {
            handled = inputMethodContext.pointee.candidateSelected(
                candidateService,
                std.string(candidate),
                index.uintValue,
                readingText,
                composingText,
                loaderService)
        }

        if handled {
            panel?.pointee.hide()
            panel?.pointee.cancelEventHandler()
        } else {
            manager.loaderService?.pointee.beep()
            return
        }

        if composingText.pointee.isCommitted() {
            commitComposition(currentClient)
            composingText.pointee.finishCommit()
        }

        updateClientComposingBuffer(currentClient)
    }

    @objc(updateClientComposingBuffer:)
    private func updateClientComposingBuffer(_ sender: Any?) {
        guard let sender = sender as? IMKTextInput else {
            return
        }

        var combinedText = OVTextBufferCombinator(composingText, readingText)
        let attrString = combinedText.combinedAttributedString()
        let selectionRange = combinedText.selectionRange()

        if composingText.pointee.shouldUpdate() || readingText.pointee.shouldUpdate() {
            sender.setMarkedText(
                attrString,
                selectionRange: selectionRange,
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            composingText.pointee.finishUpdate()
            readingText.pointee.finishUpdate()
        }

        var cursorIndex = selectionRange.location
        if cursorIndex == attrString.length, cursorIndex > 0 {
            cursorIndex -= 1
        }

        var lineHeightRect = NSRect(x: 0, y: 0, width: 16, height: 16)
        _ = sender.attributes(forCharacterIndex: cursorIndex, lineHeightRectangle: &lineHeightRect)

        let manager = OVModuleManager.default
        guard let currentCandidatePanel = manager.candidateService?.pointee.currentCandidatePanel() else {
            return
        }

        currentCandidatePanel.pointee.setPanelOrigin(lineHeightRect.origin, lineHeightRect.size.height + 4.0)
        currentCandidatePanel.pointee.updateVisibility()

        var toolTipText = String(cxxString: readingText.pointee.toolTipText())
        if toolTipText.isEmpty {
            toolTipText = String(cxxString: composingText.pointee.toolTipText())
        }

        if !toolTipText.isEmpty {
            var toolTipOrigin = lineHeightRect.origin
            if currentCandidatePanel.pointee.isVisible() {
                toolTipOrigin.y += lineHeightRect.size.height + 4.0
            }

            manager.toolTipWindowController.showTooltip(toolTipText, atPoint: toolTipOrigin)
            manager.toolTipWindowController.window?.orderFront(self)
        }
    }

    @objc(changeInputMethodAction:)
    private func changeInputMethodAction(_ sender: Any?) {
        let item = (sender as? NSDictionary)?[kIMKCommandMenuItemName] as? NSMenuItem
        if let identifier = item?.representedObject as? String {
            OVModuleManager.default.selectInputMethod(identifier)
        }
    }

    @objc(toggleTraditionalToSimplifiedChineseFilterAction:)
    private func toggleTraditionalToSimplifiedChineseFilterAction(_ sender: Any?) {
        let manager = OVModuleManager.default
        manager.traditionalToSimplifiedChineseFilterEnabled.toggle()
        manager.simplifiedToTraditionalChineseFilterEnabled = false
    }

    @objc(toggleSimplifiedToTraditionalChineseFilterAction:)
    private func toggleSimplifiedToTraditionalChineseFilterAction(_ sender: Any?) {
        let manager = OVModuleManager.default
        manager.simplifiedToTraditionalChineseFilterEnabled.toggle()
        manager.traditionalToSimplifiedChineseFilterEnabled = false
    }

    @objc(toggleFullWidthToHalfWidthFilterAction:)
    private func toggleFullWidthToHalfWidthFilterAction(_ sender: Any?) {
        let manager = OVModuleManager.default
        manager.fullWidthToHalfWidthFilterEnabled.toggle()
        manager.halfWidthToFullWidthFilterEnabled = false
    }

    @objc(toggleHalfWidthToFullWidthFilterAction:)
    private func toggleHalfWidthToFullWidthFilterAction(_ sender: Any?) {
        let manager = OVModuleManager.default
        manager.halfWidthToFullWidthFilterEnabled.toggle()
        manager.fullWidthToHalfWidthFilterEnabled = false
    }

    @objc(toggleAssociatedPhrasesAroundFilterEnabledAction:)
    private func toggleAssociatedPhrasesAroundFilterEnabledAction(_ sender: Any?) {
        let manager = OVModuleManager.default
        manager.associatedPhrasesAroundFilterEnabled.toggle()
        startOrStopAssociatedPhrasesContext()
    }

    @objc(openUserGuideAction:)
    private func openUserGuideAction(_ sender: Any?) {
        if let url = URL(string: OVUserGuideURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc(showAboutAction:)
    private func showAboutAction(_ sender: Any?) {
        NSApplication.shared.orderFrontStandardAboutPanel(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc(startOrStopAssociatedPhrasesContext)
    private func startOrStopAssociatedPhrasesContext() {
        let manager = OVModuleManager.default
        if associatedPhrasesContext == nil,
            let associatedPhrasesModule = manager.associatedPhrasesModule,
            manager.associatedPhrasesAroundFilterEnabled
        {
            associatedPhrasesContext = associatedPhrasesModule.createContext()
            if let context = associatedPhrasesContext, let loader = manager.loaderService {
                context.pointee.startSession(loader)
            }
        } else if associatedPhrasesContext != nil, !manager.associatedPhrasesAroundFilterEnabled {
            stopAssociatedPhrasesContext()
        }
        associatedPhrasesContextInUse = false
    }

    @objc(stopAssociatedPhrasesContext)
    private func stopAssociatedPhrasesContext() {
        guard let context = associatedPhrasesContext else {
            return
        }

        if let loader = OVModuleManager.default.loaderService {
            context.pointee.stopSession(loader)
        }

        associatedPhrasesContext = nil
        associatedPhrasesContextInUse = false
    }

    private func stopInputMethodContext() {
        guard let context = inputMethodContext else {
            return
        }

        if let loader = OVModuleManager.default.loaderService {
            context.pointee.stopSession(loader)
        }
        inputMethodContext = nil
    }

    private func handleOVKey(_ key: OVKey, client: AnyObject?) -> Bool {
        guard let inputMethodContext = inputMethodContext else {
            return false
        }

        let manager = OVModuleManager.default
        guard let candidateService = manager.candidateService, let loaderService = manager.loaderService else {
            return false
        }
        var key = key
        var handled = false
        var candidatePanelFallThrough = false

        let panel = candidateService.pointee.currentCandidatePanel()

        if let panel, panel.pointee.isInControl() {
            let result = panel.pointee.handleKey(&key)
            switch result {
            case .Handled:
                return true
            case .CandidateSelected:
                let index = panel.pointee.currentHightlightIndexInCandidateList()
                let candidate = panel.pointee.candidateList()?.pointee.candidateAtIndex(index) ?? std.string("")
                handled = inputMethodContext.pointee.candidateSelected(
                    candidateService,
                    candidate,
                    index,
                    readingText,
                    composingText,
                    loaderService)
                candidatePanelFallThrough = true
            case .Canceled:
                inputMethodContext.pointee.candidateCanceled(
                    candidateService,
                    readingText,
                    composingText,
                    loaderService)
                handled = true
                candidatePanelFallThrough = true
            case .NonCandidatePanelKeyReceived:
                handled = inputMethodContext.pointee.candidateNonPanelKeyReceived(
                    candidateService,
                    &key,
                    readingText,
                    composingText,
                    loaderService)
                candidatePanelFallThrough = true
            case .Invalid:
                manager.loaderService?.pointee.beep()
                return true
            @unknown default:
                break
            }
        }

        if !candidatePanelFallThrough {
            if associatedPhrasesContextInUse, let associatedPhrasesContext {
                handled = associatedPhrasesContext.pointee.handleKey(
                    &key,
                    readingText,
                    composingText,
                    candidateService,
                    loaderService)
            }

            if handled {
                associatedPhrasesContextInUse = true
            } else {
                associatedPhrasesContextInUse = false
                handled = inputMethodContext.pointee.handleKey(
                    &key,
                    readingText,
                    composingText,
                    candidateService,
                    loaderService)
            }
        }

        if composingText.pointee.isCommitted() {
            let commitText = composingText.pointee.composedCommittedText()

            if let associatedPhrasesContext,
                manager.associatedPhrasesAroundFilterEnabled
            {
                var tempReading = OVTextBufferImpl()
                var tempComposing = OVTextBufferImpl()
                associatedPhrasesContextInUse = associatedPhrasesContext.pointee.handleDirectText(
                    commitText,
                    &tempReading,
                    &tempComposing,
                    candidateService,
                    loaderService)

                if tempComposing.isCommitted() {
                    composingText.pointee.finishCommit()
                    composingText.pointee.setText(tempComposing.composedCommittedText())
                    composingText.pointee.commit()
                }
            }

            commitComposition(client)
            composingText.pointee.finishCommit()
        }

        updateClientComposingBuffer(client)
        return handled
    }

    private func overrideKeyboardIfPossible(_ client: Any?, keyboardLayout: String?) {
        guard let keyboardLayout, let client = client as? NSObject else {
            return
        }
        let selector = NSSelectorFromString("overrideKeyboardWithKeyboardNamed:")
        if client.responds(to: selector) {
            _ = client.perform(selector, with: keyboardLayout)
        }
    }
}
