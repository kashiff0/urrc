import SwiftUI

struct ScheduleView: View {

    @ObservedObject var manager: ScheduleManager
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            List {
                if manager.schedules.isEmpty {
                    ContentUnavailableView(
                        "No Schedules",
                        systemImage: "calendar.badge.clock",
                        description: Text("Add a schedule to get daily reminders to photograph your reef.")
                    )
                } else {
                    ForEach(manager.schedules) { schedule in
                        ScheduleRow(schedule: schedule, manager: manager)
                    }
                    .onDelete { idx in
                        idx.forEach { manager.deleteSchedule(id: manager.schedules[$0].id) }
                    }
                }
            }
            .navigationTitle("Schedules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddScheduleSheet(manager: manager)
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Schedule Row

private struct ScheduleRow: View {

    let schedule: ReefSchedule
    @ObservedObject var manager: ScheduleManager

    private var timeString: String {
        let h = schedule.hour
        let m = schedule.minute
        let ampm = h >= 12 ? "PM" : "AM"
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", h12, m, ampm)
    }

    private var repeatString: String {
        if schedule.weekdays.isEmpty { return "Daily" }
        let names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        return schedule.weekdays.sorted().map { names[$0 - 1] }.joined(separator: ", ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.label.isEmpty ? "Reef Capture" : schedule.label)
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                Text("\(timeString) · \(repeatString)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { _ in manager.toggleSchedule(id: schedule.id) }
            ))
            .tint(.cyan)
        }
    }
}

// MARK: - Add Schedule Sheet

private struct AddScheduleSheet: View {

    @ObservedObject var manager: ScheduleManager
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var selectedHour = 9
    @State private var selectedMinute = 0
    @State private var weekdays: Set<Int> = []   // empty = daily

    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Morning Reef Shot", text: $label)
                }

                Section("Time") {
                    Picker("Hour", selection: $selectedHour) {
                        ForEach(0..<24) { h in
                            let ampm = h >= 12 ? "PM" : "AM"
                            let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
                            Text(String(format: "%d %@", h12, ampm)).tag(h)
                        }
                    }
                    Picker("Minute", selection: $selectedMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { m in
                            Text(String(format: ":%02d", m)).tag(m)
                        }
                    }
                }

                Section("Repeat") {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            Button {
                                if weekdays.contains(day) {
                                    weekdays.remove(day)
                                } else {
                                    weekdays.insert(day)
                                }
                            } label: {
                                Text(dayLabels[day - 1])
                                    .frame(width: 34, height: 34)
                                    .background(weekdays.contains(day) ? Color.cyan : Color.gray.opacity(0.3))
                                    .foregroundColor(weekdays.contains(day) ? .black : .white)
                                    .clipShape(Circle())
                                    .font(.caption.weight(.bold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if weekdays.isEmpty {
                        Text("Daily").font(.caption).foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("New Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let schedule = ReefSchedule(
                            label: label,
                            hour: selectedHour,
                            minute: selectedMinute,
                            weekdays: weekdays
                        )
                        manager.addSchedule(schedule)
                        manager.requestNotificationPermission()
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
