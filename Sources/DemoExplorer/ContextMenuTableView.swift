import AppKit

/// NSTableView subclass that routes context-menu construction through a
/// provider closure, selecting the clicked row first (the system way is
/// nib-based menu per row, which a SwiftPM-only target can't ship). The stock
/// per-row menu mechanism is nib-based, which this package can't ship.
final class ContextMenuTableView: NSTableView {
    var rowMenuProvider: ((Int) -> NSMenu?)?
    /// Invoked when Return is pressed while the table is first responder
    /// (opens the selection, the keyboard equivalent of a double-click).
    var enterAction: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else { return nil }
        guard let menu = rowMenuProvider?(row) else { return nil }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return menu
    }

    override func keyDown(with event: NSEvent) {
        // 36 = Return, 76 = keypad Enter.
        if event.keyCode == 36 || event.keyCode == 76, let enterAction {
            enterAction()
            return
        }
        super.keyDown(with: event)
    }
}
