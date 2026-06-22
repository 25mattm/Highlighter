import AppKit
import Carbon.HIToolbox

/// A thin wrapper over Carbon's `RegisterEventHotKey` that supports any number of
/// system-wide hotkeys, each dispatching to its own closure. Carbon is used
/// (rather than a global `CGEventTap`) because it needs no Accessibility or Input
/// Monitoring permission, which keeps first launch frictionless.
///
/// One shared event handler is installed once; incoming hotkey events are routed
/// to the registered closure by their `EventHotKeyID.id`.
final class HotKeyCenter {
    /// Modifier flags expressed with Carbon's constants (`cmdKey`, `shiftKey`, …).
    struct Modifiers: OptionSet {
        let rawValue: Int
        static let command = Modifiers(rawValue: cmdKey)
        static let shift = Modifiers(rawValue: shiftKey)
        static let option = Modifiers(rawValue: optionKey)
        static let control = Modifiers(rawValue: controlKey)
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private let signature: OSType = 0x4842_4B31 // "HBK1"
    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Registers a system-wide hotkey. Returns an opaque token for later
    /// `unregister(_:)`, or `nil` if the OS rejected it (e.g. another app already
    /// owns that exact combination).
    @discardableResult
    func register(keyCode: Int, modifiers: Modifiers, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers.rawValue),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return nil }

        nextID += 1
        registrations[id] = Registration(ref: ref, handler: handler)
        return id
    }

    /// Removes a single hotkey previously returned by `register`.
    func unregister(_ token: UInt32) {
        guard let registration = registrations.removeValue(forKey: token) else { return }
        UnregisterEventHotKey(registration.ref)
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }

                return center.dispatch(id: hotKeyID.id)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func dispatch(id: UInt32) -> OSStatus {
        guard let registration = registrations[id] else { return OSStatus(eventNotHandledErr) }
        registration.handler()
        return noErr
    }
}
