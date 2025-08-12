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
    
    // C++ objects using Swift C++ interop
    private var composingText = OVTextBufferImplCpp()
    private var readingText = OVTextBufferImplCpp()
    private var inputMethodContext: OVEventHandlingContextCpp?
    private var associatedPhrasesContext: OVEventHandlingContextCpp?
    private var associatedPhrasesContextInUse: Bool = false
    private weak var currentClient: (IMKTextInput & NSObjectProtocol)?
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        // C++ objects are automatically cleaned up
        if let ctx = inputMethodContext {
            if let loaderService = OVModuleManager.default.loaderService {
                ctx.stopSession(loaderService)
            }
        }
        if let ctx = associatedPhrasesContext {
            if let loaderService = OVModuleManager.default.loaderService {
                ctx.stopSession(loaderService)
            }
        }
    }
    
    override init(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        
        // C++ objects are automatically initialized
        // composingText and readingText are already initialized by their default constructors
        
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
    
    // MARK: - IMKStateSetting protocol methods
    
    override func activateServer(_ sender: Any!) {
        guard let candidateService = OVModuleManager.default.candidateService else { return }
        candidateService.resetAll()
        
        let activeInputMethodIdentifier = OVModuleManager.default.activeInputMethodIdentifier
        let identifiers = OVModuleManager.default.inputMethodIdentifiers
        let excludedIdentifiers = OVModuleManager.default.excludedIdentifiers
        let availableInputMethods = identifiers.filter { !excludedIdentifiers.contains($0) }
        
        if availableInputMethods.isEmpty {
            if let first = identifiers.first {
                var excludedIdentifiersCopy = excludedIdentifiers
                excludedIdentifiersCopy.removeAll { $0 == first }
                OVModuleManager.default.excludedIdentifiers = excludedIdentifiersCopy
                OVModuleManager.default.selectInputMethod(first)
            }
        } else if !availableInputMethods.contains(activeInputMethodIdentifier) {
            if let first = identifiers.first {
                OVModuleManager.default.selectInputMethod(first)
            }
        }
        
        let keyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
            forInputMethod: OVModuleManager.default.activeInputMethodIdentifier
        )
        
        if let client = sender as? NSObjectProtocol,
           client.responds(to: #selector(IMKTextInput.overrideKeyboard(withKeyboardNamed:))) {
            (client as! IMKTextInput).overrideKeyboard(withKeyboardNamed: keyboardLayout)
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
            UpdateChecker.sharedInstance.checkForUpdateIfNeeded()
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
            if let client = sender as? IMKTextInput {
                client.setMarkedText(
                    emptyReading,
                    selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
            }
        }
        
        composingText.commit()
        commitComposition(sender)
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
    
    override func showPreferences(_ sender: Any!) {
        // Show the preferences panel, and also make the IME app itself the focus
        if IMKInputController.instancesRespond(to: #selector(IMKInputController.showPreferences(_:))) {
            super.showPreferences(sender)
        } else {
            (NSApp.delegate as? AppDelegate)?.showPreferences()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    
    override func commitComposition(_ sender: Any!) {
        guard composingText.isCommitted() else { return }
        
        let combinedText = String(cString: composingText.composedCommittedText().c_str())
        let filteredText = OVModuleManager.default.filteredString(with: combinedText)
        
        if let client = sender as? IMKTextInput {
            client.insertText(
                filteredText,
                replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
            )
        }
    }
    
    override func recognizedEvents(_ sender: Any!) -> NSEvent.EventTypeMask {
        return [.keyDown, .flagsChanged]
    }
    
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        if event.type == .flagsChanged {
            let sharedKeyboardLayout = OVModuleManager.default.sharedAlphanumericKeyboardLayoutIdentifier()
            let inputMethodKeyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                forInputMethod: OVModuleManager.default.activeInputMethodIdentifier
            )
            
            if (event.modifierFlags.contains(.shift) &&
                OVModuleManager.default.fallbackToSharedAlphanumericKeyboardLayoutWhenShiftPressed) {
                if let client = sender as? IMKTextInput {
                    client.overrideKeyboard(withKeyboardNamed: sharedKeyboardLayout)
                }
                return false
            }
            
            if let client = sender as? IMKTextInput {
                client.overrideKeyboard(withKeyboardNamed: inputMethodKeyboardLayout)
            }
            return false
        }
        
        if event.type != .keyDown {
            return false
        }
        
        // Clear tooltips if present
        if !readingText.toolTipText().empty() || !composingText.toolTipText().empty() {
            NSLog("clear tooltip")
            readingText.clearToolTip()
            composingText.clearToolTip()
            OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
        }
        
        // Convert NSEvent to OVKey and handle it
        guard let loaderService = OVModuleManager.default.loaderService else { return false }
        
        let characters = event.characters ?? ""
        let modifiers = event.modifierFlags
        
        let opt = modifiers.contains(.option)
        let ctrl = modifiers.contains(.control)
        let shift = modifiers.contains(.shift)
        let cmd = modifiers.contains(.command)
        let capsLock = modifiers.contains(.capsLock)
        let numLock = false // Simplified for now
        
        let key: OVKeyCpp
        
        if let firstChar = characters.first, firstChar.isASCII {
            let keyCode = Int(firstChar.asciiValue!)
            key = loaderService.makeOVKey(keyCode, opt, opt, ctrl, shift, cmd, capsLock, numLock)
        } else {
            let keyString = characters
            key = loaderService.makeOVKey(keyString, opt, opt, ctrl, shift, cmd, capsLock, numLock)
        }
        
        return handleOVKey(key, client: sender)
    }
    
    
    // MARK: - Private methods
    
    private func handleOVKey(_ key: OVKeyCpp, client: Any?) -> Bool {
        guard let inputMethodContext = inputMethodContext else { return false }
        
        var handled = false
        var candidatePanelFallThrough = false
        
        // Handle candidate panel if it's in control
        if let candidateService = OVModuleManager.default.candidateService,
           let panel = candidateService.currentCandidatePanel() {
            // TODO: Implement candidate panel key handling
            // This requires proper candidate panel C++ interop
        }
        
        if !candidatePanelFallThrough {
            // Handle the key with the input method context
            if let loaderService = OVModuleManager.default.loaderService {
                handled = inputMethodContext.handleKey(key, candidateService: OVModuleManager.default.candidateService, 
                                                     readingText: readingText, composingText: composingText, 
                                                     loaderService: loaderService)
            }
        }
        
        // Handle associated phrases context if needed
        if !handled && associatedPhrasesContextInUse,
           let associatedPhrasesContext = associatedPhrasesContext,
           let loaderService = OVModuleManager.default.loaderService {
            handled = associatedPhrasesContext.handleKey(key, candidateService: OVModuleManager.default.candidateService,
                                                       readingText: readingText, composingText: composingText,
                                                       loaderService: loaderService)
        }
        
        if handled {
            if composingText.isCommitted() {
                commitComposition(client)
                composingText.finishCommit()
            }
            
            updateClientComposingBuffer(client)
        }
        
        return handled
    }
    
    private func updateClientComposingBuffer(_ sender: Any?) {
        let combinedText = OVTextBufferCombinatorCpp(composingText, readingText)
        let attrString = combinedText.combinedAttributedString()
        let selectionRange = combinedText.selectionRange()
        
        if composingText.shouldUpdate() || readingText.shouldUpdate() {
            if let client = sender as? IMKTextInput {
                client.setMarkedText(attrString, selectionRange: selectionRange, 
                                   replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            }
            
            composingText.finishUpdate()
            readingText.finishUpdate()
        }
        
        // Handle tooltip positioning
        var cursorIndex = selectionRange.location
        if cursorIndex == attrString.length && cursorIndex > 0 {
            cursorIndex -= 1
        }
        
        var lineHeightRect = NSRect(x: 0.0, y: 0.0, width: 16.0, height: 16.0)
        if let client = sender as? IMKTextInput {
            do {
                let attr = try client.attributes(forCharacterIndex: cursorIndex, lineHeightRectangle: &lineHeightRect)
                if attr.isEmpty {
                    _ = try client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)
                }
            } catch {
                // Handle exception silently
            }
        }
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
        
        if let activeInputMethod = OVModuleManager.default.activeInputMethod {
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
        guard let inputMethodContext = inputMethodContext else { return }
        
        guard let userInfo = notification.userInfo,
              let candidate = userInfo["OVOneDimensionalCandidatePanelImplSelectedCandidateStringKey"] as? String,
              let index = userInfo["OVOneDimensionalCandidatePanelImplSelectedCandidateIndexKey"] as? Int else {
            return
        }
        
        let manager = OVModuleManager.default
        guard let candidateService = manager.candidateService,
              let panel = candidateService.currentCandidatePanel(),
              let loaderService = manager.loaderService else { return }
        
        var handled = false
        
        if associatedPhrasesContextInUse, let associatedPhrasesContext = associatedPhrasesContext {
            handled = associatedPhrasesContext.candidateSelected(candidateService, candidate: candidate, 
                                                               index: UInt(index), readingText: readingText, 
                                                               composingText: composingText, loaderService: loaderService)
            associatedPhrasesContextInUse = false
        } else {
            handled = inputMethodContext.candidateSelected(candidateService, candidate: candidate,
                                                         index: UInt(index), readingText: readingText,
                                                         composingText: composingText, loaderService: loaderService)
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
        // Get the user guide URL from OpenVanilla constants
        let urlString = "https://openvanilla.org/documentation/"  // Default fallback
        if let url = URL(string: urlString) {
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