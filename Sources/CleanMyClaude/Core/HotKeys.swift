import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: a virtual key code and Carbon modifier flags.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let space = UInt32(kVK_Space)

    static func carbon(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var hasModifier: Bool { modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 }

    /// "⌃⌥Espace", "⌘⇧K"…
    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Espace", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ForwardDelete: "⌦"
        ]
        if let s = special[Int(code)] { return s }
        // Ask the current keyboard layout which character this key types.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// System-wide shortcuts through Carbon's `RegisterEventHotKey`: no Accessibility permission needed.
/// Note: since macOS 15, shortcuts using only ⌥ or ⌥⇧ as modifiers are refused; `register` then returns false.
/// User choices are saved by id; nothing is registered in demo or snapshot mode.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [String: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var numbers: [String: UInt32] = [:]
    private var nextNumber: UInt32 = 1
    private var handlerInstalled = false
    /// The user's choices; a null entry means "no shortcut" (so the default does not come back at the next launch).
    private let saved = JSONStore<[String: KeyCombo?]>("hotkeys", default: [:])

    private init() {}

    /// The shortcut for `id`: the user's choice if any (including none at all), else `fallback`.
    func combo(for id: String, fallback: KeyCombo?) -> KeyCombo? {
        if let choice = saved.value[id] { return choice }
        return fallback
    }

    /// Registers the shortcut for `id`. Returns false if macOS refused it (taken or not allowed).
    @discardableResult
    func register(_ id: String, combo: KeyCombo?, action: @escaping () -> Void) -> Bool {
        unregister(id)
        guard let combo, !DemoData.isEnabled, !Snapshot.isActive else { return false }
        installHandler()
        let number = numbers[id] ?? {
            defer { nextNumber += 1 }
            return nextNumber
        }()
        numbers[id] = number
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434D_4348), id: number) // "CMCH"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        actions[number] = action
        return true
    }

    /// Saves the user's new shortcut for `id` (nil: none, remembered) and registers it.
    @discardableResult
    func change(_ id: String, to combo: KeyCombo?, action: @escaping () -> Void) -> Bool {
        saved.value[id] = .some(combo)
        return register(id, combo: combo, action: action)
    }

    func unregister(_ id: String) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        if let n = numbers[id] { actions[n] = nil }
    }

    fileprivate func fire(_ number: UInt32) {
        actions[number]?()
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let number = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.fire(number) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
