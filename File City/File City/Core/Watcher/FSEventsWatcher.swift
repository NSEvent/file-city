import CoreServices
import Foundation

final class FSEventsWatcher {
    private let url: URL
    private let queue = DispatchQueue(label: "filecity.fsevents")
    private var streamRef: FSEventStreamRef?
    var onChange: (() -> Void)?
    var onFileActivity: ((URL, ActivityKind) -> Void)?
    private var lastActivityByPath: [String: CFTimeInterval] = [:]
    private let throttleInterval: CFTimeInterval = 0.15

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
        let latency: CFTimeInterval = 0.1
        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
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
        lastActivityByPath.removeAll()
    }

    deinit {
        stop()
    }

    fileprivate func handleEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        var hasDirectoryChange = false
        let now = CFAbsoluteTimeGetCurrent()

        for (index, path) in paths.enumerated() {
            let eventFlags = flags[index]

            // Check for directory-level changes that need rescan
            let isDir = (eventFlags & UInt32(kFSEventStreamEventFlagItemIsDir)) != 0
            let isCreated = (eventFlags & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
            let isRemoved = (eventFlags & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0
            let isRenamed = (eventFlags & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0

            if isDir && (isCreated || isRemoved || isRenamed) {
                hasDirectoryChange = true
            }

            // Check for file activity (writes) - FSEvents cannot detect reads
            let isFile = (eventFlags & UInt32(kFSEventStreamEventFlagItemIsFile)) != 0
            let isModified = (eventFlags & UInt32(kFSEventStreamEventFlagItemModified)) != 0
            let isXattrMod = (eventFlags & UInt32(kFSEventStreamEventFlagItemXattrMod)) != 0
            let isInodeMeta = (eventFlags & UInt32(kFSEventStreamEventFlagItemInodeMetaMod)) != 0

            if isFile && (isCreated || isModified || isRemoved || isRenamed || isXattrMod || isInodeMeta) {
                // Throttle repeated events for the same path
                if let lastTime = lastActivityByPath[path], now - lastTime < throttleInterval {
                    continue
                }
                lastActivityByPath[path] = now

                let url = URL(fileURLWithPath: path)
                let kind: ActivityKind = isRemoved ? .write : (isModified || isCreated || isXattrMod || isInodeMeta ? .write : .write)
                DispatchQueue.main.async { [weak self] in
                    self?.onFileActivity?(url, kind)
                }
            }
        }

        if hasDirectoryChange {
            DispatchQueue.main.async { [weak self] in
                self?.onChange?()
            }
        }
    }
}

private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()

    // eventPaths is a pointer to an array of C strings (char**)
    let pathsPtr = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    var paths: [String] = []
    paths.reserveCapacity(numEvents)
    for i in 0..<numEvents {
        paths.append(String(cString: pathsPtr[i]))
    }
    let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

    watcher.handleEvents(paths: paths, flags: flags)
}
