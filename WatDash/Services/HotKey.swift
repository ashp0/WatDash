//
//  HotKey.swift
//  WatDash
//

import AppKit
import Carbon.HIToolbox

/// System-wide shortcut (⌃⌥Space) that opens quick capture from any app.
///
/// Carbon's RegisterEventHotKey is still the right tool for this: unlike a
/// global NSEvent monitor it needs no Accessibility permission, and it
/// swallows the keystroke instead of letting it through to the frontmost app.
@MainActor
final class HotKey {
    static let shared = HotKey()

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(action: @escaping () -> Void) {
        unregister()
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in HotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handler)

        let id = EventHotKeyID(signature: OSType(0x5744_4153), id: 1)  // 'WDAS'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
    }
}
