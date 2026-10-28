import AppKit
import ServiceManagement

/// "Lancer au démarrage du Mac": adds or removes the app from the Mac's login items
/// (System Settings → General → Login Items), with `SMAppService`, the macOS service
/// made for that.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ isOn: Bool) {
        let service = SMAppService.mainApp
        do {
            if isOn {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Impossible de changer le lancement au démarrage"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        // macOS may ask you to allow it in System Settings first.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
