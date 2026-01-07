import AppKit
import Combine
import SwiftUI

struct FinderListView: NSViewRepresentable {
    @EnvironmentObject var appState: AppState
    var searchQuery: String = ""

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = FinderTableView()
        tableView.coordinator = context.coordinator
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnSelection = false
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 3, height: 2)
        tableView.gridStyleMask = []
        tableView.headerView = NSTableHeaderView()

        // Create columns
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 220
        nameColumn.minWidth = 120
        nameColumn.maxWidth = 600
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
        tableView.addTableColumn(nameColumn)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dateModified"))
        dateColumn.title = "Date Modified"
        dateColumn.width = 140
        dateColumn.minWidth = 100
        dateColumn.maxWidth = 200
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "dateModified", ascending: false)
        tableView.addTableColumn(dateColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 80
        sizeColumn.minWidth = 60
        sizeColumn.maxWidth = 120
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        tableView.addTableColumn(sizeColumn)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Kind"
        kindColumn.width = 100
        kindColumn.minWidth = 60
        kindColumn.maxWidth = 150
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
        tableView.addTableColumn(kindColumn)

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        // Enable drag and drop
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.every, forLocal: false)

        // Set default sort
        tableView.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))]

        // Double-click action
        tableView.doubleAction = #selector(Coordinator.tableViewDoubleClick(_:))
        tableView.target = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.startObserving()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.appState = appState
        // Update search query and reload if changed
        if context.coordinator.searchQuery != searchQuery {
            context.coordinator.searchQuery = searchQuery
            context.coordinator.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var appState: AppState?
        weak var tableView: NSTableView?
        private var cancellables = Set<AnyCancellable>()
        private var allItems: [FileItem] = []
        private var sortedItems: [FileItem] = []
        private var isUpdatingSelection = false
        var searchQuery: String = ""

        private let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        private let sizeFormatter = ByteCountFormatter()

        struct FileItem {
            let url: URL
            let name: String
            let isDirectory: Bool
            let size: Int64
            let dateModified: Date
            let kind: String
        }

        init(appState: AppState) {
            self.appState = appState
            super.init()
        }

        func startObserving() {
            guard let appState else { return }

            // Observe selection changes from AppState (e.g., from 3D view clicks)
            appState.$selectedURLs
                .receive(on: DispatchQueue.main)
                .sink { [weak self] urls in
                    self?.syncTableSelectionFromAppState(urls)
                }
                .store(in: &cancellables)

            // Observe blocks changes to reload data
            appState.$blocks
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.reloadData()
                }
                .store(in: &cancellables)
        }

        func reloadData() {
            guard let appState, let tableView else { return }

            // Build file items from the root URL's direct children
            guard let rootURL = appState.rootURL else {
                allItems = []
                sortedItems = []
                tableView.reloadData()
                return
            }

            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey],
                    options: [.skipsHiddenFiles]
                )

                allItems = contents.compactMap { url -> FileItem? in
                    do {
                        let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey])
                        let isDir = resourceValues.isDirectory ?? false
                        let size = Int64(resourceValues.fileSize ?? 0)
                        let date = resourceValues.contentModificationDate ?? Date.distantPast
                        let kind = resourceValues.localizedTypeDescription ?? (isDir ? "Folder" : "Document")

                        return FileItem(
                            url: url,
                            name: url.lastPathComponent,
                            isDirectory: isDir,
                            size: size,
                            dateModified: date,
                            kind: kind
                        )
                    } catch {
                        return nil
                    }
                }
            } catch {
                allItems = []
            }

            applyFiltering()
            applySorting()

            tableView.reloadData()
            syncTableSelectionFromAppState(appState.selectedURLs)
        }

        private func applyFiltering() {
            let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
            if query.isEmpty {
                sortedItems = allItems
            } else {
                sortedItems = allItems.filter { item in
                    item.name.lowercased().contains(query)
                }
            }
        }

        private func applySorting() {
            guard let tableView, let sortDescriptor = tableView.sortDescriptors.first else { return }

            switch sortDescriptor.key {
            case "name":
                sortedItems.sort { a, b in
                    let result = a.name.localizedStandardCompare(b.name)
                    return sortDescriptor.ascending ? result == .orderedAscending : result == .orderedDescending
                }
            case "dateModified":
                sortedItems.sort { a, b in
                    sortDescriptor.ascending ? a.dateModified < b.dateModified : a.dateModified > b.dateModified
                }
            case "size":
                sortedItems.sort { a, b in
                    sortDescriptor.ascending ? a.size < b.size : a.size > b.size
                }
            case "kind":
                sortedItems.sort { a, b in
                    let result = a.kind.localizedStandardCompare(b.kind)
                    return sortDescriptor.ascending ? result == .orderedAscending : result == .orderedDescending
                }
            default:
                break
            }
        }

        private func syncTableSelectionFromAppState(_ urls: Set<URL>) {
            guard !isUpdatingSelection, let tableView else { return }
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }

            var indexSet = IndexSet()
            for (index, item) in sortedItems.enumerated() {
                if urls.contains(item.url) {
                    indexSet.insert(index)
                }
            }
            tableView.selectRowIndexes(indexSet, byExtendingSelection: false)
        }

        private func syncAppStateFromTableSelection() {
            guard !isUpdatingSelection, let appState, let tableView else { return }
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }

            let selectedURLs = tableView.selectedRowIndexes.compactMap { index -> URL? in
                guard index < sortedItems.count else { return nil }
                return sortedItems[index].url
            }
            appState.selectURLs(Set(selectedURLs))
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            sortedItems.count
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            applyFiltering()
            applySorting()
            tableView.reloadData()
            if let appState {
                syncTableSelectionFromAppState(appState.selectedURLs)
            }
        }

        // Drag source
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < sortedItems.count else { return nil }
            return sortedItems[row].url as NSURL
        }

        // Drop validation
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            // Only accept drops on folder rows
            if dropOperation == .on && row < sortedItems.count && sortedItems[row].isDirectory {
                return .move
            }
            // Accept drops at root level (move to current directory)
            if dropOperation == .above {
                return .move
            }
            return []
        }

        // Accept drop
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard let appState else { return false }

            let pasteboard = info.draggingPasteboard
            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
                return false
            }

            // Determine destination
            let destination: URL
            if dropOperation == .on && row < sortedItems.count && sortedItems[row].isDirectory {
                destination = sortedItems[row].url
            } else if let rootURL = appState.rootURL {
                destination = rootURL
            } else {
                return false
            }

            // Move files
            let fileManager = FileManager.default
            for sourceURL in urls {
                let destURL = destination.appendingPathComponent(sourceURL.lastPathComponent)
                do {
                    try fileManager.moveItem(at: sourceURL, to: destURL)
                } catch {
                    NSLog("Failed to move \(sourceURL) to \(destURL): \(error)")
                }
            }

            // Trigger rescan
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.scanRoot()
            }

            return true
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < sortedItems.count, let columnID = tableColumn?.identifier else { return nil }
            let item = sortedItems[row]

            let cellID = NSUserInterfaceItemIdentifier("Cell_\(columnID.rawValue)")
            var cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView

            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = cellID

                if columnID.rawValue == "name" {
                    // Name column with icon
                    let imageView = NSImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    cellView?.addSubview(imageView)
                    cellView?.imageView = imageView

                    let textField = NSTextField(labelWithString: "")
                    textField.translatesAutoresizingMaskIntoConstraints = false
                    textField.lineBreakMode = .byTruncatingTail
                    textField.font = NSFont.systemFont(ofSize: 13)
                    cellView?.addSubview(textField)
                    cellView?.textField = textField

                    NSLayoutConstraint.activate([
                        imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 2),
                        imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                        imageView.widthAnchor.constraint(equalToConstant: 16),
                        imageView.heightAnchor.constraint(equalToConstant: 16),
                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                        textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -2),
                        textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                    ])
                } else {
                    // Other columns - just text
                    let textField = NSTextField(labelWithString: "")
                    textField.translatesAutoresizingMaskIntoConstraints = false
                    textField.lineBreakMode = .byTruncatingTail
                    textField.font = NSFont.systemFont(ofSize: 13)

                    if columnID.rawValue == "size" {
                        textField.alignment = .right
                    }

                    cellView?.addSubview(textField)
                    cellView?.textField = textField

                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 2),
                        textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -2),
                        textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                    ])
                }
            }

            // Populate cell
            switch columnID.rawValue {
            case "name":
                cellView?.textField?.stringValue = item.name
                cellView?.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
            case "dateModified":
                cellView?.textField?.stringValue = dateFormatter.string(from: item.dateModified)
            case "size":
                if item.isDirectory {
                    cellView?.textField?.stringValue = "--"
                } else {
                    cellView?.textField?.stringValue = sizeFormatter.string(fromByteCount: item.size)
                }
            case "kind":
                cellView?.textField?.stringValue = item.kind
            default:
                break
            }

            return cellView
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            syncAppStateFromTableSelection()
        }

        func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
            guard edge == .trailing, row < sortedItems.count else { return [] }

            let deleteAction = NSTableViewRowAction(style: .destructive, title: "Delete") { [weak self] _, row in
                self?.deleteItem(at: row)
            }

            return [deleteAction]
        }

        private func deleteItem(at row: Int) {
            guard row < sortedItems.count, let appState else { return }
            let item = sortedItems[row]

            do {
                try FileActions().moveToTrash(item.url)
                appState.removeFromSelection(item.url)
                appState.scanRoot()
            } catch {
                NSLog("Failed to delete \(item.url): \(error)")
            }
        }

        // MARK: - Context Menu

        @objc func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()

            guard let tableView, let appState else { return }
            let clickedRow = tableView.clickedRow

            if clickedRow >= 0 && clickedRow < sortedItems.count {
                let item = sortedItems[clickedRow]

                // Ensure clicked row is in selection
                if !tableView.selectedRowIndexes.contains(clickedRow) {
                    tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
                }

                let selectedCount = tableView.selectedRowIndexes.count

                // Open
                let openItem = NSMenuItem(title: "Open", action: #selector(openSelectedItems(_:)), keyEquivalent: "")
                openItem.target = self
                menu.addItem(openItem)

                menu.addItem(NSMenuItem.separator())

                // Rename (only for single selection)
                if selectedCount == 1 {
                    let renameItem = NSMenuItem(title: "Rename", action: #selector(renameSelectedItem(_:)), keyEquivalent: "\r")
                    renameItem.target = self
                    menu.addItem(renameItem)
                }

                // Move to Trash
                let trashItem = NSMenuItem(title: "Move to Trash", action: #selector(trashSelectedItems(_:)), keyEquivalent: "\u{8}")
                trashItem.keyEquivalentModifierMask = .command
                trashItem.target = self
                menu.addItem(trashItem)

                menu.addItem(NSMenuItem.separator())

                // Copy
                let copyItem = NSMenuItem(title: "Copy", action: #selector(copySelectedItems(_:)), keyEquivalent: "c")
                copyItem.keyEquivalentModifierMask = .command
                copyItem.target = self
                menu.addItem(copyItem)

                // Reveal in Finder
                let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder(_:)), keyEquivalent: "")
                revealItem.target = self
                menu.addItem(revealItem)
            }
        }

        @objc func tableViewDoubleClick(_ sender: Any?) {
            guard let tableView else { return }
            let clickedRow = tableView.clickedRow
            guard clickedRow >= 0, clickedRow < sortedItems.count else { return }

            let item = sortedItems[clickedRow]
            if item.isDirectory {
                appState?.enter(item.url)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }

        @objc func openSelectedItems(_ sender: Any?) {
            guard let tableView else { return }
            for index in tableView.selectedRowIndexes {
                guard index < sortedItems.count else { continue }
                let item = sortedItems[index]
                if item.isDirectory {
                    appState?.enter(item.url)
                    break  // Only enter one directory
                } else {
                    NSWorkspace.shared.open(item.url)
                }
            }
        }

        @objc func renameSelectedItem(_ sender: Any?) {
            appState?.renameSelected()
        }

        @objc func trashSelectedItems(_ sender: Any?) {
            appState?.trashSelected()
        }

        @objc func copySelectedItems(_ sender: Any?) {
            guard let tableView else { return }
            let urls = tableView.selectedRowIndexes.compactMap { index -> URL? in
                guard index < sortedItems.count else { return nil }
                return sortedItems[index].url
            }
            guard !urls.isEmpty else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
        }

        @objc func revealInFinder(_ sender: Any?) {
            guard let tableView else { return }
            let urls = tableView.selectedRowIndexes.compactMap { index -> URL? in
                guard index < sortedItems.count else { return nil }
                return sortedItems[index].url
            }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}

// MARK: - Custom Table View for keyboard handling

final class FinderTableView: NSTableView {
    weak var coordinator: FinderListView.Coordinator?

    override func keyDown(with event: NSEvent) {
        // Enter key - rename
        if event.keyCode == 36 && selectedRowIndexes.count == 1 {
            coordinator?.renameSelectedItem(nil)
            return
        }

        // Cmd+Delete - trash
        if event.keyCode == 51 && event.modifierFlags.contains(.command) {
            coordinator?.trashSelectedItems(nil)
            return
        }

        // Cmd+C - copy
        if event.charactersIgnoringModifiers == "c" && event.modifierFlags.contains(.command) {
            coordinator?.copySelectedItems(nil)
            return
        }

        // Cmd+V - paste
        if event.charactersIgnoringModifiers == "v" && event.modifierFlags.contains(.command) {
            pasteItems()
            return
        }

        super.keyDown(with: event)
    }

    private func pasteItems() {
        guard let coordinator, let appState = coordinator.appState, let rootURL = appState.rootURL else { return }

        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty else {
            return
        }

        let fileManager = FileManager.default
        for sourceURL in urls {
            let destURL = rootURL.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destURL.path) {
                    // Generate unique name
                    var counter = 2
                    var finalURL = destURL
                    let name = destURL.deletingPathExtension().lastPathComponent
                    let ext = destURL.pathExtension
                    while fileManager.fileExists(atPath: finalURL.path) {
                        let newName = "\(name) \(counter)" + (ext.isEmpty ? "" : ".\(ext)")
                        finalURL = rootURL.appendingPathComponent(newName)
                        counter += 1
                    }
                    try fileManager.copyItem(at: sourceURL, to: finalURL)
                } else {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                }
            } catch {
                NSLog("Failed to paste \(sourceURL): \(error)")
            }
        }

        appState.scanRoot()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        if clickedRow >= 0 {
            // Select clicked row if not already selected
            if !selectedRowIndexes.contains(clickedRow) {
                selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
        }

        let menu = NSMenu()
        menu.delegate = coordinator
        coordinator?.menuNeedsUpdate(menu)
        return menu
    }
}

extension FinderListView.Coordinator: NSMenuDelegate {}
