import Foundation
#if os(macOS)
import AppKit
#endif

public class Application: @unchecked Sendable {
    private let node: Node
    private let window: Window
    private var control: Control!
    private let renderer: Renderer

    private let runLoopType: RunLoopType

    private var keyEventParser = KeyEventParser()
    private var pendingEscapeFlush: DispatchWorkItem?

    private var invalidatedNodes: [Node] = []
    private var updateScheduled = false
    private var observedNodes: [ObjectIdentifier: Weak<Node>] = [:]

    public init<I: View>(rootView: I, runLoopType: RunLoopType = .dispatch) {
        self.runLoopType = runLoopType

        node = Node(view: VStack(content: rootView).view)
        window = Window()

        renderer = Renderer(layer: window.layer)
        window.layer.renderer = renderer

        node.application = self
        renderer.application = self

        node.build()
        control = node.control!

        window.addControl(control)

        window.firstResponder = control.firstSelectableElement
        window.firstResponder?.becomeFirstResponder()
    }

    var stdInSource: DispatchSourceRead?

    public enum RunLoopType {
        /// The default option, using Dispatch for the main run loop.
        case dispatch

        #if os(macOS)
        /// This creates and runs an NSApplication with an associated run loop. This allows you
        /// e.g. to open NSWindows running simultaneously to the terminal app. This requires macOS
        /// and AppKit.
        case cocoa
        #endif
    }

    @MainActor public func start() {
        setInputMode()
        updateWindowSize()
        control.layout(size: window.layer.frame.size)
        renderer.draw()

        let stdInSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        stdInSource.setEventHandler(qos: .default, flags: [], handler: self.handleInput)
        stdInSource.resume()
        self.stdInSource = stdInSource

        let sigWinChSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        sigWinChSource.setEventHandler(qos: .default, flags: [], handler: self.handleWindowSizeChange)
        sigWinChSource.resume()

        signal(SIGINT, SIG_IGN)
        let sigIntSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigIntSource.setEventHandler(qos: .default, flags: [], handler: self.stop)
        sigIntSource.resume()

        switch runLoopType {
        case .dispatch:
            dispatchMain()
        #if os(macOS)
        case .cocoa:
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.run()
        #endif
        }
    }

    private func setInputMode() {
        var tattr = termios()
        tcgetattr(STDIN_FILENO, &tattr)
        tattr.c_lflag &= ~tcflag_t(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tattr);
    }

    private func handleInput() {
        let data = FileHandle.standardInput.availableData

        guard let string = String(data: data, encoding: .utf8) else {
            return
        }

        // Cache the global key handler controls once for this read.
        let onKeyEventControls = window.controls.flattenAndKeepOnlyOnKeyEventControl()
        let onKeyPressControls = window.controls.flattenAndKeepOnlyOnKeyPressControl()

        for char in string {
            if keyEventParser.hasPendingEscape, pendingEscapeFlush != nil {
                pendingEscapeFlush?.cancel()
                pendingEscapeFlush = nil
            }

            let previousState = keyEventParser.state
            let events = keyEventParser.feed(char)

            if previousState == .idle, keyEventParser.hasPendingEscape {
                scheduleEscapeFlush()
            }

            for event in events {
                handle(
                    event,
                    onKeyEventControls: onKeyEventControls,
                    onKeyPressControls: onKeyPressControls
                )
            }
        }
    }

    private func scheduleEscapeFlush() {
        pendingEscapeFlush?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let events = self.keyEventParser.flushPendingEscape()
            let onKeyEventControls = self.window.controls.flattenAndKeepOnlyOnKeyEventControl()
            let onKeyPressControls = self.window.controls.flattenAndKeepOnlyOnKeyPressControl()
            for event in events {
                self.handle(
                    event,
                    onKeyEventControls: onKeyEventControls,
                    onKeyPressControls: onKeyPressControls
                )
            }
        }

        pendingEscapeFlush = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func handle(
        _ event: KeyEvent,
        onKeyEventControls: [OnKeyEventControl],
        onKeyPressControls: [OnKeyPressControl]
    ) {
        if onKeyEventControls.contains(where: { $0.action(event) }) {
            return
        }

        switch event {
        case .character(let char):
            if char == ASCII.EOT {
                stop()
                return
            }

            window.firstResponder?.handleEvent(char)

            // handle input for `onKeyPress` View modifier
            for control in onKeyPressControls where control.keyPress == char {
                control.action()
            }

        case .special(let special):
            switch special {
            case .down:
                if let next = window.firstResponder?.selectableElement(below: 0) {
                    window.firstResponder?.resignFirstResponder()
                    window.firstResponder = next
                    window.firstResponder?.becomeFirstResponder()
                }

            case .up:
                if let next = window.firstResponder?.selectableElement(above: 0) {
                    window.firstResponder?.resignFirstResponder()
                    window.firstResponder = next
                    window.firstResponder?.becomeFirstResponder()
                }

            case .right:
                if let next = window.firstResponder?.selectableElement(rightOf: 0) {
                    window.firstResponder?.resignFirstResponder()
                    window.firstResponder = next
                    window.firstResponder?.becomeFirstResponder()
                }

            case .left:
                if let next = window.firstResponder?.selectableElement(leftOf: 0) {
                    window.firstResponder?.resignFirstResponder()
                    window.firstResponder = next
                    window.firstResponder?.becomeFirstResponder()
                }

            case .shiftUp, .shiftDown, .shiftLeft, .shiftRight, .shiftTab, .delete, .escape:
                break
            }
        }
    }

    func invalidateNode(_ node: Node) {
        invalidatedNodes.append(node)
        scheduleUpdate()
    }

    func _registerObservedNode(_ node: Node) {
        observedNodes[ObjectIdentifier(node)] = Weak(value: node)
    }

    func _handleObservationChange(for nodeID: ObjectIdentifier) {
        guard let node = observedNodes[nodeID]?.value else {
            observedNodes[nodeID] = nil
            return
        }
        log("Observation observed a change. invalidating node...")
        invalidateNode(node)
        node._observationRestart?()
    }

    func scheduleUpdate() {
        if !updateScheduled {
            DispatchQueue.main.async { self.update() }
            updateScheduled = true
        }
    }

    private func update() {
        updateScheduled = false

        for node in invalidatedNodes {
            node.update(using: node.view)
        }
        invalidatedNodes = []

        control.layout(size: window.layer.frame.size)
        renderer.update()
    }

    private func handleWindowSizeChange() {
        updateWindowSize()
        control.layer.invalidate()
        update()
    }

    private func updateWindowSize() {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0,
              size.ws_col > 0, size.ws_row > 0 else {
            assertionFailure("Could not get window size")
            return
        }
        window.layer.frame.size = Size(width: Extended(Int(size.ws_col)), height: Extended(Int(size.ws_row)))
        renderer.setCache()
    }

    private func stop() {
        renderer.stop()
        resetInputMode() // Fix for: https://github.com/rensbreur/SwiftTUI/issues/25
        exit(0)
    }

    /// Fix for: https://github.com/rensbreur/SwiftTUI/issues/25
    private func resetInputMode() {
        // Reset ECHO and ICANON values:
        var tattr = termios()
        tcgetattr(STDIN_FILENO, &tattr)
        tattr.c_lflag |= tcflag_t(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tattr);
    }

}
