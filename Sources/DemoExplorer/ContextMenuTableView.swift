import AppKit

/// NSTableView subclass that routes context-menu construction through a
/// provider closure, selecting the clicked row first. The stock mechanism is
/// nib-based per-row menus, which a SwiftPM-only target can't ship.
final class ContextMenuTableView: NSTableView {
    var rowMenuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        guard let menu = rowMenuProvider?(row) else { return nil }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return menu
    }
}
