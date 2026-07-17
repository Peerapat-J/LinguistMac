import AppKit

final class WindowFrameObserverView: NSView {
    weak var controller: PopupWindowFrameController?

    private weak var observedWindow: NSWindow?
    private var willMoveObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var liveResizeObserver: NSObjectProtocol?
    private var mouseUpMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe(window)
        attachControllerToCurrentWindow()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        guard newWindow !== observedWindow else {
            return
        }
        stopObserving()
        observedWindow = nil
    }

    func attachControllerToCurrentWindow() {
        controller?.attach(to: window)
    }

    private func observe(_ window: NSWindow?) {
        guard observedWindow !== window else {
            return
        }
        stopObserving()
        observedWindow = window

        guard let window else {
            return
        }

        observeMoveNotifications(for: window)
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseUp
        ) { [weak self, weak window] event in
            guard let window else {
                return event
            }
            Task { @MainActor in
                self?.controller?.windowDidEndMove(window)
            }
            return event
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.windowDidResize(window)
            }
        }
        liveResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willStartLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.windowWillStartLiveResize(window)
            }
        }
    }

    private func observeMoveNotifications(for window: NSWindow) {
        willMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                let initiatedByMouse = PopupWindowMoveEventPolicy.isWindowDrag(
                    NSApp.currentEvent?.type
                )
                self?.controller?.windowWillMove(
                    window,
                    initiatedByMouse: initiatedByMouse
                )
            }
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.windowDidMove(window)
            }
        }
    }

    private func stopObserving() {
        let observers = [willMoveObserver, moveObserver, resizeObserver, liveResizeObserver]
        for observer in observers.compactMap(\.self) {
            NotificationCenter.default.removeObserver(observer)
        }
        willMoveObserver = nil
        moveObserver = nil
        resizeObserver = nil
        liveResizeObserver = nil
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }
    }
}
