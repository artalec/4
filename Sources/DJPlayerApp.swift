import SwiftUI
import AppKit

// MARK: - Application entry point
// ВАЖНО: файл намеренно НЕ называется main.swift. Если положить @main
// в файл с именем main.swift, компилятор трактует модуль как содержащий
// top-level код и падает с ошибкой
// "'main' attribute cannot be used in a module that contains top-level code".

@main
struct DJPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("DJPlayer") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Воспроизведение") {
                Button("Воспроизвести / пауза") {
                    AppModel.shared.togglePlayPause()
                }
                Button("Остановить") {
                    AppModel.shared.audioEngine.stop()
                }
            }
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Глобальный перехват клавиш на уровне окна (работает и в macOS 13,
        // в отличие от SwiftUI .onKeyPress, который появился только в macOS 14).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Не перехватываем ввод в текстовых полях
            if event.window?.firstResponder is NSTextView { return event }

            switch event.keyCode {
            case 49: // Space
                guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
                AppModel.shared.togglePlayPause()
                return nil
            case 53: // Escape
                AppModel.shared.audioEngine.stop()
                return nil
            default:
                return event
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.save()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
