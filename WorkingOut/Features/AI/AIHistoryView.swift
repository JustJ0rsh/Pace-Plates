import SwiftUI
import SwiftData
import EventKit

struct AIHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor<AIConversation>(\.date, order: .reverse)]) var conversations: [AIConversation]
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault

    var body: some View {
        Group {
            if conversations.isEmpty {
                ContentUnavailableView(
                    "No AI History Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Generated plans and saved AI questions will appear here.")
                )
            } else {
                List {
                    ForEach(conversations) { convo in
                        NavigationLink(destination: AIHistoryDetailView(convo: convo)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: convo.mode == "plan" ? "calendar" : "bubble.left.fill")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryTextColor)
                                    Text(convo.mode == "plan" ? "Workout Plan" : "Question")
                                        .font(.subheadline).bold()
                                        .foregroundStyle(AppTheme.secondaryTextColor)
                                    Spacer()
                                    Text(convo.date, style: .date)
                                        .foregroundStyle(AppTheme.secondaryTextColor)
                                        .font(.caption)
                                }
                                Text(displayTitle(for: convo))
                                    .lineLimit(2)
                                    .foregroundStyle(AppTheme.textColor)
                                    .font(.body)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("AI History")
        .toolbar {
            if !conversations.isEmpty {
                EditButton()
            }
        }
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .appBackground(AppTheme.gradientAI)
        .foregroundColor(AppTheme.textColor)
    }

    private func delete(at offsets: IndexSet) {
        guard let modelContext = conversations.first?.modelContext else { return }
        for index in offsets { modelContext.delete(conversations[index]) }
        _ = PersistenceSave.commit(modelContext, action: "save changes")
    }
    
    private func displayTitle(for convo: AIConversation) -> String {
        // If we have a prompt, use it
        if !convo.prompt.isEmpty {
            return convo.prompt
        }
        
        // Otherwise, try to extract a meaningful title from the response
        let lines = convo.response.components(separatedBy: .newlines)
        let meaningfulLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        if let firstLine = meaningfulLines.first {
            // Remove markdown headers
            let cleaned = firstLine.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
            return cleaned.trimmingCharacters(in: .whitespaces)
        }
        
        return "(No title)"
    }
}

struct AIHistoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let convo: AIConversation
    @State private var showShare = false
    @State private var showCalendarSuccess = false
    @State private var calendarError: String? = nil
    @AppStorage("useStructuredPlanView") private var useStructuredPlanView: Bool = false
    @AppStorage("selectedCalendarIdentifier") private var selectedCalendarIdentifier: String?
    @State private var showScheduleOptions = false
    @State private var scheduleStartTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var scheduleDurationMin: Int = 60
    @State private var showTemplateSuccess = false
    @State private var showDaySelection = false
    @State private var availableWorkoutDays: [(index: Int, title: String, type: String)] = []
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendar: EKCalendar?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with mode and date
                HStack {
                    Image(systemName: convo.mode == "plan" ? "calendar" : "bubble.left.fill")
                    Text(convo.mode == "plan" ? "Workout Plan" : "Question")
                        .font(.headline)
                    Spacer()
                    Text(convo.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
                
                // Show the prompt/title if available
                if !convo.prompt.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Text(convo.prompt)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                // Response content: structured cards when enabled and available; otherwise Markdown
                VStack(alignment: .leading, spacing: 4) {
                    Text("Response")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                    
                    #if canImport(FoundationModels)
                    if useStructuredPlanView, let json = convo.structuredPlanJSON, let view = try? StructuredPlanCards(json: json) {
                        view
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.textColor.opacity(0.08), AppTheme.textColor.opacity(0.02)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.textColor.opacity(0.15), lineWidth: 1)
                            )
                    } else if convo.response.isEmpty {
                        Text("(empty)")
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(AppTheme.textColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        MarkdownView(text: convo.response)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.textColor.opacity(0.08), AppTheme.textColor.opacity(0.02)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.textColor.opacity(0.15), lineWidth: 1)
                            )
                    }
                    #else
                    if convo.response.isEmpty {
                        Text("(empty)")
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(AppTheme.textColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        MarkdownView(text: convo.response)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [AppTheme.textColor.opacity(0.08), AppTheme.textColor.opacity(0.02)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.textColor.opacity(0.15), lineWidth: 1)
                            )
                    }
                    #endif
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Spacer()
                        
                        // Schedule to calendar (only for workout plans)
                        if convo.mode == "plan" {
                            Button {
                                showScheduleOptions = true
                            } label: {
                                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Button { showShare = true } label: { 
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Spacer()
                    }
                    
                    // Use as Template button (only for workout plans with structured data)
                    if convo.mode == "plan", convo.structuredPlanJSON != nil {
                        Button {
                            // Check available workout days
                            availableWorkoutDays = WorkoutTemplateService.shared.getAvailableWorkoutDays(from: convo)
                            if availableWorkoutDays.count > 1 {
                                showDaySelection = true
                            } else if let firstDay = availableWorkoutDays.first {
                                createTemplate(dayIndex: firstDay.index)
                            }
                        } label: {
                            Label("Use as Template", systemImage: "doc.badge.plus")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    }
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Saved Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .appBackground(AppTheme.gradientAI)
        .foregroundColor(AppTheme.textColor)
        .sheet(isPresented: $showShare) { ShareSheet(items: [convo.response]) }
        .sheet(isPresented: $showScheduleOptions) {
            NavigationStack {
                Form {
                    Section {
                        DatePicker("Start time", selection: $scheduleStartTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.compact)
                        
                        HStack {
                            Text("Duration")
                            Spacer()
                            Stepper(value: $scheduleDurationMin, in: 15...180, step: 15) {
                                Text("\(scheduleDurationMin) min")
                            }
                        }
                    } header: {
                        Text("Workout Time")
                    }
                    
                    Section {
                        if availableCalendars.isEmpty {
                            Text("Loading calendars...")
                                .foregroundStyle(AppTheme.secondaryTextColor)
                        } else {
                            Picker("Calendar", selection: $selectedCalendar) {
                                ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                                    HStack {
                                        Circle()
                                            .fill(Color(cgColor: calendar.cgColor))
                                            .frame(width: 12, height: 12)
                                        Text(calendar.title)
                                    }
                                    .tag(calendar as EKCalendar?)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }
                    } header: {
                        Text("Calendar")
                    } footer: {
                        Text("Events will be added to the selected calendar")
                    }
                }
                .navigationTitle("Schedule Options")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showScheduleOptions = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Schedule") {
                            // Save selected calendar
                            if let selected = selectedCalendar {
                                selectedCalendarIdentifier = selected.calendarIdentifier
                            }
                            showScheduleOptions = false
                            scheduleToCalendar(convo)
                        }
                        .disabled(selectedCalendar == nil)
                    }
                }
                .onAppear {
                    Task {
                        do {
                            try await WorkoutCalendarService.shared.requestAccess()
                            let calendars = WorkoutCalendarService.shared.getWritableCalendars()
                            await MainActor.run {
                                availableCalendars = calendars
                                // Set selected calendar from saved preference or default
                                if let savedId = selectedCalendarIdentifier,
                                   let saved = calendars.first(where: { $0.calendarIdentifier == savedId }) {
                                    selectedCalendar = saved
                                } else {
                                    selectedCalendar = calendars.first
                                }
                            }
                        } catch {
                            await MainActor.run {
                                calendarError = error.localizedDescription
                                showScheduleOptions = false
                            }
                        }
                    }
                }
            }
        }
        .alert("Added to Calendar", isPresented: $showCalendarSuccess) {
            Button("OK") { }
        } message: {
            Text("Your workout plan has been added to your calendar with reminders.")
        }
        .alert("Calendar Access", isPresented: .constant(calendarError != nil)) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                calendarError = nil
            }
            Button("Cancel", role: .cancel) { calendarError = nil }
        } message: {
            Text(calendarError ?? "Calendar access is required to add events. In Settings, enable Calendars for this app.")
        }
        .alert("Template Created", isPresented: $showTemplateSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Workout template has been created! You can now start a workout from this template in the Workouts tab.")
        }
        .sheet(isPresented: $showDaySelection) {
            NavigationStack {
                List {
                    ForEach(availableWorkoutDays, id: \.index) { day in
                        Button {
                            showDaySelection = false
                            createTemplate(dayIndex: day.index)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.title)
                                    .font(.headline)
                                    .foregroundColor(AppTheme.textColor)
                                Text(day.type)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryTextColor)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .navigationTitle("Select Workout Day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showDaySelection = false }
                    }
                }
            }
        }
    }
    
    private func createTemplate(dayIndex: Int) {
        if let _ = WorkoutTemplateService.shared.createTemplateFromAIPlan(
            conversation: convo,
            dayIndex: dayIndex,
            context: modelContext
        ) {
            showTemplateSuccess = true
            Haptics.notify(.success)
        }
    }
    
    private func scheduleToCalendar(_ convo: AIConversation) {
        Task {
            do {
                let hour = Calendar.current.component(.hour, from: scheduleStartTime)
                let minute = Calendar.current.component(.minute, from: scheduleStartTime)
                try await WorkoutCalendarService.shared.scheduleWorkoutPlan(
                    convo,
                    startHour: hour,
                    startMinute: minute,
                    durationMinutes: scheduleDurationMin,
                    calendarIdentifier: selectedCalendarIdentifier
                )
                await MainActor.run {
                    showCalendarSuccess = true
                    Haptics.notify(.success)
                }
            } catch {
                await MainActor.run {
                    calendarError = error.localizedDescription
                    Haptics.notify(.error)
                }
            }
        }
    }
}
