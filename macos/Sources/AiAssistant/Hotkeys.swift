import Carbon
import Foundation

private func hotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hid = EventHotKeyID()
    let err = GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hid
    )
    if err == noErr {
        Hotkeys.dispatch(id: hid.id)
    }
    return noErr
}

/// Phím tắt toàn cục qua Carbon (không cần quyền Accessibility):
/// ⌘⇧7 tóm tắt, ⌘⇧8 dịch, ⌘⇧9 giải đề, ⌘⇧0 kiểm tra lừa đảo.
/// Dự phòng: ⌃⌥S/T/G/K. Tránh ⌘⇧3/4/5 của hệ thống.
/// Mỗi phím nhận được đều log để chẩn đoán bàn phím PC (Logitech).
final class Hotkeys {
    private static var refs: [EventHotKeyRef?] = []
    private static var actions: [UInt32: (AiTask) -> Void] = [:]
    private static var installed = false

    /// Đăng ký; mỗi lần bấm gọi `action` với tác vụ tương ứng.
    static func register(action: @escaping (AiTask) -> Void) {
        // (mods, keyCode, id, task)
        let combos: [(UInt32, UInt32, UInt32, AiTask)] = [
            (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_7), 1, .summarize),
            (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_8), 2, .translate),
            (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_9), 3, .solve),
            (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_0), 4, .scamCheck),
            (UInt32(controlKey | optionKey), UInt32(kVK_ANSI_S), 11, .summarize),
            (UInt32(controlKey | optionKey), UInt32(kVK_ANSI_T), 12, .translate),
            (UInt32(controlKey | optionKey), UInt32(kVK_ANSI_G), 13, .solve),
            (UInt32(controlKey | optionKey), UInt32(kVK_ANSI_K), 14, .scamCheck),
        ]
        if !installed {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyHandler,
                1,
                &spec,
                nil,
                nil
            )
            installed = true
        }
        for (mods, key, hid, task) in combos {
            var ref_: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x41494141), id: hid)
            let err = RegisterEventHotKey(key, mods, id, GetApplicationEventTarget(), 0, &ref_)
            NSLog("AiAssistant hotkey id=\(hid) err=\(err)")
            refs.append(ref_)
            actions[hid] = action
            let _ = task
        }
    }

    private static var zoomRefs: [EventHotKeyRef?] = []

    /// Phóng to/thu nhỏ panel (⌘⇧= / ⌘⇧−): chỉ đăng ký khi panel mở.
    static func registerZoom(state: AppState) {
        unregisterZoom()
        let pairs: [(UInt32, UInt32)] = [
            (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_Equal)),
            (UInt32(cmdKey | shiftKey), UInt32(kVK_ANSI_Minus)),
        ]
        for (i, (mods, key)) in pairs.enumerated() {
            var ref_: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x41494141), id: UInt32(21 + i))
            RegisterEventHotKey(key, mods, id, GetApplicationEventTarget(), 0, &ref_)
            zoomRefs.append(ref_)
        }
        actions[21] = { _ in state.zoom = min(2.0, state.zoom + 0.1) }
        actions[22] = { _ in state.zoom = max(0.6, state.zoom - 0.1) }
    }

    static func unregisterZoom() {
        for r in zoomRefs { if let r { UnregisterEventHotKey(r) } }
        zoomRefs = []
        actions[21] = nil
        actions[22] = nil
    }

    fileprivate static func dispatch(id: UInt32) {
        NSLog("AiAssistant hotkey pressed id=\(id)")
        // Task suy từ id; gọi trên main để an toàn UI.
        let task: AiTask = (id == 2 || id == 12) ? .translate
            : (id == 3 || id == 13) ? .solve
            : (id == 4 || id == 14) ? .scamCheck : .summarize
        DispatchQueue.main.async { actions[id]?(task) }
    }
}
