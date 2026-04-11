import SwiftUI

@main
struct CtxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene suppresses the default window — we're menu bar only
        Settings { EmptyView() }
    }
}
