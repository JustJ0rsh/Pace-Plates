import SwiftUI
import SwiftData
import EventKit

struct AIConversationSheet: View {
    enum Mode: String { case plan, ask }

    struct Citation: Identifiable {
        let id = UUID()
        let number: Int
        let title: String
        let url: String
        let snippet: String
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let mode: Mode
    let request: WorkoutPlanRequest

    @State private var content: String = ""
    @State private var isStreaming: Bool = true
    @State private var errorText: String? = nil
    @State private var showShare: Bool = false
    @State private var showSaved: Bool = false
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var displayedText: String = ""
    @State private var fullBufferedText: String = ""
    @State private var streamingOpacity: Double = 0.5
    @State private var citations: [Citation] = []
    @State private var showCalendarSuccess = false
    @State private var calendarError: String? = nil
    @State private var showScheduleOptions = false
    @State private var scheduleStartTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var scheduleDurationMin: Int = 60
    @State private var cachedBaselinePaceMinPerUnit: Double? = nil
    @State private var structuredPlanJSON: String? = nil
    @AppStorage("useStructuredPlanView") private var useStructuredPlanView: Bool = false
    @AppStorage("selectedCalendarIdentifier") private var selectedCalendarIdentifier: String?
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendar: EKCalendar?
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var autoFollow: Bool = true
    @State private var userIsDragging: Bool = false
    @State private var showTemplateSuccess = false
    @State private var createdTemplatesCount = 0
    @State private var waitingForFirstChunk = true
    @State private var conversationID = UUID()

    init(mode: Mode, request: WorkoutPlanRequest) {
        self.mode = mode
        self.request = request
        // Parse citations from existing content if available
        _citations = State(initialValue: parseCitations(from: ""))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if isStreaming && waitingForFirstChunk {
                            preStreamLoadingContent
                        } else {
                            #if canImport(FoundationModels)
                            if let json = structuredPlanJSON, useStructuredPlanView, let view = try? StructuredPlanCards(json: json) {
                                view
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(AppTheme.secondaryBackgroundColor.opacity(0.92))
                                    )
                                    .id("streamText")
                                    .opacity(isStreaming ? streamingOpacity : 1.0)
                            } else {
                                MarkdownView(text: displayText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(AppTheme.secondaryBackgroundColor.opacity(0.92))
                                    )
                                    .id("streamText")
                                    .opacity(isStreaming ? streamingOpacity : 1.0)
                            }
                            #else
                            MarkdownView(text: displayText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppTheme.secondaryBackgroundColor.opacity(0.92))
                                )
                                .id("streamText")
                                .opacity(isStreaming ? streamingOpacity : 1.0)
                            #endif
                            
                            // Citations section at the bottom
                            if !citations.isEmpty {
                                citationsSection
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ConversationScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                            .onAppear {
                                contentHeight = geo.size.height
                            }
                            .onChange(of: geo.size.height) { _, newHeight in
                                contentHeight = newHeight
                            }
                        }
                    )
                    // Remove in-scroll overlays; we'll add Safari-like top/bottom overlays anchored to safe areas below
                }
                .coordinateSpace(name: "scroll")
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            scrollViewHeight = geo.size.height
                        }
                        .onChange(of: geo.size.height) { _, newHeight in
                            scrollViewHeight = newHeight
                        }
                    }
                )
                .onPreferenceChange(ConversationScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    // While streaming, follow only when pinned and not actively dragging
                    if isStreaming { autoFollow = isPinnedToBottom && !userIsDragging }
                }
                .onChange(of: displayedText) { _, _ in
                    // Follow stream while autoFollow is active
                    if isStreaming && autoFollow {
                        withAnimation(.linear(duration: 0.12)) { proxy.scrollTo("streamText", anchor: .bottom) }
                    }
                }
            }
            .navigationTitle(mode == .plan ? "Weekly Training Plan" : "AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: { Image(systemName: "tray.and.arrow.down") }
                        .accessibilityLabel("Save")
                        .disabled(content.isEmpty)
                }
                
                // Actions moved to bottom bar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomActionBar }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
            .appBackground(AppTheme.gradientRuns)
            .foregroundColor(AppTheme.textColor)
            // Do not block scrolling: observe drag simultaneously
            .simultaneousGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        if isStreaming {
                            userIsDragging = true
                            autoFollow = false
                        }
                    }
                    .onEnded { _ in
                        // Small delay to avoid flicker, then re-evaluate pinned
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            userIsDragging = false
                            if isStreaming { autoFollow = isPinnedToBottom }
                        }
                }
            )
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [content])
        }
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
                                .foregroundStyle(.secondary)
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
                            scheduleToCalendar()
                        }
                        .disabled(content.isEmpty || selectedCalendar == nil)
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
        .alert("Plan Ready", isPresented: $showTemplateSuccess) {
            Button("OK") { }
        } message: {
            Text("Coach activated this plan and created \(createdTemplatesCount) executable session\(createdTemplatesCount == 1 ? "" : "s").")
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
        .task { 
            // Pre-compute a baseline pace from recent local runs for sanity checks
            cachedBaselinePaceMinPerUnit = computeBaselinePaceMinutes()
            streamTask = Task { await stream() }
        }
        .onDisappear {
            // Cancel any ongoing streaming when the view disappears
            streamTask?.cancel()
            streamTask = nil
            isStreaming = false
            waitingForFirstChunk = false
        }
        .alert("Error", isPresented: .constant(errorText != nil)) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
        .alert("Saved", isPresented: $showSaved) {
            Button("OK", role: .cancel) { showSaved = false }
        } message: { Text("Conversation saved") }
    }

    private var displayText: String {
        if displayedText.isEmpty && fullBufferedText.isEmpty {
            // If streaming is done but we have no content, show error message
            if !isStreaming {
                return "No response generated. Please try again."
            }
            return ""
        }
        return displayedText
    }

    @ViewBuilder
    private var preStreamLoadingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                Spacer(minLength: 40)
                loadingBubble(text: loadingPromptText, isAssistant: false, isGeneratingBubble: false)
            }

            HStack(alignment: .bottom) {
                loadingBubble(text: "Generating…", isAssistant: true, isGeneratingBubble: true)
                    .id("streamText")
                Spacer(minLength: 40)
            }
        }
    }

    private var loadingPromptText: String {
        let trimmed = request.extraContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if mode == .plan {
            return "Create a weekly training plan for my \(request.goal) goal."
        }
        return "Help with my training and fitness questions."
    }

    @ViewBuilder
    private func loadingBubble(text: String, isAssistant: Bool, isGeneratingBubble: Bool) -> some View {
        let bubbleFill: Color = isAssistant
            ? AppTheme.secondaryBackgroundColor.opacity(0.90)
            : AppTheme.accentColor.opacity(0.22)

        VStack(alignment: .leading, spacing: 0) {
            if isGeneratingBubble {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.textColor))
                        .scaleEffect(0.85)
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textColor)
                }
                .padding(14)
            } else {
                MarkdownView(text: text)
                    .padding(14)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(bubbleFill)

                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(AppTheme.textColor.opacity(0.12), lineWidth: 1)
            }
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .opacity(isAssistant && isGeneratingBubble ? streamingOpacity : 1.0)
    }
    
    // Subtle top/bottom fade overlays inside the chat tile to achieve a "liquid glass" edge blend
    @ViewBuilder
    private var tileFadeOverlays: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.22),
                    Color.white.opacity(0.10),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 22)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .compositingGroup()
        .opacity(0.9)
    }
    
    private var citationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(citations) { citation in
                        CitationTile(citation: citation)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 16)
        .background(AppTheme.secondaryBackgroundColor.opacity(0.90))
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func stream() async {
        do {
            // Start clear and gradually become visible
            await MainActor.run {
                streamingOpacity = 0.2
                displayedText = ""
                fullBufferedText = ""
                waitingForFirstChunk = true
                autoFollow = true
                withAnimation(.easeInOut(duration: 0.25)) {
                    streamingOpacity = 1.0
                }
            }

            // Per-request token so overlapping generations never read each other's plan JSON.
            let requestToken = UUID()
            // Drain the token's entry even if the stream throws below; the normal-path
            // read removes it first, making this a no-op on success.
            defer { _ = WorkoutPlanGenerator.takeStructuredPlanJSON(for: requestToken) }

            for try await chunk in WorkoutPlanGenerator.shared.generatePlanStream(request: request, token: requestToken) {
                // Check for cancellation
                if Task.isCancelled { break }
                
                await MainActor.run {
                    if waitingForFirstChunk && !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        waitingForFirstChunk = false
                    }
                    fullBufferedText += chunk
                    displayedText = fullBufferedText
                    content = fullBufferedText
                }
            }

            // Read (and remove) only this request's structured plan JSON.
            let producedPlanJSON = WorkoutPlanGenerator.takeStructuredPlanJSON(for: requestToken)

            await MainActor.run {
                structuredPlanJSON = producedPlanJSON

                var finalized = fullBufferedText
                if mode == .plan,
                   let structuredPlanJSON {
                    #if canImport(FoundationModels)
                    if let markdown = WorkoutPlanGenerator.markdownFromStructuredPlanJSON(
                        structuredPlanJSON,
                        weightUnit: request.weightUnit,
                        distanceUnit: request.distanceUnit
                    ) {
                        finalized = markdown
                    }
                    #endif
                }

                finalized = sanitize(finalized)
                finalized = fillPlaceholdersIfNeeded(in: finalized)

                fullBufferedText = finalized
                displayedText = finalized
                content = finalized
                citations = parseCitations(from: finalized)
            }
        } catch is CancellationError {
            // Silently handle cancellation
        } catch {
            await MainActor.run { errorText = error.localizedDescription }
        }
        await MainActor.run {
            isStreaming = false
            waitingForFirstChunk = false
            streamingOpacity = 1.0
            streamTask = nil
            autoFollow = false
        }
    }

    private func fillPlaceholdersIfNeeded(in full: String) -> String {
        // Replace lines like "- Day 1: ..." with simple, data-informed suggestions
        let baselines = ExerciseRecommendationService.baselines(context: request.modelContext, preferredUnit: request.weightUnit)
        guard !baselines.isEmpty else { return full }

        let unit = request.weightUnit
        let top = Array(baselines.prefix(5))
        var idx = 0

        func trio() -> String {
            // Pick three exercises, rotating
            let a = top[idx % top.count]; idx += 1
            let b = top[idx % top.count]; idx += 1
            let c = top[idx % top.count]; idx += 1
            let la = ExerciseRecommendationService.suggestedLoads(e1rm: a.e1rm, unit: unit, repTargets: [6])
            let lb = ExerciseRecommendationService.suggestedLoads(e1rm: b.e1rm, unit: unit, repTargets: [8])
            let lc = ExerciseRecommendationService.suggestedLoads(e1rm: c.e1rm, unit: unit, repTargets: [10])
            let sa = la[6].map { "**\(a.name)** — 4x6 @ \(Int($0)) \(unit)" } ?? "**\(a.name)** — 4x6"
            let sb = lb[8].map { "**\(b.name)** — 4x8 @ \(Int($0)) \(unit)" } ?? "**\(b.name)** — 4x8"
            let sc = lc[10].map { "**\(c.name)** — 3x10 @ \(Int($0)) \(unit)" } ?? "**\(c.name)** — 3x10"
            return "\(sa); \(sb); \(sc)"
        }

        let lines = full.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        let mapped = lines.map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            // Match bullets starting with '-' or '•'
            if (t.hasPrefix("- Day ") || t.hasPrefix("• Day ")) && t.contains("...") {
                return line.replacingOccurrences(of: "...", with: trio())
            }
            return line
        }
        return mapped.joined(separator: "\n")
    }

    private func sanitize(_ full: String) -> String {
        // Filter out obvious system/instruction lines but accept content by default
        let rawLines = full.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var out: [String] = []
        var started = false
        var skippingContext = false
        
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            // Start accepting content when we see common heading patterns OR any substantive content
            if !started {
                // Obvious system/instruction lines to skip at the beginning
                if lower.hasPrefix("you are") || 
                   lower.hasPrefix("generate") ||
                   lower.hasPrefix("create a") && lower.contains("training plan") && line == full.components(separatedBy: "\n").first ||
                   lower.hasPrefix("output format:") ||
                   lower.hasPrefix("instructions:") {
                    continue
                }
                
                // Accept content when we see headings OR substantive text (more than 10 chars and not a system message)
                if lower.hasPrefix("#") || // Any markdown heading
                   lower.hasPrefix("**day ") || // Bold day markers
                   lower.hasPrefix("day ") ||
                   lower.contains("training plan") ||
                   lower.contains("workout") ||
                   lower.contains("week ") ||
                   (trimmed.count > 10 && !lower.contains("format") && !lower.contains("instruction")) {
                    started = true
                }
                
                // If we haven't started yet, skip this line
                if !started { continue }
            }

            // Skip any lines that echo prompt scaffolding (even after started)
            if lower.hasPrefix("notes:") && lower.count < 20 { continue }
            if lower.contains("output format strictly") { continue }
            if lower.hasPrefix("output format") { continue }

            // Skip baselines echo block
            if lower.hasPrefix("recent exercise baselines") { skippingContext = true; continue }
            if skippingContext {
                if trimmed.isEmpty || lower.hasPrefix("## week ") || lower.hasPrefix("### week") { 
                    skippingContext = false 
                } else { 
                    continue 
                }
            }

            out.append(line)
        }

        // Ensure unique consecutive duplicates removed (helps when model streams repeats)
        var dedup: [String] = []
        for l in out {
            if dedup.last != l { dedup.append(l) }
        }
        var base = dedup.joined(separator: "\n")
        // Improve formatting: convert workout type labels to headings
        base = formatWorkoutTypeLabels(in: base)
        // For plans, normalize rest/recovery lines so a day is either training or rest, not both,
        // and fix any obviously inconsistent run durations using baseline pace.
        if mode == .plan { base = normalizeRestAndRecovery(in: base) }
        if mode == .plan { base = fixRunDurations(in: base, baselineMinPerUnit: cachedBaselinePaceMinPerUnit) }
        return base
    }

    // Convert workout type labels from bullets to headings for better formatting
    // e.g., "- Strength exercises:" → "#### Strength Exercises"
    private func formatWorkoutTypeLabels(in text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var out: [String] = []
        
        // Common workout type keywords that should be headings
        let workoutTypes = [
            "strength exercises", "strength training", "strength workout",
            "cardio exercises", "cardio training", "cardio workout", "cardio",
            "flexibility exercises", "flexibility training", "flexibility workout", "flexibility",
            "mobility exercises", "mobility training", "mobility workout", "mobility",
            "warm-up exercises", "warm-up", "warmup",
            "cool-down exercises", "cool-down", "cooldown",
            "core exercises", "core training", "core workout",
            "upper body", "lower body", "full body",
            "hiit workout", "hiit training",
            "stretching exercises", "stretching",
            "active recovery", "recovery workout"
        ]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            
            // Check if this is a bullet point with a workout type label
            var isWorkoutTypeLabel = false
            var labelText = ""
            
            // Match "- Workout Type:" or "• Workout Type:" patterns
            if (lower.hasPrefix("- ") || lower.hasPrefix("• ")) {
                // Remove bullet and trim
                var content = trimmed
                if content.hasPrefix("- ") {
                    content.removeFirst(2)
                } else if content.hasPrefix("• ") {
                    content.removeFirst(2)
                }
                content = content.trimmingCharacters(in: .whitespaces)
                
                // Remove bold markers if present
                content = content.replacingOccurrences(of: "**", with: "")
                
                // Check if it ends with a colon (typical for category labels)
                if content.hasSuffix(":") {
                    let withoutColon = String(content.dropLast()).trimmingCharacters(in: .whitespaces)
                    let lowerWithoutColon = withoutColon.lowercased()
                    
                    // Check if this matches a workout type
                    for workoutType in workoutTypes {
                        if lowerWithoutColon == workoutType || 
                           lowerWithoutColon.contains(workoutType) && lowerWithoutColon.count < workoutType.count + 10 {
                            isWorkoutTypeLabel = true
                            // Capitalize properly
                            labelText = withoutColon.capitalized
                            break
                        }
                    }
                }
            }
            
            if isWorkoutTypeLabel && !labelText.isEmpty {
                // Convert to heading (#### for smaller heading)
                out.append("#### \(labelText)")
            } else {
                // Keep line as-is
                out.append(line)
            }
        }
        
        return out.joined(separator: "\n")
    }
    
    // Ensure that for each Day section, if there are any training lines present, we remove stray
    // "Rest Day"/"Active Recovery" lines. If the day is rest-only, keep a single rest label.
    private func normalizeRestAndRecovery(in text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var out: [String] = []

        var currentHeader: String? = nil
        var currentDetails: [String] = []

        func flush() {
            guard let header = currentHeader else { return }
            // Determine if day has any non-rest detail
            let cleanTokens: [(String, String)] = currentDetails.map { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                var s = t
                if s.hasPrefix("- ") { s.removeFirst(2) }
                if s.hasPrefix("• ") { s.removeFirst(2) }
                return (line, s.lowercased())
            }
            let hasTraining = cleanTokens.contains { !($0.1 == "rest day" || $0.1 == "active recovery") && !$0.1.isEmpty }
            var details: [String] = []
            if hasTraining {
                // Keep all non-rest lines, drop rest labels
                for (orig, low) in cleanTokens where !(low == "rest day" || low == "active recovery") {
                    details.append(orig)
                }
            } else {
                // Keep a single rest label (prefer Active Recovery if present)
                if cleanTokens.contains(where: { $0.1 == "active recovery" }) {
                    details = ["Active Recovery"]
                } else if cleanTokens.contains(where: { $0.1 == "rest day" }) {
                    details = ["Rest Day"]
                } else {
                    details = []
                }
            }
            out.append(header)
            out.append(contentsOf: details)
            currentHeader = nil
            currentDetails = []
        }

        func isDayHeader(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "^#{1,3}\\s*Day\\s+\\d+(:|\\s).*$", options: .regularExpression) != nil { return true }
            if trimmed.range(of: "^[-•]\\s*Day\\s+\\d+(:|\\s).*$", options: .regularExpression) != nil { return true }
            if trimmed.range(of: "^Day\\s+\\d+(:|\\s).*$", options: .regularExpression) != nil { return true }
            return false
        }

        for line in lines {
            if isDayHeader(line) {
                flush()
                currentHeader = line
            } else if currentHeader != nil {
                currentDetails.append(line)
            } else {
                out.append(line)
            }
        }
        flush()
        return out.joined(separator: "\n")
    }

    // Compute a distance-weighted average pace (min per unit) from recent runs
    private func computeBaselinePaceMinutes() -> Double? {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<RunningSession>()
        let runs: [RunningSession] = (try? request.modelContext.fetch(descriptor)) ?? []
        let recent = runs.filter { $0.date >= start }
        var totalDuration: TimeInterval = 0
        var totalDistanceUnits: Double = 0
        for r in recent {
            let isMi = r.distanceUnit.lowercased().contains("mi")
            let inKm = isMi ? r.distance * 1.60934 : r.distance
            let wantKm = request.distanceUnit.lowercased().contains("km")
            let dist = wantKm ? inKm : inKm / 1.60934
            if dist > 0, r.duration > 0 { totalDuration += r.duration; totalDistanceUnits += dist }
        }
        guard totalDistanceUnits > 0 else { return nil }
        return (totalDuration / 60.0) / totalDistanceUnits
    }

    // Adjust any run durations that conflict with a reasonable baseline pace
    private func fixRunDurations(in text: String, baselineMinPerUnit: Double?) -> String {
        guard let baseline = baselineMinPerUnit, baseline.isFinite, baseline > 0 else { return text }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var out: [String] = []
        let unit = request.distanceUnit.lowercased().contains("km") ? "km" : "mi"

        func timeString(from totalMinutes: Double) -> String {
            let secs = Int((totalMinutes * 60).rounded())
            let h = secs / 3600
            let m = (secs % 3600) / 60
            let s = secs % 60
            if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
            return String(format: "%d:%02d", m, s)
        }

        func adjust(_ line: String) -> String {
            let lower = line.lowercased()
            guard lower.contains("run:") && (lower.contains(" mi") || lower.contains(" km")) else { return line }

            // Extract distance after "Run:" token
            guard let distRegex = try? NSRegularExpression(pattern: "run:\\s*([0-9]+(?:\\.[0-9]+)?)\\s*(mi|km)", options: [.caseInsensitive]) else { return line }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = distRegex.firstMatch(in: line, range: range), match.numberOfRanges >= 3,
                  let dRange = Range(match.range(at: 1), in: line),
                  let uRange = Range(match.range(at: 2), in: line) else { return line }
            let distVal = Double(line[dRange]) ?? 0
            let unitFound = String(line[uRange]).lowercased()
            guard distVal > 0 else { return line }
            let distanceInUserUnit: Double = unitFound == unit ? distVal : (unitFound == "mi" ? distVal * 1.60934 : distVal / 1.60934)

            // Time patterns
            guard let hmsRegex = try? NSRegularExpression(pattern: "\\b(in|for)\\s+(\\d{1,3}):(\\d{2})(?::(\\d{2}))?", options: [.caseInsensitive]),
                  let minRegex = try? NSRegularExpression(pattern: "\\b(in|for)\\s+(\\d{1,3})\\s*(min|mins|minutes)", options: [.caseInsensitive]) else { return line }

            if let m = hmsRegex.firstMatch(in: line, range: range), m.numberOfRanges >= 4,
               let hRange = Range(m.range(at: 2), in: line), let mRange = Range(m.range(at: 3), in: line) {
                let sRange = m.numberOfRanges >= 5 ? Range(m.range(at: 4), in: line) : nil
                let hours = Int(line[hRange]) ?? 0
                let mins = Int(line[mRange]) ?? 0
                let secs = sRange.flatMap { Int(line[$0]) } ?? 0
                let totalMin = Double(hours * 60 + mins) + Double(secs) / 60.0
                let pace = totalMin / max(distanceInUserUnit, 0.0001)
                if abs(pace - baseline) > 3.0 { // clamp outliers
                    let correctedMin = baseline * distanceInUserUnit
                    let newTime = timeString(from: correctedMin)
                    let replRange = Range(m.range, in: line)!
                    return line.replacingCharacters(in: replRange, with: "in \(newTime)")
                }
                return line
            } else if let m = minRegex.firstMatch(in: line, range: range), m.numberOfRanges >= 3,
                      let mmRange = Range(m.range(at: 2), in: line) {
                let minsOnly = Double(line[mmRange]) ?? 0
                let pace = minsOnly / max(distanceInUserUnit, 0.0001)
                if abs(pace - baseline) > 3.0 {
                    let correctedMin = baseline * distanceInUserUnit
                    let newTime = timeString(from: correctedMin)
                    let replRange = Range(m.range, in: line)!
                    return line.replacingCharacters(in: replRange, with: "in \(newTime)")
                }
                return line
            }
            return line
        }

        for l in lines { out.append(adjust(l)) }
        return out.joined(separator: "\n")
    }

    private func save() {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Generate a meaningful title/prompt
        let promptText: String
        if mode == .plan {
            // For workout plans, create a descriptive title
            if !request.extraContext.isEmpty {
                promptText = "Weekly Plan: \(request.extraContext)"
            } else {
                let goalText = request.goal.capitalized
                promptText = "Weekly Training Plan (\(goalText) Goal)"
            }
        } else {
            // For ask mode, use the actual question
            promptText = request.extraContext.isEmpty ? "General Question" : request.extraContext
        }
        
        let id = conversationID
        let descriptor = FetchDescriptor<AIConversation>(
            predicate: #Predicate { $0.id == id }
        )
        let convo: AIConversation
        if let existing = try? modelContext.fetch(descriptor).first {
            convo = existing
            convo.date = Date()
            convo.mode = mode.rawValue
            convo.goal = request.goal
            convo.prompt = promptText
            convo.response = content
            convo.model = WorkoutPlanGenerator.shared.persistenceModelIdentifier()
            convo.structuredPlanJSON = structuredPlanJSON
        } else {
            convo = AIConversation(
                id: conversationID,
                mode: mode.rawValue,
                goal: request.goal,
                prompt: promptText,
                response: content,
                model: WorkoutPlanGenerator.shared.persistenceModelIdentifier(),
                structuredPlanJSON: structuredPlanJSON
            )
            modelContext.insert(convo)
        }
        do { try modelContext.save(); showSaved = true } catch { errorText = error.localizedDescription }
    }
    
    private func scheduleToCalendar() {
        Task {
            // Save first if not already saved
            if !content.isEmpty {
                // Create a temporary conversation object to schedule
                let promptText: String
                if !request.extraContext.isEmpty {
                    promptText = "Weekly Plan: \(request.extraContext)"
                } else {
                    let goalText = request.goal.capitalized
                    promptText = "Weekly Training Plan (\(goalText) Goal)"
                }
                
                let tempConvo = AIConversation(
                    id: conversationID,
                    mode: mode.rawValue,
                    goal: request.goal,
                    prompt: promptText,
                    response: content,
                    model: WorkoutPlanGenerator.shared.persistenceModelIdentifier(),
                    structuredPlanJSON: structuredPlanJSON
                )
                
                do {
                    let hour = Calendar.current.component(.hour, from: scheduleStartTime)
                    let minute = Calendar.current.component(.minute, from: scheduleStartTime)
                    try await WorkoutCalendarService.shared.scheduleWorkoutPlan(
                        tempConvo,
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
    
    private func saveAsTemplates() {
        // Create a temporary conversation object to parse
        let promptText: String
        if !request.extraContext.isEmpty {
            promptText = "Weekly Plan: \(request.extraContext)"
        } else {
            let goalText = request.goal.capitalized
            promptText = "Weekly Training Plan (\(goalText) Goal)"
        }
        
        let tempConvo = AIConversation(
            id: conversationID,
            mode: mode.rawValue,
            goal: request.goal,
            prompt: promptText,
            response: content,
            model: WorkoutPlanGenerator.shared.persistenceModelIdentifier(),
            structuredPlanJSON: structuredPlanJSON
        )
        
        // Create templates from the plan (structured JSON preferred; includes rest/recovery days)
        let templates = WorkoutTemplateService.shared.createTemplatesFromPlan(
            conversation: tempConvo,
            context: modelContext
        )

        let trainingPlan = TrainingPlanService.shared.createOrUpdateAIPlan(
            conversation: tempConvo,
            templates: templates,
            context: modelContext,
            activate: true
        )
        
        createdTemplatesCount = templates.count
        if createdTemplatesCount > 0, trainingPlan != nil {
            showTemplateSuccess = true
            Haptics.notify(.success)
        } else {
            // No templates created (might be all rest days or parsing failed)
            calendarError = "Coach couldn’t turn this response into an executable plan. Try generating a new plan with specific training days."
            Haptics.notify(.warning)
        }
    }
    
    private var isPinnedToBottom: Bool {
        // Consider pinned if content fits or within ~12pt of bottom
        if contentHeight <= scrollViewHeight + 1 { return true }
        let scrolledDistance = abs(scrollOffset)
        let maxScrollDistance = max(0, contentHeight - scrollViewHeight)
        let distanceFromBottom = maxScrollDistance - scrolledDistance
        return distanceFromBottom < 12
    }
}

// MARK: - Bottom Action Bar
private extension AIConversationSheet {
    @ViewBuilder var bottomActionBar: some View {
        if !content.isEmpty {
            VStack(spacing: 0) {
                Divider()
                    .opacity(0.15)

                HStack(spacing: 12) {
                    if mode == .plan && !isStreaming {
                        Button { saveAsTemplates() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.fill")
                                Text("Activate Plan")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(AppTheme.accentColor))
                        }

                        Button { showScheduleOptions = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.plus")
                                Text("Schedule")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(AppTheme.textColor.opacity(0.10)))
                        }
                    }

                    Spacer()

                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.textColor)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AppTheme.textColor.opacity(0.10)))
                    }
                    .accessibilityLabel("Share plan")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            )
        }
    }
}

// MARK: - Scroll Offset Preference Key for Conversation
struct ConversationScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private func parseCitations(from content: String) -> [AIConversationSheet.Citation] {
    // Web search disabled: do not resolve citations to sources
    return []
}

private func extractCitationsFromContent(_ content: String) -> [AIConversationSheet.Citation] {
    return parseCitations(from: content)
}

// MARK: - Citation Tile
struct CitationTile: View {
    let citation: AIConversationSheet.Citation
    
    var body: some View {
        Link(destination: URL(string: citation.url) ?? URL(string: "https://duckduckgo.com")!) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(sourceColor.gradient)
                            .frame(width: 32, height: 32)
                        
                        Text("\(citation.number)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        // Infer source from URL if not available
                        Text(inferredSource)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(sourceColor)
                            .textCase(.uppercase)
                        
                        Text(citation.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer(minLength: 0)
                    
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(sourceColor.opacity(0.7))
                }
                
                Text(citation.snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(width: 290)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [sourceColor.opacity(0.08), sourceColor.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(sourceColor.opacity(0.25), lineWidth: 1.5)
                }
            )
            .shadow(color: sourceColor.opacity(0.15), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
    
    private var inferredSource: String {
        let url = citation.url.lowercased()
        if url.contains("reddit.com") || url.contains("redd.it") {
            return "Reddit"
        } else if url.contains("wikipedia.org") {
            return "Wikipedia"
        } else if url.contains("duckduckgo.com") || url.contains("ddg.") {
            return "DuckDuckGo"
        } else {
            return "Web Source"
        }
    }
    
    private var sourceColor: Color {
        let source = inferredSource.lowercased()
        switch source {
        case "reddit": return .orange
        case "wikipedia": return .purple
        case "duckduckgo": return .blue
        default: return .gray
        }
    }
}

#Preview {
    AIConversationSheet(mode: .plan, request: WorkoutPlanRequest(goal: "maintain", extraContext: "", weightUnit: "lbs", distanceUnit: "mi", modelContext: PersistenceController.preview.container.mainContext))
        .modelContainer(PersistenceController.preview.container)
}
