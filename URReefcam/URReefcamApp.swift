import SwiftUI
import BackgroundTasks

@main
struct URReefcamApp: App {

    init() {
        // BGTaskScheduler registration MUST happen before any view is created
        ScheduleManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
