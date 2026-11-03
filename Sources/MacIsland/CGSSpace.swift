import AppKit
import IslandCore

// Private SkyLight API (exported by CoreGraphics). A window in its own space with an absolute
// level isn't part of any desktop, so it stays put while three-finger swipes slide the desktops
// underneath, and shows over full-screen apps too. Same approach as other notch apps.
private typealias CGSConnectionID = Int32
private typealias CGSSpaceID = UInt64

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ flag: Int32, _ options: NSDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int32)
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray)
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)
@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ cid: CGSConnectionID, _ spaces: NSArray)

/// A desktop-independent space that keeps its windows visible through Space switches.
@MainActor
final class StickySpace {
    private let connection = _CGSDefaultConnection()
    private let space: CGSSpaceID
    private var windowNumbers: [Int] = []

    init(level: Int32 = Int32.max) {
        space = CGSSpaceCreate(connection, 1, nil)
        CGSSpaceSetAbsoluteLevel(connection, space, level)
        CGSShowSpaces(connection, [NSNumber(value: space)])
    }

    func add(_ window: NSWindow) {
        let number = window.windowNumber
        guard number > 0, !windowNumbers.contains(number) else { return }
        windowNumbers.append(number)
        CGSAddWindowsToSpaces(connection, [NSNumber(value: number)], [NSNumber(value: space)])
    }

    deinit {
        let spaces: NSArray = [NSNumber(value: space)]
        CGSRemoveWindowsFromSpaces(connection, windowNumbers.map { NSNumber(value: $0) } as NSArray, spaces)
        CGSHideSpaces(connection, spaces)
        CGSSpaceDestroy(connection, space)
    }
}
