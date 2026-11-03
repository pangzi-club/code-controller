# UI Verification Playbook

How to exercise the real, assembled app with Accessibility (AX),
`screencapture`, and synthetic mouse/keyboard events. Use this for anything
unit tests cannot see: window frame restoration, focus rings, the settings
window, empty states, dark mode, and localization.

Unit tests (`swift test`) still cover pure logic; this document covers the
AppKit/SwiftUI surface.

## Ground rules

- **Test the `.app`, not `swift run`.** A bare SwiftPM binary gets no Dock icon
  and no menu bar from Launch Services. Always assemble a bundle first:
  `make app` for the local/Developer ID build, `make mas` for the sandboxed
  App Store build, or `make launch` for the dev identity.
- **Names.** The display name and bundle ID live in `Sources/*/AppInfo.swift`;
  the executable target (and therefore the process) is `<Library>` + `App`.
  The helpers read the bundle ID from `APP_BUNDLE_ID`. Export it once per shell:

  ```sh
  APP_NAME="$(sed -nE 's/^[[:space:]]*static let displayName[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' Sources/*/AppInfo.swift)"
  export APP_BUNDLE_ID="$(sed -nE 's/^[[:space:]]*static let bundleID[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' Sources/*/AppInfo.swift)"
  export APP_PATH="build/$APP_NAME.app"   # make app (universal)
  # Per-arch build from `ARCHS=arm64 make app`:
  # export APP_PATH="build/$APP_NAME-$(uname -m).app"
  # Dev build from `make launch`:
  # export APP_BUNDLE_ID="$APP_BUNDLE_ID.dev"
  # export APP_PATH="build/$APP_NAME-Dev-$(uname -m).app"
  export APP_PROCESS="$(ls "$APP_PATH"/Contents/MacOS | head -1)"
  ```

- **Permissions.** AX queries and CGEvent clicks require Accessibility for the
  terminal/Qoder process. `screencapture` does not. If AX returns errors or a
  click only focuses, check System Settings > Privacy & Security > Accessibility.
- **Coordinate spaces.** AX frames, `screencapture -R`, and CGEvent mouse
  positions use top-left origin. AppKit `NSWindow.frame` and
  `NSEvent.mouseLocation` use bottom-left. Convert before comparing.
- **State restoration.** The system restores the main window and its frame. If
  the main window was closed at quit, open it with ⌘N. The Settings scene is
  never restored on its own; open it with ⌘,.
- **Leave no traces.** Quit the app, restore dark mode, delete test `defaults`
  (from the sandbox container when testing the App Store build), and remove
  temporary logs when finished.

## Build and launch loop

```sh
make app                    # or: make launch (dev identity, opens automatically)
pkill -x "$APP_PROCESS"; sleep 1
# Optional: seed defaults before launch (language, theme, frame)
open "$APP_PATH"
sleep 3
```

`pkill -x` matches the exact process name; when the app is not running it exits
nonzero, which is harmless in a script.

The `make app` and `make launch` builds are unsandboxed. The `make mas` build
is the sandboxed one: it uses the same bundle ID as `make app` but keeps its
preferences and logs under `~/Library/Containers/<bundleID>/Data`. The `.dev`
app from `make launch` has a separate bundle ID and separate TCC grants and
defaults. Export the matching `APP_BUNDLE_ID` and `APP_PATH` before seeding
defaults; `swift run` shares neither.

## Helper toolkit

Keep these small Swift files in `/tmp` and run them with `swift` (they compile
on first use). Full sources are in the appendix.

| Helper | Purpose |
| --- | --- |
| `axpos` | Print every AX window title and frame |
| `axfind <query>` | Walk the AX tree and print matching roles, titles, frames |
| `click x y` | One CGEvent left click at a global (top-left) point |
| `drag x1 y1 x2 y2` | Synthetic drag with a slow move curve and pre-press |
| `frames video.mov` | Dump 60 fps PNG frames from a launch recording |

### Inspecting windows and controls

```sh
swift /tmp/axfind.swift "AXWindow"     # window titles and frames
swift /tmp/axfind.swift "AXButton"     # every button with its frame
swift /tmp/axfind.swift "添加"          # controls by localized title
```

Frame centers are the click targets: `x + width/2`, `y + height/2`.
The **first click often only activates the window** and does not press the
control; click twice, or activate first:

```sh
osascript -e "tell application id \"$APP_BUNDLE_ID\" to activate"
```

Overlapping windows are a common trap: the settings window sits over the main
window. Click its title bar first, take a screenshot to confirm it is frontmost,
then interact with its controls.

### Clicking and typing

```sh
swift /tmp/click.swift 124 143        # sidebar row, center coordinates
osascript -e 'tell application "System Events" to keystroke "f" using command down'
```

- With a Pinyin/IME input source, Latin keystrokes may become an IME
  composition instead of text. Type **digits** to exercise text filters; digits
  bypass composition. Return commits, Esc clears.
- SwiftUI controls do not always take focus from a synthetic click. Prefer the
  app's keyboard shortcut when it has one, or activate the window first.

### Dragging

Use the slow drag helper; SwiftUI drag sessions need a press, a short pause,
and incremental moves. Start on meaningful content (row icon or title), not
blank row padding, or the drag never starts.

```sh
swift /tmp/drag.swift 710 658 710 488
```

Hold a drag open to inspect mid-drag UI (drop feedback, focus ring):

```sh
/tmp/draghold 710 658 710 488 &
sleep 2.2
screencapture -x -R670,300,580,560 /tmp/drag-hold.png
wait
```

Build a hold variant by adding `sleep(2_500_000)` before the mouse-up.

### Launch animation and frame restoration

Record the screen while launching, then inspect the frames around the window's
first appearance:

```sh
screencapture -x -v -V 6 /tmp/launch.mov &
sleep 1.2
open "$APP_PATH"
wait
swift /tmp/frames.swift /tmp/launch.mov
```

Frames land in `/tmp/launchframes/`. Open the frames immediately before and
after the first visible window; a window-size flash is easy to miss live.

Case note: the window frame is restored by SwiftUI/NSWindow before the window
is displayed. A default-size frame followed by a jump means the autosave key
changed — the scene content type must keep a stable name (keep top-level
wrappers non-private; a `private` type mangles to a per-launch address). The
first visible frame should already be the saved size.

## Settings window, focus ring and window state

1. Open Settings from the App menu (⌘,) — a second attempt must focus the same
   single window, never duplicate it. The sidebar footer should only offer
   Add Folder; settings has no second in-window entry.
2. The window is fixed-size and centered; resizing must be disabled.
3. Close the settings window, quit, and relaunch: the main window frame must
   survive, and the Settings window must not reopen by itself.
4. Click the custom toolbar sidebar toggle (the system toggle is removed and
   the replacement uses `.focusEffectDisabled()`), then the detail pane: the
   toggle must not keep a blue focus ring after the sidebar changes. The same
   must hold right after launch.
5. The sidebar must stay translucent all the way to the window's top edge,
   with the traffic lights floating over it. Scroll the detail pane: content
   must not show through the toolbar (the page-colored strip covers it).
6. Enter full screen: neither the native toolbar nor an inline replacement may
   appear, and there must be no glass band or clipped sidebar header. Exit full
   screen and confirm that the native toolbar and titlebar treatment return.
7. Close every window (⌘W; confirm with `axfind "AXWindow"`), then click the
   Dock icon: the main window must come back. Minimize it (⌘M) and click the
   Dock icon instead — the same window must deminiaturize, never a second one.
   The reopen path lives in `AppDelegate.applicationShouldHandleReopen`; a
   stock SwiftUI `WindowGroup` opens nothing on its own.

## Appearance and localization

### Dark mode

Temporarily switch the system appearance, capture, then revert:

```sh
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
# relaunch or let the running app follow the system
screencapture -x -R14,39,1172,763 /tmp/dark.png
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'
```

This changes the user's system setting; always revert. Check cards, secondary
labels, empty states, selection colors and the sidebar material for contrast.

### UI language

The in-app language applies on relaunch:

```sh
defaults write "$APP_BUNDLE_ID" language -string en
pkill -x "$APP_PROCESS"; sleep 1; open "$APP_PATH"; sleep 3
screencapture -x -R14,39,1172,763 /tmp/en.png
defaults delete "$APP_BUNDLE_ID" language   # restore Follow System
pkill -x "$APP_PROCESS"; sleep 1; open "$APP_PATH"
```

Verify visible app text, not AX labels: system-provided UI (standard menus,
dialogs) follows the system language and `CFBundleLocalizations`, not the
in-app override.

### Key parity

Every UI key must exist in both bundles. Run after adding strings:

```sh
make check-l10n
```

It reports missing keys in both directions and duplicate keys, and exits
nonzero on a mismatch.

## Empty states

1. Clear the saved folders: `defaults delete "$APP_BUNDLE_ID" folderBookmarks`
   (and the legacy `folderPaths` key if present), or remove every folder
   through the context menu.
2. Relaunch and verify the placeholder message, the icon, and the prominent
   "Add Folder" button are centered in the detail pane.
3. Add a folder, remove it again, and confirm the empty state returns.
4. Drag a folder over the sidebar and capture the drop highlight mid-drag.

## Performance measurements

`top` snapshots are noisy; measure average CPU from `ps` cumulative CPU time:

```sh
PID=$(pgrep -x "$APP_PROCESS")
start=$(ps -o time= -p "$PID" | tr -d ' '); t0=$(date +%s)
sleep 90
end=$(ps -o time= -p "$PID" | tr -d ' '); t1=$(date +%s)
python3 - "$start" "$end" "$t0" "$t1" <<'PY'
import sys
def secs(t):
    parts = [float(p) for p in t.split(':')]
    total = 0.0
    for part in parts:
        total = total * 60 + part
    return total
start, end, t0, t1 = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
print(f"cpu {(secs(end) - secs(start)) / (t1 - t0) * 100:.2f}% over {t1 - t0}s")
PY
```

Compare configurations deliberately:

- **Idle:** close every window (⌘W; confirm with `axfind "AXWindow"`), measure
  60–90 s.
- **Active:** open the changed surface and repeat.
- **Baseline:** disable or pause the new work when the UI allows it; the
  difference is its cost.

If one path looks expensive, add temporary millisecond marks around it, run
for ~20 samples, read the log, and remove the instrumentation before
committing. Use `sample` for a stack profile:

```sh
sample $(pgrep -x "$APP_PROCESS") 5 1 -file /tmp/app-sample.txt
```

## Defaults recipes

The `.app` stores preferences under its bundle ID; `swift run` uses a different
domain. `make app` and `make launch` write the normal
`~/Library/Preferences/<bundleID>.plist`. The sandboxed `make mas` build keeps
its domain and container under `~/Library/Containers/<bundleID>/Data`;
`defaults` normally resolves it through cfprefsd, but read the container's
`Library/Preferences/<bundleID>.plist` directly if a domain is not found.

| Key | Meaning |
| --- | --- |
| `folderBookmarks` | Sidebar folders (JSON-encoded path + security bookmark) |
| `folderPaths` | Legacy sidebar paths, read only when no bookmarks exist |
| `theme` | `system`, `light` or `dark` |
| `language` | `en`, `zh-Hans`, or absent for Follow System |

Window frames are not an app key: SwiftUI stores them under the scene's frame
autosave name, `NSWindow Frame main-AppWindow-1` for the main
`WindowGroup(id: "main")`.

```sh
defaults delete "$APP_BUNDLE_ID"            # clean slate
defaults write "$APP_BUNDLE_ID" theme -string dark
defaults write "$APP_BUNDLE_ID" language -string zh-Hans
```

Delete only the keys you changed when testing against real user state; prefer
a fresh domain on a throwaway user account or a VM.

## Per-change checklist

1. `swift test` — logic still passes.
2. `make check-l10n` — if any `.strings` file changed.
3. `make app` — universal (arm64 + x86_64) release build, unsandboxed
   signature (Developer ID or ad-hoc). Use `make mas` for the sandboxed App
   Store build and `make launch` for the dev identity.
4. Launch and capture the changed surface (window, settings pane, state).
5. Check the empty/error path if the surface has one.
6. Check dark mode and the other UI language for new strings.
7. Quit and relaunch — verify any persisted state (frame, theme, language,
   folders) survives.
8. If the window scene changed, record the launch and confirm the first visible
   frame is already the restored (or first-launch default) one.
9. If the change adds timers, watchers or scans, measure idle and active CPU
   before and after.

## Extending this playbook

This template has no menu bar items, no sampling loop and no privileged
sensors, so the probes above stop at windows, settings and localization. If a
fork adds those surfaces, add a section with the AX identifiers it needs (make
status items and search fields addressable) and keep the same
capture-and-inspect loop.

## Appendix: helper sources

Save each file as `/tmp/<name>.swift` and run `swift /tmp/<name>.swift ...`.
All coordinates are global, top-left origin. Set `APP_BUNDLE_ID` first.

### axpos.swift

```swift
import AppKit
import ApplicationServices

guard let bundleID = ProcessInfo.processInfo.environment["APP_BUNDLE_ID"], !bundleID.isEmpty else {
    print("set APP_BUNDLE_ID first"); exit(1)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("app not running"); exit(1)
}
let axApp = AXUIElementCreateApplication(app.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

guard let raw = attribute(axApp, kAXWindowsAttribute as String) as? [AXUIElement] else {
    print("no windows"); exit(1)
}
for window in raw {
    let title = attribute(window, kAXTitleAttribute as String) as? String ?? ""
    var position = CGPoint.zero
    var size = CGSize.zero
    if let p = attribute(window, kAXPositionAttribute as String) {
        AXValueGetValue(p as! AXValue, .cgPoint, &position)
    }
    if let s = attribute(window, kAXSizeAttribute as String) {
        AXValueGetValue(s as! AXValue, .cgSize, &size)
    }
    print("\(title) pos=\(position) size=\(size)")
}
```

### axfind.swift

```swift
import AppKit
import ApplicationServices

let query = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard let bundleID = ProcessInfo.processInfo.environment["APP_BUNDLE_ID"], !bundleID.isEmpty else {
    print("set APP_BUNDLE_ID first"); exit(1)
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("app not running"); exit(1)
}
let axApp = AXUIElementCreateApplication(app.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func frame(_ element: AXUIElement) -> CGRect? {
    var position = CGPoint.zero
    var size = CGSize.zero
    guard let p = attribute(element, kAXPositionAttribute as String),
          let s = attribute(element, kAXSizeAttribute as String) else { return nil }
    AXValueGetValue(p as! AXValue, .cgPoint, &position)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: position, size: size)
}
func text(_ element: AXUIElement) -> String {
    (attribute(element, kAXTitleAttribute as String) as? String)
        ?? (attribute(element, kAXDescriptionAttribute as String) as? String)
        ?? (attribute(element, kAXValueAttribute as String) as? String)
        ?? ""
}
func walk(_ element: AXUIElement, depth: Int) {
    let role = attribute(element, kAXRoleAttribute as String) as? String ?? ""
    let label = text(element)
    if !query.isEmpty,
       label.localizedCaseInsensitiveContains(query) || role.localizedCaseInsensitiveContains(query) {
        print("\(String(repeating: " ", count: depth))\(role) '\(label)' frame=\(frame(element).map(String.init(describing:)) ?? "nil")")
    }
    if depth < 12, let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] {
        for child in children { walk(child, depth: depth + 1) }
    }
}
walk(axApp, depth: 0)
```

### click.swift

```swift
import AppKit

guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else {
    print("usage: click x y"); exit(1)
}
let point = CGPoint(x: x, y: y)
let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}
post(.mouseMoved); usleep(20_000)
post(.leftMouseDown); usleep(60_000)
post(.leftMouseUp)
```

### drag.swift / draghold.swift

```swift
import AppKit

guard CommandLine.arguments.count >= 5,
      let x1 = Double(CommandLine.arguments[1]), let y1 = Double(CommandLine.arguments[2]),
      let x2 = Double(CommandLine.arguments[3]), let y2 = Double(CommandLine.arguments[4]) else {
    print("usage: drag x1 y1 x2 y2 [cmd]"); exit(1)
}
let command = CommandLine.arguments.contains("cmd")
let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                              mouseCursorPosition: point, mouseButton: .left) else { return }
    if command { event.flags = .maskCommand }
    event.post(tap: .cghidEventTap)
}
let start = CGPoint(x: x1, y: y1), end = CGPoint(x: x2, y: y2)
post(.mouseMoved, start); usleep(120_000)
post(.leftMouseDown, start); usleep(180_000)
for step in 1...20 {
    let t = Double(step) / 20
    post(.leftMouseDragged, CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t))
    usleep(30_000)
}
usleep(200_000)
post(.leftMouseUp, end)
```

For a hold-to-inspect drag, add `sleep(2_500_000)` before the mouse-up and run
the helper in the background, then capture the screen.

### frames.swift

```swift
import AVFoundation
import AppKit

guard CommandLine.arguments.count == 2 else { print("usage: frames video.mov"); exit(1) }
let asset = AVAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let dir = URL(fileURLWithPath: "/tmp/launchframes")
try? FileManager.default.removeItem(at: dir)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let seconds = CMTimeGetSeconds(asset.duration)
for index in 0..<Int(seconds * 60) {
    let time = CMTime(value: CMTimeValue(index), timescale: 60)
    guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: dir.appendingPathComponent(String(format: "frame-%04d.png", index)))
    }
}
print("frames in \(dir.path)")
```

`copyCGImage` is deprecated on macOS 15+ but still works; use
`generateCGImagesAsynchronously` if you prefer.
