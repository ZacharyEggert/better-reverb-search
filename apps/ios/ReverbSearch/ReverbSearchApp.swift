import SwiftUI

@main
struct ReverbSearchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Re-check the stored promo code once per launch.
                .task { await BypassCode.refresh() }
        }
    }
}
