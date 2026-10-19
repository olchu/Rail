import AppKit
import ApplicationServices

/// Undocumented calls for windows on other Spaces: the public Accessibility API neither lists
/// them nor can switch to them. The same approach AltTab uses. Symbols are resolved at runtime,
/// so if macOS drops one, Rail falls back to current-Space behavior instead of failing to launch.
@MainActor
enum PrivateAPI {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let hiServices = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let getWindow: GetWindow? = symbol("_AXUIElementGetWindow", in: hiServices)
    private static let createWithRemoteToken: CreateWithRemoteToken? = symbol("_AXUIElementCreateWithRemoteToken", in: hiServices)
    private static let getProcessForPID: GetProcessForPID? = symbol("GetProcessForPID", in: hiServices)
    private static let setFrontProcess: SetFrontProcess? = symbol("_SLPSSetFrontProcessWithOptions", in: skyLight)
    private static let postEventRecord: PostEventRecord? = symbol("SLPSPostEventRecordTo", in: skyLight)
    private static let mainConnectionID: MainConnectionID? = symbol("SLSMainConnectionID", in: skyLight)
    private static let copySpacesForWindows: CopySpacesForWindows? = symbol("SLSCopySpacesForWindows", in: skyLight)

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    /// The window server's number for a window element; stable for the life of the window.
    static func windowNumber(_ element: AXUIElement) -> CGWindowID? {
        var number: CGWindowID = 0
        guard let getWindow, getWindow(element, &number) == .success, number != 0 else { return nil }
        return number
    }

    /// Whether the window belongs to some Space. Background tabs of a system tab bar belong to none,
    /// while windows on other Spaces do. Nil when the private calls are unavailable.
    static func isOnSpace(_ number: CGWindowID) -> Bool? {
        guard let mainConnectionID, let copySpacesForWindows else { return nil }
        let allSpaces: Int32 = 7
        let spaces = copySpacesForWindows(mainConnectionID(), allSpaces, [NSNumber(value: number)] as CFArray)?
            .takeRetainedValue() as? [NSNumber]
        return !(spaces ?? []).isEmpty
    }

    /// Finds standard windows of an app by trying element IDs one by one: AX hands out
    /// windows on other Spaces only this way. Stops once every wanted window turns up
    /// or the time budget runs out.
    static func scanWindows(of pid: pid_t, wanted: Set<CGWindowID>,
                            budget: Duration = .milliseconds(100)) -> [CGWindowID: AXUIElement] {
        guard let createWithRemoteToken, !wanted.isEmpty else { return [:] }
        // Remote token layout: pid, 0, "coco", then the 64-bit element ID.
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: pid, toByteOffset: 0, as: pid_t.self)
            bytes.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            bytes.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
        }
        var found: [CGWindowID: AXUIElement] = [:]
        let clock = ContinuousClock()
        let deadline = clock.now + budget
        for elementID in UInt64(0)..<1000 where clock.now < deadline {
            token.withUnsafeMutableBytes { $0.storeBytes(of: elementID, toByteOffset: 12, as: UInt64.self) }
            guard let element = createWithRemoteToken(token as CFData)?.takeRetainedValue(),
                  element.value(kAXSubroleAttribute) as String? == kAXStandardWindowSubrole,
                  let number = windowNumber(element), wanted.contains(number) else { continue }
            found[number] = element
            if found.count == wanted.count { break }
        }
        return found
    }

    /// Makes the window key and its app frontmost, switching to the window's Space if needed.
    /// Returns false when the private calls are unavailable.
    static func bringToFront(_ pid: pid_t, window number: CGWindowID) -> Bool {
        guard let getProcessForPID, let setFrontProcess, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, number, userGenerated) == .success else { return false }

        // Synthetic "make key window" event record: mouse down, then up, aimed at the window.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: number) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        bytes.replaceSubrange(0x20..<0x30, with: repeatElement(0xff, count: 0x10))
        for phase: UInt8 in [0x01, 0x02] {
            bytes[0x08] = phase
            _ = postEventRecord(&psn, &bytes)
        }
        return true
    }
}
