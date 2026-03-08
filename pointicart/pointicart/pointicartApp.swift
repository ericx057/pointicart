import SwiftUI
import CoreText

@main
struct pointicartApp: App {
    @State private var appState = AppState()

    init() {
        Self.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .onOpenURL { url in
                    appState.handleURL(url)
                }
                .onAppear {
                    Task {
                        _ = await NotificationService.requestPermission()
                    }
                }
        }
    }

    private static func registerFonts() {
        let fontNames = ["DMSans-Regular", "DMSans-Medium", "DMSans-Bold"]
        for name in fontNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                NSLog("[PTIC] Font file not found: %@.ttf", name)
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                NSLog("[PTIC] Failed to register font %@: %@", name, error?.takeRetainedValue().localizedDescription ?? "unknown")
            }
        }
    }
}
