//  © 2026 Ankur Sinha. All rights reserved. Part of Firmament (MIT).
import SwiftUI

@main
struct NightSkyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
