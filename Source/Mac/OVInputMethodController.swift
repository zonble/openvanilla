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

import InputMethodKit
import Foundation
import Cocoa
import OpenVanilla
import OpenVanillaImpl
import LoaderService
import ModuleManager
import TooltipUI

@objc(OVInputMethodController)
class OVInputMethodController: IMKInputController {
    
    // C++ objects using Swift C++ interop with proper namespace qualification
    private var composingText = OpenVanilla.OVTextBufferImpl()
    private var readingText = OpenVanilla.OVTextBufferImpl()
    private var inputMethodContext: OpenVanilla.OVEventHandlingContext?
    private var associatedPhrasesContext: OpenVanilla.OVEventHandlingContext?
    private var associatedPhrasesContextInUse: Bool = false
    private weak var currentClient: (IMKTextInput & NSObjectProtocol)?
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        // C++ objects are automatically cleaned up by Swift
        if let ctx = inputMethodContext, let loaderService = OVModuleManager.default.loaderService {
            ctx.stopSession(loaderService)
        }
        if let ctx = associatedPhrasesContext, let loaderService = OVModuleManager.default.loaderService {
            ctx.stopSession(loaderService)
        }
    }
    
    override init(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        
        // C++ objects are automatically initialized with proper namespace
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInputMethodChange(_:)),
            name: NSNotification.Name("OVModuleManagerDidUpdateActiveInputMethodNotification"),
            object: OVModuleManager.default
        )
    }
    
    override func menu() -> NSMenu? {
        let menu = NSMenu()
        
        let activeInputMethodIdentifier = OVModuleManager.default.activeInputMethodIdentifier
        let inputMethodIdentifiers = OVModuleManager.default.inputMethodIdentifiers
        let excludedIdentifiers = OVModuleManager.default.excludedIdentifiers
        
        for identifier in inputMethodIdentifiers {
            if excludedIdentifiers.contains(identifier) {
                continue
            }
            
            let item = NSMenuItem()
            item.title = OVModuleManager.default.localizedInputMethodName(identifier)
            item.representedObject = identifier
            item.target = self
            item.action = #selector(changeInputMethodAction(_:))
            
            if activeInputMethodIdentifier == identifier {
                item.state = .on
            }
            
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        var filterItem = NSMenuItem(
            title: NSLocalizedString("Convert Traditional Chinese to Simplified", comment: ""),
            action: #selector(toggleTraditionalToSimplifiedChineseFilterAction(_:)),
            keyEquivalent: "g"
        )
        filterItem.keyEquivalentModifierMask = [.command, .control]
        filterItem.state = OVModuleManager.default.traditionalToSimplifiedChineseFilterEnabled ? .on : .off
        menu.addItem(filterItem)
        
        filterItem = NSMenuItem(
            title: NSLocalizedString("Convert Simplified Chinese to Traditional", comment: ""),
            action: #selector(toggleSimplifiedToTraditionalChineseFilterAction(_:)),
            keyEquivalent: ""
        )
        filterItem.state = OVModuleManager.default.simplifiedToTraditionalChineseFilterEnabled ? .on : .off
        menu.addItem(filterItem)
        
        filterItem = NSMenuItem(
            title: NSLocalizedString("Associated Phrases", comment: ""),
            action: #selector(toggleAssociatedPhrasesAroundFilterEnabledAction(_:)),
            keyEquivalent: ""
        )
        filterItem.state = OVModuleManager.default.associatedPhrasesAroundFilterEnabled ? .on : .off
        menu.addItem(filterItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let preferenceMenuItem = NSMenuItem(
            title: NSLocalizedString("OpenVanilla Preferences…", comment: ""),
            action: #selector(showPreferences(_:)),
            keyEquivalent: ""
        )
        menu.addItem(preferenceMenuItem)
        
        let userManualItem = NSMenuItem(
            title: NSLocalizedString("User Guide", comment: ""),
            action: #selector(openUserGuideAction(_:)),
            keyEquivalent: ""
        )
        menu.addItem(userManualItem)
        
        let aboutMenuItem = NSMenuItem(
            title: NSLocalizedString("About OpenVanilla", comment: ""),
            action: #selector(showAboutAction(_:)),
            keyEquivalent: ""
        )
        menu.addItem(aboutMenuItem)
        
        return menu
    }
    
    // MARK: IMKStateSetting protocol methods
    
    override func activateServer(_ sender: Any!) {
        OVModuleManager.default.candidateService?.resetAll()
        
        let activeInputMethodIdentifier = OVModuleManager.default.activeInputMethodIdentifier
        let identifiers = OVModuleManager.default.inputMethodIdentifiers
        let excludedIdentifiers = OVModuleManager.default.excludedIdentifiers
        
        var availableInputMethods: [String] = []
        for identifier in identifiers {
            if !excludedIdentifiers.contains(identifier) {
                availableInputMethods.append(identifier)
            }
        }
        
        if availableInputMethods.isEmpty {
            let first = identifiers.first!
            var excludedIdentifiersCopy = Array(excludedIdentifiers)
            excludedIdentifiersCopy.removeAll { $0 == first }
            OVModuleManager.default.excludedIdentifiers = excludedIdentifiersCopy
            OVModuleManager.default.selectInputMethod(first)
        } else if !availableInputMethods.contains(activeInputMethodIdentifier) {
            let first = identifiers.first!
            OVModuleManager.default.selectInputMethod(first)
        }
        
        let keyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
            forInputMethod: OVModuleManager.default.activeInputMethodIdentifier
        )
        
        if let client = sender as? (IMKTextInput & NSObjectProtocol) {
            client.overrideKeyboard(withKeyboardNamed: keyboardLayout)
        }
        
        OVModuleManager.default.synchronizeActiveInputMethodSettings()
        
        if inputMethodContext == nil, let activeInputMethod = OVModuleManager.default.activeInputMethod {
            inputMethodContext = activeInputMethod.createContext()
        }
        
        if let ctx = inputMethodContext, let loaderService = OVModuleManager.default.loaderService {
            ctx.startSession(loaderService)
        }
        
        startOrStopAssociatedPhrasesContext()
        
        currentClient = sender as? (IMKTextInput & NSObjectProtocol)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCandidateSelected(_:)),
            name: NSNotification.Name("OVOneDimensionalCandidatePanelImplDidSelectCandidateNotification"),
            object: nil
        )
        
        if UserDefaults.standard.bool(forKey: "OVCheckForUpdateKey") {
            UpdateChecker.shared.checkForUpdateIfNeeded()
        }
    }
    
    override func deactivateServer(_ sender: Any!) {
        if let ctx = inputMethodContext, let loaderService = OVModuleManager.default.loaderService {
            ctx.stopSession(loaderService)
            inputMethodContext = nil
        }
        
        stopAssociatedPhrasesContext()
        
        // Clean up reading buffer residue if not empty
        if !readingText.isEmpty() {
            let emptyReading = NSAttributedString(string: "")
            currentClient?.setMarkedText(
                emptyReading,
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        }
        
        composingText.commit()
        commitComposition(currentClient)
        composingText.finishCommit()
        
        composingText.clear()
        readingText.clear()
        OVModuleManager.default.candidateService?.resetAll()
        OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
        OVModuleManager.default.writeOutActiveInputMethodSettings()
        
        currentClient = nil
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("OVOneDimensionalCandidatePanelImplDidSelectCandidateNotification"),
            object: nil
        )
    }
    
    override func showPreferences(_ sender: Any?) {
        // Show the preferences panel and make the IME app itself the focus
        if type(of: self).instancesRespond(to: #selector(showPreferences(_:))) {
            super.showPreferences(sender)
        } else if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showPreferences()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    override func commitComposition(_ sender: Any!) {
        if composingText.isCommitted() {
            let combinedText = String(composingText.composedCommittedText())
            let filteredText = OVModuleManager.default.filteredString(with: combinedText)
            if let client = sender as? IMKTextInput {
                client.insertText(
                    filteredText,
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
            }
        }
    }
    
    override func recognizedEvents(_ sender: Any!) -> NSEventMask {
        return [.keyDown, .flagsChanged]
    }
    
    override func handleEvent(_ event: NSEvent!, client: Any!) -> Bool {
        guard let event = event else { return false }
        
        if event.type == .flagsChanged {
            let sharedKeyboardLayout = OVModuleManager.default.sharedAlphanumericKeyboardLayoutIdentifier
            let inputMethodKeyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                forInputMethod: OVModuleManager.default.activeInputMethodIdentifier
            )
            
            if event.modifierFlags.contains(.shift) &&
               OVModuleManager.default.fallbackToSharedAlphanumericKeyboardLayoutWhenShiftPressed {
                if let client = client as? (IMKTextInput & NSObjectProtocol) {
                    client.overrideKeyboard(withKeyboardNamed: sharedKeyboardLayout)
                }
                return false
            }
            
            if let client = client as? (IMKTextInput & NSObjectProtocol) {
                client.overrideKeyboard(withKeyboardNamed: inputMethodKeyboardLayout)
            }
            return false
        }
        
        if event.type != .keyDown {
            return false
        }
        
        // Clear tooltips if present - fixed string conversion for Swift C++ interop
        if !String(readingText.toolTipText()).isEmpty || !String(composingText.toolTipText()).isEmpty {
            NSLog("clear tooltip")
            readingText.clearToolTip()
            composingText.clearToolTip()
            OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
        }
        
        let chars = event.characters ?? ""
        let cocoaModifiers = event.modifierFlags
        let virtualKeyCode = event.keyCode
        
        let capsLock = cocoaModifiers.contains(.capsLock)
        let shift = cocoaModifiers.contains(.shift)
        let ctrl = cocoaModifiers.contains(.control)
        let opt = cocoaModifiers.contains(.option)
        let cmd = cocoaModifiers.contains(.command)
        let numLock = false
        
        let numKeys: [UInt16] = [
            0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5b, 0x5c, 0x41, 0x45, 0x4e, 0x43, 0x4b, 0x51
        ]
        
        let isNumpadKey = numKeys.contains(virtualKeyCode)
        
        var key: OpenVanilla.OVKey
        var unicharCode: UniChar = 0
        
        if !chars.isEmpty {
            unicharCode = chars.utf16.first!
            
            // Map Ctrl-[A-Z] to a char code
            if cocoaModifiers.contains(.control) {
                if unicharCode < 27 {
                    unicharCode += (Character("a").asciiValue! - 1)
                } else {
                    switch unicharCode {
                    case 27:
                        unicharCode = shift ? Character("{").asciiValue! : Character("[").asciiValue!
                    case 28:
                        unicharCode = shift ? Character("|").asciiValue! : Character("\\").asciiValue!
                    case 29:
                        unicharCode = shift ? Character("}").asciiValue! : Character("]").asciiValue!
                    case 31:
                        unicharCode = shift ? Character("_").asciiValue! : Character("-").asciiValue!
                    default:
                        break
                    }
                }
            }
            
            var remappedKeyCode = unicharCode
            
            // Remap function key codes - fixed namespace references
            switch unicharCode {
            case UInt16(NSUpArrowFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.Up.rawValue)
            case UInt16(NSDownArrowFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.Down.rawValue)
            case UInt16(NSLeftArrowFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.Left.rawValue)
            case UInt16(NSRightArrowFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.Right.rawValue)
            case UInt16(NSDeleteFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.Delete.rawValue)
            case UInt16(NSHomeFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.Home.rawValue)
            case UInt16(NSEndFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.End.rawValue)
            case UInt16(NSPageUpFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.PageUp.rawValue)
            case UInt16(NSPageDownFunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.PageDown.rawValue)
            case UInt16(NSF1FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F1.rawValue)
            case UInt16(NSF2FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F2.rawValue)
            case UInt16(NSF3FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F3.rawValue)
            case UInt16(NSF4FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F4.rawValue)
            case UInt16(NSF5FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F5.rawValue)
            case UInt16(NSF6FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F6.rawValue)
            case UInt16(NSF7FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F7.rawValue)
            case UInt16(NSF8FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F8.rawValue)
            case UInt16(NSF9FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F9.rawValue)
            case UInt16(NSF10FunctionKey):
                remappedKeyCode = UInt16(OpenVanilla.OVKeyCode.F10.rawValue)
            default:
                break
            }
            
            unicharCode = remappedKeyCode
        }
        
        if let loaderService = OVModuleManager.default.loaderService {
            if unicharCode < 128 {
                key = loaderService.makeOVKey(
                    unicharCode, opt, opt, ctrl, shift, cmd, capsLock, isNumpadKey
                )
            } else {
                key = loaderService.makeOVKey(
                    String(chars), opt, opt, ctrl, shift, cmd, capsLock, isNumpadKey
                )
            }
            
            return handleOVKey(key, client: client)
        }
        
        return false
    }
    
    // MARK: - Private methods
    
    private func handleOVKey(_ key: OpenVanilla.OVKey, client: Any?) -> Bool {
        guard let inputMethodContext = inputMethodContext else {
            return false
        }
        
        var handled = false
        var candidatePanelFallThrough = false
        
        // Handle candidate panel interaction
        if let candidateService = OVModuleManager.default.candidateService,
           let panel = candidateService.currentCandidatePanel(),
           panel.isInControl() {
            
            let result = panel.handleKey(key)
            switch result {
            case .Handled:
                return true
                
            case .CandidateSelected:
                let index = panel.currentHightlightIndexInCandidateList()
                let candidate = panel.candidateList()?.candidateAtIndex(index) ?? ""
                handled = inputMethodContext.candidateSelected(
                    candidateService, candidate, index, readingText, composingText,
                    OVModuleManager.default.loaderService!
                )
                candidatePanelFallThrough = true
                
            case .Canceled:
                inputMethodContext.candidateCanceled(
                    candidateService, readingText, composingText,
                    OVModuleManager.default.loaderService!
                )
                handled = true
                candidatePanelFallThrough = true
                
            case .NonCandidatePanelKeyReceived:
                handled = inputMethodContext.candidateNonPanelKeyReceived(
                    candidateService, key, readingText, composingText,
                    OVModuleManager.default.loaderService!
                )
                candidatePanelFallThrough = true
                
            case .Invalid:
                OVModuleManager.default.loaderService?.beep()
                return true
                
            default:
                break
            }
        }
        
        if !candidatePanelFallThrough {
            if associatedPhrasesContextInUse, let associatedPhrasesContext = associatedPhrasesContext {
                handled = associatedPhrasesContext.handleKey(
                    key, readingText, composingText,
                    OVModuleManager.default.candidateService!,
                    OVModuleManager.default.loaderService!
                )
            }
            
            if handled {
                associatedPhrasesContextInUse = true
            } else {
                associatedPhrasesContextInUse = false
                handled = inputMethodContext.handleKey(
                    key, readingText, composingText,
                    OVModuleManager.default.candidateService!,
                    OVModuleManager.default.loaderService!
                )
            }
        }
        
        if composingText.isCommitted() {
            let commitText = String(composingText.composedCommittedText())
            
            // Toggling menu item does not deactivate the current session
            if let associatedPhrasesContext = associatedPhrasesContext,
               OVModuleManager.default.associatedPhrasesAroundFilterEnabled {
                
                var tempReading = OpenVanilla.OVTextBufferImpl()
                var tempComposing = OpenVanilla.OVTextBufferImpl()
                
                associatedPhrasesContextInUse = associatedPhrasesContext.handleDirectText(
                    commitText, tempReading, tempComposing,
                    OVModuleManager.default.candidateService!,
                    OVModuleManager.default.loaderService!
                )
                
                if tempComposing.isCommitted() {
                    composingText.finishCommit()
                    composingText.setText(String(tempComposing.composedCommittedText()))
                    composingText.commit()
                }
            }
            
            commitComposition(client)
            composingText.finishCommit()
        }
        
        updateClientComposingBuffer(client)
        return handled
    }
    
    @objc private func handleInputMethodChange(_ notification: Notification) {
        composingText.clear()
        readingText.clear()
        
        if let ctx = inputMethodContext, let loaderService = OVModuleManager.default.loaderService {
            ctx.stopSession(loaderService)
            inputMethodContext = nil
        }
        
        let emptyReading = NSAttributedString(string: "")
        currentClient?.setMarkedText(
            emptyReading,
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        composingText.commit()
        
        commitComposition(currentClient)
        
        composingText.clear()
        readingText.clear()
        OVModuleManager.default.candidateService?.resetAll()
        OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
        
        if inputMethodContext == nil, let activeInputMethod = OVModuleManager.default.activeInputMethod {
            inputMethodContext = activeInputMethod.createContext()
        }
        
        if let ctx = inputMethodContext, let loaderService = OVModuleManager.default.loaderService {
            ctx.startSession(loaderService)
            
            // Update keyboard layout
            let keyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                forInputMethod: OVModuleManager.default.activeInputMethodIdentifier
            )
            currentClient?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
        }
    }
    
    @objc private func handleCandidateSelected(_ notification: Notification) {
        guard let inputMethodContext = inputMethodContext else {
            return
        }
        
        let dict = notification.userInfo ?? [:]
        let candidate = dict["OVOneDimensionalCandidatePanelImplSelectedCandidateStringKey"] as? String ?? ""
        let index = dict["OVOneDimensionalCandidatePanelImplSelectedCandidateIndexKey"] as? Int ?? 0
        
        let manager = OVModuleManager.default
        guard let candidateService = manager.candidateService,
              let panel = candidateService.currentCandidatePanel(),
              let loaderService = manager.loaderService else {
            return
        }
        
        let handled: Bool
        if associatedPhrasesContextInUse, let associatedPhrasesContext = associatedPhrasesContext {
            handled = associatedPhrasesContext.candidateSelected(
                candidateService, candidate, index, readingText, composingText, loaderService
            )
            associatedPhrasesContextInUse = false
        } else {
            handled = inputMethodContext.candidateSelected(
                candidateService, candidate, index, readingText, composingText, loaderService
            )
        }
        
        if handled {
            panel.hide()
            panel.cancelEventHandler()
        } else {
            loaderService.beep()
            return
        }
        
        if composingText.isCommitted() {
            commitComposition(currentClient)
            composingText.finishCommit()
        }
        
        updateClientComposingBuffer(currentClient)
    }
    
    private func updateClientComposingBuffer(_ sender: Any?) {
        let combinedText = OpenVanilla.OVTextBufferCombinator(composingText, readingText)
        let attrString = combinedText.combinedAttributedString()
        let selectionRange = combinedText.selectionRange()
        
        if composingText.shouldUpdate() || readingText.shouldUpdate() {
            if let client = sender as? IMKTextInput {
                client.setMarkedText(
                    attrString,
                    selectionRange: selectionRange,
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
            }
            
            composingText.finishUpdate()
            readingText.finishUpdate()
        }
        
        var cursorIndex = selectionRange.location
        if cursorIndex == attrString.length && cursorIndex > 0 {
            cursorIndex -= 1
        }
        
        var lineHeightRect = NSRect(x: 0.0, y: 0.0, width: 16.0, height: 16.0)
        
        if let client = sender as? IMKTextInput {
            let attr = client.attributesForCharacterIndex(cursorIndex, lineHeightRectangle: &lineHeightRect)
            
            // Fall back to index 0 if no attributes are reported at cursorIndex
            if attr?.isEmpty == true {
                let _ = client.attributesForCharacterIndex(0, lineHeightRectangle: &lineHeightRect)
            }
        }
        
        if let candidateService = OVModuleManager.default.candidateService,
           let currentCandidatePanel = candidateService.currentCandidatePanel() {
            currentCandidatePanel.setPanelOrigin(lineHeightRect.origin, lineHeightRect.size.height + 4.0)
            currentCandidatePanel.updateVisibility()
        }
        
        // Fixed string conversion for Swift C++ interop
        var toolTipText = String(readingText.toolTipText())
        if toolTipText.isEmpty {
            toolTipText = String(composingText.toolTipText())
        }
        
        if !toolTipText.isEmpty {
            var toolTipOrigin = lineHeightRect.origin
            if let candidateService = OVModuleManager.default.candidateService,
               let currentCandidatePanel = candidateService.currentCandidatePanel(),
               currentCandidatePanel.isVisible() {
                toolTipOrigin.y += lineHeightRect.size.height + 4.0
            }
            
            OVModuleManager.default.toolTipWindowController.showTooltip(toolTipText, at: toolTipOrigin)
            OVModuleManager.default.toolTipWindowController.window?.orderFront(self)
        }
    }
    
    @objc private func changeInputMethodAction(_ sender: Any?) {
        if let menuItem = sender as? NSMenuItem,
           let identifier = menuItem.representedObject as? String {
            OVModuleManager.default.selectInputMethod(identifier)
        }
    }
    
    @objc private func toggleTraditionalToSimplifiedChineseFilterAction(_ sender: Any?) {
        let manager = OVModuleManager.default
        manager.traditionalToSimplifiedChineseFilterEnabled.toggle()
        manager.simplifiedToTraditionalChineseFilterEnabled = false
    }
    
    @objc private func toggleSimplifiedToTraditionalChineseFilterAction(_ sender: Any?) {
        let manager = OVModuleManager.default
        manager.simplifiedToTraditionalChineseFilterEnabled.toggle()
        manager.traditionalToSimplifiedChineseFilterEnabled = false
    }
    
    @objc private func toggleAssociatedPhrasesAroundFilterEnabledAction(_ sender: Any?) {
        let manager = OVModuleManager.default
        manager.associatedPhrasesAroundFilterEnabled.toggle()
        startOrStopAssociatedPhrasesContext()
    }
    
    @objc private func openUserGuideAction(_ sender: Any?) {
        if let url = URL(string: "https://openvanilla.org/docs/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func showAboutAction(_ sender: Any?) {
        NSApplication.shared.orderFrontStandardAboutPanel(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    private func startOrStopAssociatedPhrasesContext() {
        if associatedPhrasesContext == nil,
           let associatedPhrasesModule = OVModuleManager.default.associatedPhrasesModule,
           OVModuleManager.default.associatedPhrasesAroundFilterEnabled {
            associatedPhrasesContext = associatedPhrasesModule.createContext()
            if let ctx = associatedPhrasesContext, let loaderService = OVModuleManager.default.loaderService {
                ctx.startSession(loaderService)
            }
        } else if associatedPhrasesContext != nil && !OVModuleManager.default.associatedPhrasesAroundFilterEnabled {
            stopAssociatedPhrasesContext()
        }
        associatedPhrasesContextInUse = false
    }
    
    private func stopAssociatedPhrasesContext() {
        guard let ctx = associatedPhrasesContext else { return }
        
        if let loaderService = OVModuleManager.default.loaderService {
            ctx.stopSession(loaderService)
        }
        associatedPhrasesContext = nil
        associatedPhrasesContextInUse = false
    }
}