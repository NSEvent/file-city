import CoreServices
import Foundation

final class FSEventsWatcher {
    private let url: URL
    private let queue = DispatchQueue(label: "filecity.fsevents")
    private var streamRef: FSEventStreamRef?
    var onChange: (() -> Void)?

    init(url: URL) {
        self.url = url
    }

    func start() {
        stop()
        let paths = [url.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        let latency: CFTimeInterval = 0.2
        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleChange()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )
        if let streamRef {
            FSEventStreamSetDispatchQueue(streamRef, queue)
            FSEventStreamStart(streamRef)
        }
    }

    func stop() {
        if let streamRef {
            FSEventStreamStop(streamRef)
            FSEventStreamInvalidate(streamRef)
            FSEventStreamRelease(streamRef)
            self.streamRef = nil
        }
    }

    deinit {
        stop()
    }

    private func handleChange() {
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }
}
