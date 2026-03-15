import BackgroundTasks
import UserNotifications
import SwiftUI

// MARK: - Schedule Entry

struct ReefSchedule: Codable, Identifiable {
    var id: UUID = UUID()
    var isEnabled: Bool = true
    var label: String
    var hour: Int          // 0–23
    var minute: Int        // 0–59
    var weekdays: Set<Int> // 1=Sun … 7=Sat; empty = daily
}

// MARK: - ScheduleManager

@MainActor
final class ScheduleManager: ObservableObject {

    static let shared = ScheduleManager()
    private static let bgTaskID = "com.ureefcam.refresh"
    private let schedulesKey = "com.ureefcam.schedules"

    @Published var schedules: [ReefSchedule] = [] {
        didSet { persist(); rescheduleAll() }
    }

    private init() { load() }

    // MARK: - BGTaskScheduler registration (call from App.init)

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ScheduleManager.bgTaskID,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }

    // MARK: - Background task handler

    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleNextBackgroundRefresh()

        let enabledSchedules = schedules.filter { $0.isEnabled }
        guard !enabledSchedules.isEmpty else {
            task.setTaskCompleted(success: true)
            return
        }

        // Fire local notification to prompt user to open app
        let content = UNMutableNotificationContent()
        content.title = "Reef Progress Capture"
        content.body = "Time to capture your reef's progress!"
        content.sound = .default
        content.userInfo = ["deepLink": "ureefcam://capture"]

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content,
                                             trigger: nil) // immediate
        UNUserNotificationCenter.current().add(request)

        task.setTaskCompleted(success: true)
    }

    // MARK: - Schedule next background refresh

    func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: ScheduleManager.bgTaskID)
        // Schedule for 15 minutes from now; system decides exact timing
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Local notification scheduling

    private func rescheduleAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        for schedule in schedules where schedule.isEnabled {
            scheduleNotification(for: schedule)
        }
        scheduleNextBackgroundRefresh()
    }

    private func scheduleNotification(for schedule: ReefSchedule) {
        let content = UNMutableNotificationContent()
        content.title = schedule.label.isEmpty ? "Reef Progress Capture" : schedule.label
        content.body = "Open URReefcam to capture today's progress."
        content.sound = .default
        content.userInfo = ["deepLink": "ureefcam://capture"]

        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute

        if schedule.weekdays.isEmpty {
            // Daily
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: "daily-\(schedule.id)",
                                                content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        } else {
            // Specific weekdays
            for weekday in schedule.weekdays {
                components.weekday = weekday
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: "\(schedule.id)-\(weekday)",
                                                    content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    // MARK: - Permission request

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    // MARK: - CRUD

    func addSchedule(_ schedule: ReefSchedule) {
        schedules.append(schedule)
    }

    func deleteSchedule(id: UUID) {
        schedules.removeAll { $0.id == id }
    }

    func toggleSchedule(id: UUID) {
        if let idx = schedules.firstIndex(where: { $0.id == id }) {
            schedules[idx].isEnabled.toggle()
        }
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(schedules) {
            UserDefaults.standard.set(data, forKey: schedulesKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: schedulesKey),
              let loaded = try? JSONDecoder().decode([ReefSchedule].self, from: data) else { return }
        schedules = loaded
    }
}
