import SwiftUI

@main
struct pointicartApp: App {
    @State private var appState = AppState()

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
}
