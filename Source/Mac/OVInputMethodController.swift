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
    
    // C++ objects - using UnsafeMutablePointer for manual memory management
    private var composingText: UnsafeMutablePointer<OVTextBufferImpl>?
    private var readingText: UnsafeMutablePointer<OVTextBufferImpl>?
    private var inputMethodContext: UnsafeMutablePointer<OVEventHandlingContext>?
    private var associatedPhrasesContext: UnsafeMutablePointer<OVEventHandlingContext>?
    private var associatedPhrasesContextInUse: Bool = false
    private weak var currentClient: (IMKTextInput & NSObjectProtocol)?
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        // Clean up C++ objects
        if let ctx = inputMethodContext {
            ctx.deallocate()
        }
        if let ctx = associatedPhrasesContext {
            ctx.deallocate()
        }
        if let text = composingText {
            text.deallocate()
        }
        if let text = readingText {
            text.deallocate()
        }
    }
    
    override init(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        
        // Initialize C++ objects
        composingText = UnsafeMutablePointer<OVTextBufferImpl>.allocate(capacity: 1)
        composingText!.initialize(to: OVTextBufferImpl())
        
        readingText = UnsafeMutablePointer<OVTextBufferImpl>.allocate(capacity: 1)
        readingText!.initialize(to: OVTextBufferImpl())
        
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
            // TODO: Create context from active input method
            // This requires C++ interop for createContext() method
        }
        
        if let ctx = inputMethodContext, let loaderService = OVModuleManager.default.loaderService {
            // TODO: Call startSession on context
            // This requires C++ interop
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
            // TODO: Call stopSession and delete context
            // This requires C++ interop
            inputMethodContext?.deallocate()
            inputMethodContext = nil
        }
        
        stopAssociatedPhrasesContext()
        
        // Clean up reading buffer residue if not empty
        if let readingText = readingText, !readingText.pointee.isEmpty() {
            let emptyReading = NSAttributedString(string: "")
            if let client = sender as? IMKTextInput {
                client.setMarkedText(
                    emptyReading,
                    selectionRange: NSRange(location: 0, length: 0),
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
            }
        }
        
        if let composingText = composingText {
            composingText.pointee.commit()
            commitComposition(sender)
            composingText.pointee.finishCommit()
            composingText.pointee.clear()
        }
        
        readingText?.pointee.clear()
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
        guard let composingText = composingText, composingText.pointee.isCommitted() else { return }
        
        let combinedText = String(cString: composingText.pointee.composedCommittedText().c_str())
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
        if let readingText = readingText, let composingText = composingText {
            if !readingText.pointee.toolTipText().empty() || !composingText.pointee.toolTipText().empty() {
                NSLog("clear tooltip")
                readingText.pointee.clearToolTip()
                composingText.pointee.clearToolTip()
                OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
            }
        }
        
        // TODO: Implement key handling logic
        // This requires extensive C++ interop for OVKey creation and handling
        
        return false
    }
    
    // MARK: - Private methods
    
    @objc private func handleInputMethodChange(_ notification: Notification) {
        composingText?.pointee.clear()
        readingText?.pointee.clear()
        
        if let ctx = inputMethodContext, let loaderService = OVModuleManager.default.loaderService {
            // TODO: Stop session and deallocate context
            inputMethodContext?.deallocate()
            inputMethodContext = nil
        }
        
        let emptyReading = NSAttributedString(string: "")
        currentClient?.setMarkedText(
            emptyReading,
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        
        composingText?.pointee.commit()
        commitComposition(currentClient)
        
        composingText?.pointee.clear()
        readingText?.pointee.clear()
        OVModuleManager.default.candidateService?.resetAll()
        OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
        
        if inputMethodContext == nil, let activeInputMethod = OVModuleManager.default.activeInputMethod {
            // TODO: Create new context
        }
        
        if let ctx = inputMethodContext, let loaderService = OVModuleManager.default.loaderService {
            // TODO: Start session
            
            // Update keyboard layout
            let keyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                forInputMethod: OVModuleManager.default.activeInputMethodIdentifier
            )
            currentClient?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
        }
    }
    
    @objc private func handleCandidateSelected(_ notification: Notification) {
        // TODO: Implement candidate selection handling
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
        if let url = URL(string: "OVUserGuideURLString") {  // TODO: Get actual constant value
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
            // TODO: Create associated phrases context
            // associatedPhrasesContext = associatedPhrasesModule.createContext()
            // TODO: Start session
        } else if associatedPhrasesContext != nil && !OVModuleManager.default.associatedPhrasesAroundFilterEnabled {
            stopAssociatedPhrasesContext()
        }
        associatedPhrasesContextInUse = false
    }
    
    private func stopAssociatedPhrasesContext() {
        guard let ctx = associatedPhrasesContext else { return }
        
        // TODO: Stop session
        ctx.deallocate()
        associatedPhrasesContext = nil
        associatedPhrasesContextInUse = false
    }
}