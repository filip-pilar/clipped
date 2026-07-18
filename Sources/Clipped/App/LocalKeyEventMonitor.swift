import AppKit

final class LocalKeyEventMonitor {
    private var token: Any?

    init(handler: @escaping (NSEvent) -> Bool) {
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}
