import Foundation
import InputMethodKit
import LoaderService
import ModuleManager
import OpenVanillaImpl
import TooltipUI

class InputController: IMKInputController {
    fileprivate var composingText = OpenVanilla.OVTextBufferImpl()
    fileprivate var readingText = OpenVanilla.OVTextBufferImpl()
    fileprivate var inputMethodContext: OpenVanilla.OVEventHandlingContext? = nil
    fileprivate var associatedPhrasesContext: OpenVanilla.OVEventHandlingContext? = nil
    fileprivate var associatedPhrasesContextInUse = false
    fileprivate var currentClient: IMKTextInput?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        // TODO: Notification
    }

    func startOrStopAssociatedPhrasesContext() {
    }

    func stopAssociatedPhrasesContext() {
    }

    @objc func updateClientComposingBuffer(_ sender: Any?) {
    }

    //MARK: - IMKStateSetting protocol methods

    override func activateServer(_ client: Any!) {
        guard let client = client as? IMKTextInput else {
            return
        }
        OVModuleManager.default.candidateService.pointee.resetAll()
        if let activeInputMethod = OVModuleManager.default.activeInputMethodIdentifier {
            let keyboardLayout = OVModuleManager.default.alphanumericKeyboardLayout(
                forInputMethod: activeInputMethod as String)
            client.overrideKeyboard(withKeyboardNamed: keyboardLayout)

            OVModuleManager.default.synchronizeActiveInputMethodSettings()

            if inputMethodContext == nil {
                inputMethodContext =
                    OVModuleManager.default.activeInputMethod.pointee.createContext()?.pointee
            }
            if var inputMethodContext {
                let service = OVModuleManager.default.loaderServiceRef
                inputMethodContext.startSession(service)
            }
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
            let service = OVModuleManager.default.loaderServiceRef
            inputMethodContext.stopSession(service)
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
                self.perform(
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
        guard let inputMethodContext else {
            return false
        }
        var handled = false
        var candidatePanelFallThrough = false
//        let panel = OVModuleManager.default.candidateService.pointee.currentCandidatePanel()



        return false

    }

}
