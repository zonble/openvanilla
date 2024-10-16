import Foundation
import InputMethodKit
import LoaderService
import ModuleManager
import OpenVanillaImpl
import TooltipUI

@objc(OVInputMethodController)
class InputController: IMKInputController {
    fileprivate var composingText = OpenVanilla.OVTextBufferImpl()
    fileprivate var readingText = OpenVanilla.OVTextBufferImpl()
    fileprivate var inputMethodContext: OpenVanilla.OVEventHandlingContext? = nil
    fileprivate var associatedPhrasesContext: OpenVanilla.OVEventHandlingContext? = nil
    fileprivate var associatedPhrasesContextInUse = false
    fileprivate var currentClient: IMKTextInput?

    deinit {
        NotificationCenter.default.removeObserver(self)
        if var inputMethodContext {
            OVModuleManager.default.delete(&inputMethodContext)
        }
        if var associatedPhrasesContext {
            OVModuleManager.default.delete(&associatedPhrasesContext)
        }
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
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
                OVModuleManager.default.activeInputMethod.pointee.createContext()?.pointee
        }
        if var inputMethodContext {
            var loaderService = unsafeBitCast(
                OVModuleManager.default.loaderService.pointee, to: OpenVanilla.OVLoaderService.self)
            inputMethodContext.startSession(&loaderService)
        }

        startOrStopAssociatedPhrasesContext()
        currentClient = client
        // TODO: Notification

        if UserDefaults.standard.bool(forKey: OVCheckForUpdateKey) {
            UpdateChecker.shared.checkForUpdateIfNeeded()
        }
    }

    override func deactivateServer(_ client: Any!) {
        guard let client = client as? IMKTextInput else {
            return
        }

        if var inputMethodContext {
            var loaderService = unsafeBitCast(
                OVModuleManager.default.loaderService.pointee, to: OpenVanilla.OVLoaderService.self)
            inputMethodContext.stopSession(&loaderService)
            OVModuleManager.default.delete(&inputMethodContext)
            self.inputMethodContext = nil
        }
        stopAssociatedPhrasesContext()

        if readingText.isEmpty() == false {
            let emptyReading = NSAttributedString(string: "")
            client.setMarkedText(
                emptyReading, selectionRange: NSMakeRange(0, 0),
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        }
        composingText.commit()
        commitComposition(client)
        composingText.finishCommit()
        composingText.clear()
        readingText.clear()
        OVModuleManager.default.candidateService.pointee.resetAll()
        OVModuleManager.default.toolTipWindowController.window?.orderOut(self)
        OVModuleManager.default.writeOutActiveInputMethodSettings()
        currentClient = nil
        // TODO: Notification
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

        if composingText.isCommitted() {
            let combinedText = String(composingText.composedText())
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
        if readingText.toolTipText().length() > 0 || composingText.toolTipText().length() > 0 {
            readingText.clearToolTip()
            composingText.clearToolTip()
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
            if unicharCode < 27 {
                let char: Character = "a"
                unicharCode += (UniChar(char.asciiValue ?? 0) - 1)
            } else {
                switch unicharCode {
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
        }
        unicharCode = OVKeyMapping.remap(code: unicharCode)
        var service = OVModuleManager.default.loaderService.pointee
        let key = {
            if unicharCode < 128 {
                return service.makeOVKey(
                    Int32(unicharCode), opt, opt, ctrl, shift, cmd, capsLock, numLock)
            } else {
                return service.makeOVKey(
                    std.string(chars), opt, opt, ctrl, shift, cmd, capsLock, numLock)
            }
        }()
        return handle(ovKey: key, cliemt: client)
    }

    private func handle(ovKey: OpenVanilla.OVKey, cliemt: IMKTextInput) -> Bool {
        var key = ovKey
        guard var inputMethodContext else {
            return false
        }
        var candidateServiceRef = unsafeBitCast(
            OVModuleManager.default.candidateService.pointee,
            to: OpenVanilla.OVCandidateService.self)
        var loaderServiceRef = unsafeBitCast(
            OVModuleManager.default.loaderService.pointee, to: OpenVanilla.OVLoaderService.self)
        var readingTextRef = unsafeBitCast(readingText, to: OpenVanilla.OVTextBuffer.self)
        var composingTextRef = unsafeBitCast(composingText, to: OpenVanilla.OVTextBuffer.self)

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
                handled = inputMethodContext.candidateSelected(
                    &candidateServiceRef, candidate, index, &readingTextRef, &composingTextRef,
                    &loaderServiceRef)
            case .canceled:
                inputMethodContext.candidateCanceled(
                    &candidateServiceRef, &readingTextRef, &composingTextRef, &loaderServiceRef)
                handled = true
                candidatePanelFallThrough = true
            case .nonCandidatePanelKeyReceived:
                handled = inputMethodContext.candidateNonPanelKeyReceived(
                    &candidateServiceRef, &key, &readingTextRef, &composingTextRef,
                    &loaderServiceRef)
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
                    associatedPhrasesContext?.handleKey(
                        &key, &readingTextRef, &composingTextRef, &candidateServiceRef,
                        &loaderServiceRef) == true
            }
            if handled {
                associatedPhrasesContextInUse = true
            } else {
                associatedPhrasesContextInUse = false
                handled = inputMethodContext.handleKey(
                    &key, &readingTextRef, &composingTextRef, &candidateServiceRef,
                    &loaderServiceRef)
            }
        }

        if composingText.isCommitted() {
            let commitText = composingText.composedCommittedText()

            // Toggling menu item does not deactive the current session, so the context may still exist after it's disabled, and hence the extra check with the preferences.
            if var associatedPhrasesContext,
                OVModuleManager.default.associatedPhrasesAroundFilterEnabled
            {
                let tempReading = OpenVanilla.OVTextBufferImpl()
                var tempReadingCast = unsafeBitCast(tempReading, to: OpenVanilla.OVTextBuffer.self)
                var tempComposing = OpenVanilla.OVTextBufferImpl()
                var tempComposingCast = unsafeBitCast(
                    tempComposing, to: OpenVanilla.OVTextBuffer.self)

                associatedPhrasesContextInUse = associatedPhrasesContext.handleDirectText(
                    commitText, &tempReadingCast, &tempComposingCast, &candidateServiceRef,
                    &loaderServiceRef)

                if tempComposing.isCommitted() {
                    composingText.finishCommit()
                    composingText.setText(tempComposing.composedCommittedText())
                    composingText.commit()
                }

            }
            commitComposition(client)
            composingText.finishCommit()
        }

        updateClientComposingBuffer(client)
        return handled
    }

    //MARK: - Notification

    @objc func handleInputMethodChange(_ notification: Notification) {
        composingText.clear()
        readingText.clear()

        if var inputMethodContext {
            let service = OVModuleManager.default.loaderService.pointee
            var loaderService = unsafeBitCast(
                service, to: OpenVanilla.OVLoaderService.self)
            inputMethodContext.stopSession(&loaderService)
            OVModuleManager.default.delete(&inputMethodContext)
            self.inputMethodContext = nil
        }

        let emptyReading = NSAttributedString(string: "")
        currentClient?.setMarkedText(
            emptyReading, selectionRange: NSMakeRange(0, 0),
            replacementRange: NSMakeRange(NSNotFound, NSNotFound))
        composingText.commit()
        commitComposition(currentClient)
        composingText.clear()
        readingText.clear()
        OVModuleManager.default.candidateService.pointee.resetAll()
        OVModuleManager.default.toolTipWindowController.window?.orderOut(self)

        if inputMethodContext == nil {
            inputMethodContext =
                OVModuleManager.default.activeInputMethod.pointee.createContext()?.pointee
        }
        if var inputMethodContext {
            let service = OVModuleManager.default.loaderService.pointee
            var loaderService = unsafeBitCast(
                service, to: OpenVanilla.OVLoaderService.self)
            inputMethodContext.startSession(&loaderService)
            if let activeInputMethod = OVModuleManager.default.activeInputMethodIdentifier
                as? String
            {
                let keyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                    forInputMethod: activeInputMethod)
                currentClient?.overrideKeyboard(withKeyboardNamed: keyboardLayout)
            }

        }
    }

    @objc func handleCandidateSelected(_ notification: Notification) {
        guard var inputMethodContext else {
            return
        }
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

        var candidateServiceRef = unsafeBitCast(
            OVModuleManager.default.candidateService.pointee,
            to: OpenVanilla.OVCandidateService.self)
        var loaderServiceRef = unsafeBitCast(
            OVModuleManager.default.loaderService.pointee, to: OpenVanilla.OVLoaderService.self)
        var readingTextRef = unsafeBitCast(readingText, to: OpenVanilla.OVTextBuffer.self)
        var composingTextRef = unsafeBitCast(composingText, to: OpenVanilla.OVTextBuffer.self)

        var handled = false

        if associatedPhrasesContextInUse {
            handled =
                associatedPhrasesContext?.candidateSelected(
                    &candidateServiceRef, std.string(candidate), Int(index), &readingTextRef,
                    &composingTextRef, &loaderServiceRef) ?? false
            associatedPhrasesContextInUse = false
        } else {
            handled = inputMethodContext.candidateSelected(
                &candidateServiceRef, std.string(candidate), Int(index), &readingTextRef,
                &composingTextRef, &loaderServiceRef)
        }

        let panel = OVModuleManager.default.candidatePanel

        if handled {
            panel?.pointee.hide()
            panel?.pointee.cancelEventHandler()
        } else {
            OVModuleManager.default.loaderService.pointee.beep()
        }

        if composingText.isCommitted() {
            commitComposition(currentClient)
            composingText.finishCommit()
        }

        updateClientComposingBuffer(currentClient)
    }

    @objc func updateClientComposingBuffer(_ client: Any?) {
        guard let client = client as? IMKTextInput else {
            return
        }

        var combinedText = OpenVanilla.OVTextBufferCombinator(&composingText, &readingText)
        guard let attrString = combinedText.combinedAttributedString() else {
            return
        }
        let selectionRange = combinedText.selectionRange()

        if composingText.shouldUpdate() || readingText.shouldUpdate() {
            client.setMarkedText(
                attrString, selectionRange: selectionRange,
                replacementRange: NSMakeRange(NSNotFound, NSNotFound))
            composingText.finishUpdate()
            readingText.finishUpdate()
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
        var toolTipText = readingText.toolTipText()
        if toolTipText.count == 0 {
            toolTipText = composingText.toolTipText()
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
                OVModuleManager.default.associatedPhrasesModule.pointee.createContext()?.pointee
            let service = OVModuleManager.default.loaderService.pointee
            var loaderService = unsafeBitCast(
                service, to: OpenVanilla.OVLoaderService.self)
            associatedPhrasesContext?.startSession(&loaderService)
        } else if associatedPhrasesContext != nil
            && !OVModuleManager.default.associatedPhrasesAroundFilterEnabled
        {
            stopAssociatedPhrasesContext()
        }

        associatedPhrasesContextInUse = false
    }

    func stopAssociatedPhrasesContext() {
        guard var associatedPhrasesContext else {
            return
        }
        var loaderService = unsafeBitCast(
            OVModuleManager.default.loaderService.pointee, to: OpenVanilla.OVLoaderService.self)
        associatedPhrasesContext.stopSession(&loaderService)
        OVModuleManager.default.delete(&associatedPhrasesContext)
        self.associatedPhrasesContext = nil
        associatedPhrasesContextInUse = false
    }

}
