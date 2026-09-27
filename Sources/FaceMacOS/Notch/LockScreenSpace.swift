import AppKit

/// Moves windows into a private SkyLight space that sits above the lock screen, so the notch animation
/// stays visible while the Mac is locked (the same technique boringNotch uses via SkyLightWindow).
@MainActor
enum LockScreenSpace {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock: above the lock screen (300), below boot progress (500).
    private static let aboveLockScreenLevel: Int32 = 400

    private static let space: (connection: Int32, id: Int32, addWindows: SpaceAddWindows)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let mainConnection = dlsym(handle, "SLSMainConnectionID"),
              let create = dlsym(handle, "SLSSpaceCreate"),
              let setLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(handle, "SLSShowSpaces"),
              let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            Log.app.error("SkyLight unavailable; the notch won't show on the lock screen")
            return nil
        }
        let connection = unsafeBitCast(mainConnection, to: MainConnectionID.self)()
        let id = unsafeBitCast(create, to: SpaceCreate.self)(connection, 1, 0)
        _ = unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self)(connection, id, aboveLockScreenLevel)
        _ = unsafeBitCast(show, to: ShowSpaces.self)(connection, [id] as CFArray)
        return (connection, id, unsafeBitCast(add, to: SpaceAddWindows.self))
    }()

    static func move(_ window: NSWindow) {
        guard let space, window.windowNumber > 0 else { return }
        _ = space.addWindows(space.connection, space.id, [window.windowNumber] as CFArray, 7)
    }
}
