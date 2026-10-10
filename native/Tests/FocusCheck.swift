@MainActor enum FocusFixture {
    static let processID = ProcessInfo.processInfo.processIdentifier + 1_000
    static let field = AXUIElementCreateApplication(processID + 1)
    static let otherField = AXUIElementCreateApplication(processID + 2)
    static var enabled = false
    static var supportsManualAccessibility = true
    static var readyAfter = 1
    static var reads = 0
    static var requests = 0
    static var focused = field
    static var secure = false
    static var queriedProcesses: [pid_t] = []
    static var textWrites = 0
    static var trusted = true
    static var invalidElement = false
    static var switchAppAfterRead: Int?

    static func reset() {
        enabled = false
        supportsManualAccessibility = true
        readyAfter = 1
        reads = 0
        requests = 0
        focused = field
        secure = false
        queriedProcesses = []
        textWrites = 0
        trusted = true
        invalidElement = false
        switchAppAfterRead = nil
        NSWorkspace.shared.frontmostApplication = Application(processIdentifier: FocusFixture.processID)
    }

    struct Application {
        let processIdentifier: pid_t
    }
}

@MainActor enum NSWorkspace {
    static let shared = Workspace()
    final class Workspace {
        var frontmostApplication: FocusFixture.Application?
    }
}

@MainActor func AXIsProcessTrusted() -> Bool { FocusFixture.trusted }

@MainActor @discardableResult
func AXUIElementCopyAttributeValue(
    _ element: AXUIElement, _ attribute: CFString, _ value: UnsafeMutablePointer<CFTypeRef?>
) -> AXError {
    switch attribute as String {
    case kAXFocusedUIElementAttribute:
        var pid: pid_t = 0
        _ = AXUIElementGetPid(element, &pid)
        FocusFixture.queriedProcesses.append(pid)
        FocusFixture.reads += 1
        if FocusFixture.reads == FocusFixture.switchAppAfterRead {
            NSWorkspace.shared.frontmostApplication = FocusFixture.Application(processIdentifier: FocusFixture.processID + 100)
        }
        guard FocusFixture.enabled, FocusFixture.reads >= FocusFixture.readyAfter else { return .noValue }
        value.pointee = FocusFixture.invalidElement ? "Invalid AX element" as CFString : FocusFixture.focused
    case kAXSubroleAttribute:
        value.pointee = (FocusFixture.secure ? kAXSecureTextFieldSubrole : "AXStandard") as CFString
    case kAXRoleAttribute:
        value.pointee = kAXTextAreaRole as CFString
    default:
        return .attributeUnsupported
    }
    return .success
}

@MainActor @discardableResult
func AXUIElementSetAttributeValue(_ element: AXUIElement, _ attribute: CFString, _ value: CFTypeRef) -> AXError {
    guard attribute as String == "AXManualAccessibility" else {
        FocusFixture.textWrites += 1
        return .attributeUnsupported
    }
    var pid: pid_t = 0
    _ = AXUIElementGetPid(element, &pid)
    guard pid == FocusFixture.processID else { return .invalidUIElement }
    FocusFixture.requests += 1
    guard FocusFixture.supportsManualAccessibility, CFEqual(value, kCFBooleanTrue) else { return .attributeUnsupported }
    FocusFixture.enabled = true
    return .success
}

@main struct FocusCheck {
    @MainActor static func main() async throws {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw NSError(domain: message, code: 1) }
        }

        FocusFixture.reset()
        let immediate = FocusTarget.capture()
        try require(immediate?.element.map { CFEqual($0, FocusFixture.field) } == true,
                    "Electron cursor was missed with initially inactive accessibility")
        print("Electron cursor with initially inactive accessibility: FOUND")

        FocusFixture.reset()
        FocusFixture.readyAfter = 3
        guard let delayed = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        try require(delayed.element == nil, "Fixture must begin with an unpublished cursor")
        let resolved = try await delayed.resolved()
        try require(resolved.element.map { CFEqual($0, FocusFixture.field) } == true,
                    "Delayed Electron cursor did not resolve")
        _ = try resolved.validate()
        _ = try resolved.validate()
        try require(FocusFixture.requests == 1, "Validation must not repeatedly enable accessibility")
        try require(FocusFixture.queriedProcesses.allSatisfy { $0 == FocusFixture.processID }, "Resolution queried another process")
        print("Delayed cursor resolves once; validation remains read-only")

        FocusFixture.focused = FocusFixture.otherField
        do {
            _ = try resolved.validate()
            throw NSError(domain: "Changed field was incorrectly accepted", code: 1)
        } catch InsertionError.focusChanged {}
        try require(FocusFixture.textWrites == 0, "Changed focus caused a text write")
        print("Changed field is rejected without writing text")

        FocusFixture.reset()
        FocusFixture.secure = true
        guard let secure = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        do {
            _ = try secure.validate()
            throw NSError(domain: "Password field was incorrectly accepted", code: 1)
        } catch InsertionError.secureField {}
        print("Password field remains rejected")

        FocusFixture.reset()
        FocusFixture.supportsManualAccessibility = false
        FocusFixture.enabled = true
        guard let native = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        _ = try native.validate()
        print("Native fields work when manual accessibility is unsupported")

        FocusFixture.reset()
        FocusFixture.readyAfter = .max
        guard let unavailable = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        do {
            _ = try await unavailable.resolved()
            throw NSError(domain: "Missing cursor did not time out", code: 1)
        } catch InsertionError.focusUnavailable {}
        try require(FocusFixture.reads == 13, "Cursor lookup did not stop at its retry bound")
        print("Unavailable cursor stops at the retry bound")

        FocusFixture.reset()
        FocusFixture.readyAfter = .max
        guard let switched = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        NSWorkspace.shared.frontmostApplication = FocusFixture.Application(processIdentifier: FocusFixture.processID + 100)
        do {
            _ = try await switched.resolved()
            throw NSError(domain: "Switched app was incorrectly accepted", code: 1)
        } catch InsertionError.focusChanged {}
        try require(FocusFixture.reads == 1 && FocusFixture.textWrites == 0, "Switched app triggered a lookup or write")
        print("App switching stops cursor resolution without writing text")

        FocusFixture.reset()
        FocusFixture.readyAfter = .max
        FocusFixture.switchAppAfterRead = 3
        guard let switchedDuringWait = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        do {
            _ = try await switchedDuringWait.resolved()
            throw NSError(domain: "App switching during a retry was incorrectly accepted", code: 1)
        } catch InsertionError.focusChanged {}
        try require(FocusFixture.reads == 3, "Resolution continued querying after the app switched")
        print("App switching during a retry stops further queries")

        FocusFixture.reset()
        guard let existing = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        FocusFixture.enabled = false
        do {
            _ = try existing.validate()
            throw NSError(domain: "Unavailable focus was incorrectly accepted", code: 1)
        } catch InsertionError.focusUnavailable {}
        try require(FocusFixture.textWrites == 0, "Unavailable focus caused a text write")
        print("Unreadable focus reports unavailable instead of a changed field")

        FocusFixture.reset()
        FocusFixture.trusted = false
        guard let untrusted = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        do {
            _ = try untrusted.validate()
            throw NSError(domain: "Missing permission was incorrectly accepted", code: 1)
        } catch InsertionError.permission {}
        print("Missing Keyboard access reports a permission error")

        FocusFixture.reset()
        FocusFixture.invalidElement = true
        guard let invalid = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        try require(invalid.element == nil, "Invalid Accessibility value was cast to a field")
        do {
            _ = try await invalid.resolved()
            throw NSError(domain: "Invalid Accessibility values did not time out", code: 1)
        } catch InsertionError.focusUnavailable {}
        try require(FocusFixture.textWrites == 0, "Invalid Accessibility value caused a text write")
        print("Invalid Accessibility responses stop safely without writing text")

        FocusFixture.reset()
        FocusFixture.readyAfter = .max
        guard let canceled = FocusTarget.capture() else { throw InsertionError.focusUnavailable }
        let task = Task { try await canceled.resolved() }
        task.cancel()
        do {
            _ = try await task.value
            throw NSError(domain: "Canceled lookup continued", code: 1)
        } catch is CancellationError {}
        try require(FocusFixture.reads == 1 && FocusFixture.textWrites == 0, "Canceled lookup read or wrote text")
        print("Canceled cursor resolution stops before another lookup")
        print("Focus checks: PASS")
    }
}
