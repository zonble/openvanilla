import Foundation
import InputMethodKit
import LoaderService
import ModuleManager
import OpenVanillaImpl
import TooltipUI

@objc(OVInputMethodController)
class InputController: IMKInputController {
    fileprivate var composingText: UnsafeMutablePointer<OpenVanilla.OVTextBufferImpl>! = nil
    fileprivate var readingText: UnsafeMutablePointer<OpenVanilla.OVTextBufferImpl>! = nil
    fileprivate var inputMethodContext: UnsafeMutablePointer<OpenVanilla.OVEventHandlingContext>? = nil
    fileprivate var associatedPhrasesContext: UnsafeMutablePointer<OpenVanilla.OVEventHandlingContext>? = nil
    fileprivate var associatedPhrasesContextInUse = false
    fileprivate var currentClient: IMKTextInput?

    deinit {
        NotificationCenter.default.removeObserver(self)
        composingText.deinitialize(count: 1)
        composingText.deallocate()
        readingText.deinitialize(count: 1)
        readingText.deallocate()
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        let composing = UnsafeMutablePointer<OpenVanilla.OVTextBufferImpl>.allocate(capacity: 1)
        composing.initialize(to: OpenVanilla.OVTextBufferImpl())
        self.composingText = composing

        let reading = UnsafeMutablePointer<OpenVanilla.OVTextBufferImpl>.allocate(capacity: 1)
        reading.initialize(to: OpenVanilla.OVTextBufferImpl())
        self.readingText = reading

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInputMethodChange(_:)),
            name: NSNotification.Name.OVModuleManagerDidUpdateActiveInputMethod,
            object: OVModuleManager.default)
    }

    override func menu() -> NSMenu {
        let menu = NSMenu()
        let activeInputMethodIdentifier = OVModuleManager.default.activeInputMethodIdentifier
        let inputMethodIdentifiers = OVModuleManager.default.inputMethodIdentifiers
        for identifier in inputMethodIdentifiers {
            let item = NSMenuItem()
            item.title = OVModuleManager.default.localizedInputMethodName(identifier)
            item.representedObject = identifier
            item.target = self
            item.action = #selector(changeInputMethodAction(_:))
            if let activeInputMethodIdentifier = activeInputMethodIdentifier as? String,
                activeInputMethodIdentifier == identifier
            {
                item.state = .on
            }
            menu.addItem(item)
        }

        let tc2scItem = NSMenuItem(
            title: NSLocalizedString("Convert Traditional Chinese to Simplified", comment: ""),
            action: #selector(toggleTraditionalToSimplifiedChineseFilterAction(_:)),
            keyEquivalent: "g")
        tc2scItem.keyEquivalentModifierMask = [.command, .control]
        tc2scItem.state =
            OVModuleManager.default.traditionalToSimplifiedChineseFilterEnabled ? .on : .off
        menu.addItem(tc2scItem)

        let sc2tcItem = NSMenuItem(
            title: NSLocalizedString("Convert Simplified Chinese to Traditional", comment: ""),
            action: #selector(toggleSimplifiedToTraditionalChineseFilterAction(_:)),
            keyEquivalent: "")
        sc2tcItem.state =
            OVModuleManager.default.simplifiedToTraditionalChineseFilterEnabled ? .on : .off
        menu.addItem(sc2tcItem)

        let assocatedPhrasesItem = NSMenuItem(
            title: NSLocalizedString("Associated Phrases", comment: ""),
            action: #selector(toggleAssociatedPhrasesAroundFilterEnabledAction(_:)),
            keyEquivalent: "")
        assocatedPhrasesItem.state =
            OVModuleManager.default.associatedPhrasesAroundFilterEnabled ? .on : .off
        menu.addItem(assocatedPhrasesItem)

        menu.addItem(NSMenuItem.separator())

        let preferenceMenuItem = NSMenuItem(
            title: NSLocalizedString("OpenVanilla Preferences…", comment: ""),
            action: #selector(showPreferences(_:)),
            keyEquivalent: "")
        menu.addItem(preferenceMenuItem)

        let userManualItem = NSMenuItem(
            title: NSLocalizedString("User Guide", comment: ""),
            action: #selector(openUserGuideAction(_:)),
            keyEquivalent: "")
        menu.addItem(userManualItem)

        let aboutMenuItem = NSMenuItem(
            title: NSLocalizedString("About OpenVanilla", comment: ""),
            action: #selector(showAboutAction(_:)),
            keyEquivalent: "")
        menu.addItem(aboutMenuItem)

        return menu

    }

    //MARK: - IMKStateSetting protocol methods

    override func activateServer(_ client: Any!) {
        guard let client = client as? IMKTextInput else {
            return
        }
        OVModuleManager.default.candidateService.pointee.resetAll()
        if let activeInputMethod = OVModuleManager.default.activeInputMethodIdentifier as? String {
            let keyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                forInputMethod: activeInputMethod)
            client.overrideKeyboard(withKeyboardNamed: keyboardLayout)

            OVModuleManager.default.synchronizeActiveInputMethodSettings()
        }

        if inputMethodContext == nil {
            inputMethodContext =
                OVModuleManager.default.activeInputMethod.pointee.createContext()
        }

        let loaderService = OVModuleManager.default.loaderServiceRef
        inputMethodContext?.pointee.startSession(loaderService)

        startOrStopAssociatedPhrasesContext()
        currentClient = client
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleCandidateSelected(_:)),
            name: NSNotification.Name.OVOneDimensionalCandidatePanelImplDidSelectCandidate,
            object: nil)

        if UserDefaults.standard.bool(forKey: OVCheckForUpdateKey) {
            UpdateChecker.shared.checkForUpdateIfNeeded()
        }
    }

    override func deactivateServer(_ client: Any!) {
        guard let client = client as? IMKTextInput else {
            return
        }

        let loaderService = OVModuleManager.default.loaderServiceRef
        inputMethodContext?.pointee.stopSession(loaderService)
        if let inputMethodContext = inputMethodContext {
            OVModuleManager.default.delete(inputMethodContext)
            self.inputMethodContext = nil
        }
        stopAssociatedPhrasesContext()

        if readingText.pointee.isEmpty() == false {
            let emptyReading = NSAttributedString(string: "")
            client.setMarkedText(
                emptyReading, selectionRange: NSMakeRange(0, 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        }
        composingText.pointee.commit()
        commitComposition(client)
        composingText.pointee.finishCommit()
        composingText.pointee.clear()
        readingText.pointee.clear()
        OVModuleManager.default.candidateService.pointee.resetAll()
        OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
        OVModuleManager.default.writeOutActiveInputMethodSettings()
        currentClient = nil
        NotificationCenter.default.removeObserver(
            self, name: NSNotification.Name.OVOneDimensionalCandidatePanelImplDidSelectCandidate,
            object: nil)
    }

    override func showPreferences(_ sender: Any!) {
        if IMKInputController.self.instancesRespond(to: #selector(showPreferences(_:))) {
            super.showPreferences(sender)
        } else {
            (NSApp.delegate as? AppDelegate)?.showPreferences()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    override func commitComposition(_ client: Any!) {
        guard let client = client as? IMKTextInput else {
            return
        }
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let termialFixedVersion = "15.0.1"
        if (osVersion as NSString).compare(termialFixedVersion, options: .numeric)
            == .orderedAscending
        {
            // fix the premature commit bug in Terminal.app since OS X 10.5
            if client.bundleIdentifier() == "com.apple.Terminal"
                && String(describing: type(of: client)) == "IPMDServerClientWrapper"
            {
                perform(
                    #selector(updateClientComposingBuffer(_:)), with: currentClient, afterDelay: 0.0
                )
                return
            }
        }

        if composingText.pointee.isCommitted() {
            let combinedText = String(composingText.pointee.composedText())
            let filteredText = OVModuleManager.default.filteredString(with: combinedText)
            client.insertText(filteredText, replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        }
    }

    override func recognizedEvents(_ client: Any!) -> Int {
        let events: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        return Int(events.rawValue)
    }

    override func handle(_ event: NSEvent!, client: Any!) -> Bool {
        guard let client = client as? IMKTextInput else {
            return false
        }
        if event.type == .flagsChanged {
            let sharedKeyboardLayout = OVModuleManager.default
                .sharedAlphanumericKeyboardLayoutIdentifier
            if let activeInputMethod = OVModuleManager.default.activeInputMethodIdentifier
                as? String
            {
                if event.modifierFlags.contains(.shift)
                    && OVModuleManager.default
                        .fallbackToSharedAlphanumericKeyboardLayoutWhenShiftPressed
                {
                    client.overrideKeyboard(withKeyboardNamed: sharedKeyboardLayout)
                    return false
                }
                let inputMethodKeyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                    forInputMethod: activeInputMethod)
                client.overrideKeyboard(withKeyboardNamed: inputMethodKeyboardLayout)
            }
            return false
        }
        if event.type != .keyDown {
            return false
        }
        if readingText.pointee.toolTipText().length() > 0 || composingText.pointee.toolTipText().length() > 0 {
            readingText.pointee.clearToolTip()
            composingText.pointee.clearToolTip()
            OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
        }
        let chars = event.characters
        guard let chars, chars.count > 0 else {
            return false
        }

        let cocoaModifiers = event.modifierFlags
        let virtualKeyCode = event.keyCode
        let capsLock = cocoaModifiers.contains(.capsLock)
        let shift = cocoaModifiers.contains(.shift)
        let ctrl = cocoaModifiers.contains(.control)
        let opt = cocoaModifiers.contains(.option)
        let cmd = cocoaModifiers.contains(.command)
        var numLock = false
        let numKeys: [UInt32] = [
            // 0,1,2,3,4,5, 6,7,8,9,.,+,-,*,/,=
            0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5b, 0x5c, 0x41, 0x45, 0x4e, 0x43,
            0x4b, 0x51,
        ]
        for i in numKeys {
            if i == virtualKeyCode {
                numLock = true
                break
            }
        }
        var unicharCode: UniChar = 0

        unicharCode = (chars as NSString).character(at: 0)
        if ctrl {
            switch unicharCode {
            case _ where unicharCode < 27:
                let char: Character = "a"
                unicharCode += (UniChar(char.asciiValue ?? 0) - 1)
            case 27:
                let char: Character = shift ? "{" : "["
                unicharCode = UniChar(char.asciiValue ?? 0)
            case 28:
                let char: Character = shift ? "|" : "\\"
                unicharCode = UniChar(char.asciiValue ?? 0)
            case 29:
                let char: Character = shift ? "}" : "]"
                unicharCode = UniChar(char.asciiValue ?? 0)
            case 31:
                let char: Character = shift ? "_" : "-"
                unicharCode = UniChar(char.asciiValue ?? 0)
            default:
                break
            }
        }
        unicharCode = OVKeyMapping.remap(code: unicharCode)
        var service = OVModuleManager.default.loaderService.pointee
        let key = {
            if unicharCode < 128 {
                service.makeOVKey(
                    Int32(unicharCode), opt, opt, ctrl, shift, cmd, capsLock, numLock)
            } else {
                service.makeOVKey(
                    std.string(chars), opt, opt, ctrl, shift, cmd, capsLock, numLock)
            }
        }()
        return handle(ovKey: key, client: client)
    }

    private func handle(ovKey: OpenVanilla.OVKey, client: IMKTextInput) -> Bool {
        NSLog("handle(ovKey")
        NSLog("inputMethodContext \(inputMethodContext)")
        var key = ovKey
        let loaderServiceRef = OVModuleManager.default.loaderServiceRef
        let candidateServiceRef = OVModuleManager.default.candidateServiceRef

        let readingTextRef = OVModuleManager.default.cast(readingText)
        let composingTextRef = OVModuleManager.default.cast(composingText)

        var handled = false
        var candidatePanelFallThrough = false
        let panel = OVModuleManager.default.candidatePanel?.pointee
        if var panel, panel.isInControl() {
            let handleKeyResult = panel.handleKey(&key)
            let result = OVOneDimensionalCandidatePanelResultMapping.remap(status: handleKeyResult)

            switch result {
            case .handled:
                return true
            case .candidateSelected:
                let index = panel.currentHightlightIndexInCandidateList()
                let candidate = panel.candidate()
                handled = inputMethodContext?.pointee.candidateSelected(
                    candidateServiceRef, candidate, index, readingTextRef, composingTextRef,
                    loaderServiceRef) ?? false
            case .canceled:
                inputMethodContext?.pointee.candidateCanceled(
                    candidateServiceRef, readingTextRef, composingTextRef, loaderServiceRef)
                handled = true
                candidatePanelFallThrough = true
            case .nonCandidatePanelKeyReceived:
                handled = inputMethodContext?.pointee.candidateNonPanelKeyReceived(
                    candidateServiceRef, &key, readingTextRef, composingTextRef,
                    loaderServiceRef) ?? false
                candidatePanelFallThrough = true
            case .invalid:
                OVModuleManager.default.loaderService.pointee.beep()
            @unknown default:
                print("")
            }
        }

        if !candidatePanelFallThrough {
            if associatedPhrasesContextInUse {
                handled =
                associatedPhrasesContext?.pointee.handleKey(
                        &key, readingTextRef, composingTextRef, candidateServiceRef,
                        loaderServiceRef) == true
            }
            if handled {
                associatedPhrasesContextInUse = true
            } else {
                NSLog("handle.... \(readingTextRef)")
                NSLog("handle.... \(key)")
                NSLog("handle.... \(readingTextRef)")
                NSLog("handle.... \(composingTextRef)")
                NSLog("handle.... \(candidateServiceRef)")
                NSLog("handle.... \(loaderServiceRef)")
                associatedPhrasesContextInUse = false
                handled = inputMethodContext?.pointee.handleKey(
                    &key, readingTextRef, composingTextRef, candidateServiceRef,
                    loaderServiceRef) ?? false
            }
        }

        if composingText.pointee.isCommitted() {
            let commitText = composingText.pointee.composedCommittedText()

            // Toggling menu item does not deactive the current session, so the context may still exist after it's disabled, and hence the extra check with the preferences.
            if associatedPhrasesContext != nil,
                OVModuleManager.default.associatedPhrasesAroundFilterEnabled
            {
                let tempReading: UnsafeMutablePointer<OpenVanilla.OVTextBufferImpl>! = nil
                tempReading.initialize(to: OpenVanilla.OVTextBufferImpl())
                let tempComposing: UnsafeMutablePointer<OpenVanilla.OVTextBufferImpl>! = nil
                tempComposing.initialize(to: OpenVanilla.OVTextBufferImpl())
                let tempReadingCast = OVModuleManager.default.cast(tempReading)
                let tempComposingCast = OVModuleManager.default.cast(tempComposing)

                associatedPhrasesContextInUse = associatedPhrasesContext?.pointee.handleDirectText(
                    commitText, tempReadingCast, tempComposingCast, candidateServiceRef,
                    loaderServiceRef) ?? false

                if tempComposing.pointee.isCommitted() {
                    composingText.pointee.finishCommit()
                    composingText.pointee.setText(tempComposing.pointee.composedCommittedText())
                    composingText.pointee.commit()
                }

                tempReading.deinitialize(count: 1)
                tempReading.deallocate()
                tempComposing.deinitialize(count: 1)
                tempComposing.deallocate()
            }
            commitComposition(client)
            composingText.pointee.finishCommit()
        }

        updateClientComposingBuffer(client)
        NSLog("handled? \(handled)")
        return handled
    }

    //MARK: - Notification

    @objc func handleInputMethodChange(_ notification: Notification) {
        composingText.pointee.clear()
        readingText.pointee.clear()

        let loaderService = OVModuleManager.default.loaderServiceRef
        inputMethodContext?.pointee.stopSession(loaderService)
        self.inputMethodContext = nil

        let emptyReading = NSAttributedString(string: "")
        currentClient?.setMarkedText(
            emptyReading, selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        composingText.pointee.commit()
        commitComposition(currentClient)
        composingText.pointee.clear()
        readingText.pointee.clear()
        OVModuleManager.default.candidateService.pointee.resetAll()
        OVModuleManager.default.toolTipWindowController.window?.orderOut(self)

        if inputMethodContext == nil {
            inputMethodContext =
                OVModuleManager.default.activeInputMethod.pointee.createContext()
        }
        inputMethodContext?.pointee.startSession(loaderService)
        if let activeInputMethod = OVModuleManager.default.activeInputMethodIdentifier
            as? String
        {
            let keyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                forInputMethod: activeInputMethod)
            currentClient?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
        }
    }

    @objc func handleCandidateSelected(_ notification: Notification) {
        let dict = notification.userInfo ?? [:]
        guard
            let candidate = dict[OVOneDimensionalCandidatePanelImplSelectedCandidateStringKey]
                as? String
        else {
            return
        }
        let index =
            (dict[OVOneDimensionalCandidatePanelImplSelectedCandidateIndexKey] as? NSNumber)?
            .uintValue ?? 0

        let candidateServiceRef = OVModuleManager.default.candidateServiceRef
        let loaderServiceRef = OVModuleManager.default.loaderServiceRef
        var readingTextRef = unsafeBitCast(readingText, to: OpenVanilla.OVTextBuffer.self)
        var composingTextRef = unsafeBitCast(composingText, to: OpenVanilla.OVTextBuffer.self)

        var handled = false

        if associatedPhrasesContextInUse {
            handled = associatedPhrasesContext?.pointee.candidateSelected(
                    candidateServiceRef, std.string(candidate), Int(index), &readingTextRef,
                    &composingTextRef, loaderServiceRef) ?? false
            associatedPhrasesContextInUse = false
        } else {
//            NSLog("inputMethodContext \(inputMethodContext)")
//            NSLog("inputMethodContext \(inputMethodContext.pointee)")
            handled = inputMethodContext?.pointee.candidateSelected(
                candidateServiceRef, std.string(candidate), Int(index), &readingTextRef,
                &composingTextRef, loaderServiceRef) ?? false
        }

        let panel = OVModuleManager.default.candidatePanel

        if handled {
            panel?.pointee.hide()
            panel?.pointee.cancelEventHandler()
        } else {
            OVModuleManager.default.loaderService.pointee.beep()
        }

        if composingText.pointee.isCommitted() {
            commitComposition(currentClient)
            composingText.pointee.finishCommit()
        }

        updateClientComposingBuffer(currentClient)
    }

    @objc func updateClientComposingBuffer(_ client: Any?) {
        guard let client = client as? IMKTextInput else {
            return
        }

        var combinedText = OpenVanilla.OVTextBufferCombinator(composingText, readingText)
        guard let attrString = combinedText.combinedAttributedString() else {
            return
        }
        let selectionRange = combinedText.selectionRange()

        if composingText.pointee.shouldUpdate() || readingText.pointee.shouldUpdate() {
            client.setMarkedText(
                attrString, selectionRange: selectionRange,
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
            composingText.pointee.finishUpdate()
            readingText.pointee.finishUpdate()
        }

        let params: [Any] = [client, attrString, NSValue(range: selectionRange)]
        // If the sender is Chrome, use a 1/20 sec delay. This is likely because some
        // internally async updates need to catch up. This is considered a hack, not a
        // real solution. Please see these two long-standing bugs below, which also
        // affect Google Japanese Input on Mac as well as Apple's built-in Pinyin IME:
        // https://bugs.chromium.org/p/chromium/issues/detail?id=86460
        // https://bugs.chromium.org/p/chromium/issues/detail?id=580808
        if client.bundleIdentifier() == "com.google.Chrome" {
            perform(
                #selector(deferredUpdateClientComposingBuffer(_:)), with: params, afterDelay: 0.0
            )
        } else {
            deferredUpdateClientComposingBuffer(params)
        }
    }

    @objc func deferredUpdateClientComposingBuffer(_ params: [Any]) {
        guard let client = params[0] as? IMKTextInput,
            let attrString = params[1] as? NSAttributedString,
            let selectionRange = (params[2] as? NSValue)?.rangeValue
        else {
            return
        }
        var cursorIndex = selectionRange.location
        if cursorIndex == attrString.length && cursorIndex > 0 {
            cursorIndex -= 1
        }
        var lineHeightRect = NSMakeRect(0.0, 0.0, 16.0, 16.0)
        let attr = client.attributes(
            forCharacterIndex: cursorIndex, lineHeightRectangle: &lineHeightRect)
        if attr == nil || attr?.count == 0 {
            client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)
        }
        let currentCandidatePanel = OVModuleManager.default.candidatePanel
        currentCandidatePanel?.pointee.setPanelOrigin(
            lineHeightRect.origin, lineHeightRect.size.height + 4.0)
        currentCandidatePanel?.pointee.updateDisplay()
        var toolTipText = readingText.pointee.toolTipText()
        if toolTipText.count == 0 {
            toolTipText = composingText.pointee.toolTipText()
        }

        if toolTipText.count > 0 {
            var toolTipOrigin = lineHeightRect.origin
            //            var fromTopLeft = true
            if currentCandidatePanel?.pointee.isVisible() == true {
                toolTipOrigin.y += lineHeightRect.size.height + 4.0
                //                fromTopLeft = false
            }
            let toolTipWindowController = OVModuleManager.default.toolTipWindowController
            (toolTipWindowController as? TooltipController)?.show(
                tooltip: String(toolTipText), at: toolTipOrigin)
            toolTipWindowController.window?.orderFront(self)
        }
    }

    //MARK: - Actions

    @IBAction func changeInputMethodAction(_ sender: NSObject) {
        guard let item = sender.value(forKey: kIMKCommandMenuItemName) as? NSMenuItem,
            let identifier = item.representedObject as? String
        else {
            return
        }
        OVModuleManager.default.selectInputMethod(identifier)
    }

    @IBAction func toggleTraditionalToSimplifiedChineseFilterAction(_ sender: Any) {
        let manager = OVModuleManager.default
        manager.traditionalToSimplifiedChineseFilterEnabled = !manager
            .traditionalToSimplifiedChineseFilterEnabled
        manager.simplifiedToTraditionalChineseFilterEnabled = false
    }

    @IBAction func toggleSimplifiedToTraditionalChineseFilterAction(_ sender: Any) {
        let manager = OVModuleManager.default
        manager.simplifiedToTraditionalChineseFilterEnabled = !manager
            .simplifiedToTraditionalChineseFilterEnabled
        manager.traditionalToSimplifiedChineseFilterEnabled = false
    }

    @IBAction func toggleAssociatedPhrasesAroundFilterEnabledAction(_ sender: Any) {
        let manager = OVModuleManager.default
        manager.associatedPhrasesAroundFilterEnabled = !manager.associatedPhrasesAroundFilterEnabled
        startOrStopAssociatedPhrasesContext()
    }

    @IBAction func openUserGuideAction(_ sender: Any) {
        if let url = URL(string: OVUserGuideURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @IBAction func showAboutAction(_ sender: Any) {
        NSApplication.shared.orderFrontStandardAboutPanel(sender)
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func startOrStopAssociatedPhrasesContext() {
        if associatedPhrasesContext == nil
            && OVModuleManager.default.associatedPhrasesAroundFilterEnabled
        {
            associatedPhrasesContext =
                OVModuleManager.default.associatedPhrasesModule.pointee.createContext()
            let loaderService = OVModuleManager.default.loaderServiceRef
            associatedPhrasesContext?.pointee.startSession(loaderService)
        } else if associatedPhrasesContext != nil
            && !OVModuleManager.default.associatedPhrasesAroundFilterEnabled
        {
            stopAssociatedPhrasesContext()
        }

        associatedPhrasesContextInUse = false
    }

    func stopAssociatedPhrasesContext() {
        let loaderService = OVModuleManager.default.loaderServiceRef
        associatedPhrasesContext?.pointee.stopSession(loaderService)
        self.associatedPhrasesContext = nil
        associatedPhrasesContextInUse = false
    }

}
