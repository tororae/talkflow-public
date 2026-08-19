import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut that stops everything.
///
/// Always-on delivery brings KakaoTalk forward to type, which can take the
/// screen away mid-sentence. Reaching TalkFlow's own window to switch it off is
/// exactly what a runaway send makes hard, so the stop has to work from wherever
/// the user is. Registered as a real system hot key rather than by watching
/// keystrokes: it needs no input-monitoring permission and it fires even while
/// another app owns the keyboard.
public final class GlobalStopHotKey: @unchecked Sendable {
    /// ⌃⌥⌘. — the period follows the Mac idiom for cancel, and the three
    /// modifiers keep it clear of anything an app is likely to claim.
    public static let displayName = "⌃⌥⌘."

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onStop: @Sendable () -> Void

    public init(onStop: @escaping @Sendable () -> Void) {
        self.onStop = onStop
    }

    deinit {
        unregister()
    }

    @discardableResult
    public func register() -> Bool {
        guard reference == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context, let event else { return noErr }
                var pressed = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                guard pressed.id == GlobalStopHotKey.identifier else { return noErr }
                Unmanaged<GlobalStopHotKey>.fromOpaque(context).takeUnretainedValue().onStop()
                return noErr
            },
            1,
            &eventType,
            context,
            &handler
        )
        guard installed == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        return RegisterEventHotKey(
            UInt32(kVK_ANSI_Period),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        ) == noErr
    }

    public func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private static let signature = OSType(0x54_46_4C_57) // 'TFLW'
    private static let identifier: UInt32 = 1
}
