import SwiftUI
import SwiftData
import Combine

struct AIChatSheet: View {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
    }

    struct QuickAskPrompt: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let userMessage: String
        let prompt: String
    }

    let requestBase: WorkoutPlanRequest

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Message] = []
    @State private var isStreaming: Bool = false
    @State private var errorText: String? = nil
    @State private var showSaved: Bool = false

    @State private var streamingOpacity: Double = 0.5
    @State private var lastStreamedAssistantID: UUID? = nil
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var waitingForFirstChunk: Bool = false
    @State private var showClearConfirmation: Bool = false
    @State private var displayedText: String = ""
    @State private var fullBufferedText: String = ""
    // Web search removed to reduce tokens and latency
    // Web search removed
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var autoFollow: Bool = true
    @State private var userIsDragging: Bool = false
    @State private var floatingPromptAnimation: Bool = false

    private let quickPrompts: [QuickAskPrompt] = [
        QuickAskPrompt(
            id: "strength-block",
            icon: "dumbbell.fill",
            title: "Strength Focus Plan",
            subtitle: "Get stronger with clear progressions",
            userMessage: "Build me a strength-focused training plan.",
            prompt: """
            Build a practical 4-week strength-focused plan.
            Return exactly these sections:
            1) Weekly split
            2) Main lifts with sets/reps/intensity targets
            3) Accessory work
            4) Progression and deload rules
            Keep it realistic for a busy adult.
            """
        ),
        QuickAskPrompt(
            id: "endurance-build",
            icon: "figure.run.circle",
            title: "Endurance Build",
            subtitle: "Improve aerobic base and long-run stamina",
            userMessage: "Create an endurance-focused progression.",
            prompt: """
            Create a 6-week endurance progression focused on sustainable mileage.
            Return exactly:
            1) Weekly mileage targets
            2) Session types (easy/tempo/long/recovery)
            3) Intensity guidance using RPE
            4) Signs to back off and recover
            """
        ),
        QuickAskPrompt(
            id: "hybrid-strength-cardio",
            icon: "flame.fill",
            title: "Hybrid Training Week",
            subtitle: "Balance strength and cardio together",
            userMessage: "Give me a balanced strength + cardio week.",
            prompt: """
            Design a balanced weekly routine that combines strength and cardio without overtraining.
            Return exactly:
            1) Day-by-day schedule
            2) Strength days (lift focus + volume)
            3) Cardio days (duration/intensity)
            4) Recovery day placement and rationale
            """
        ),
        QuickAskPrompt(
            id: "health-recovery-audit",
            icon: "heart.text.square.fill",
            title: "Recovery & Health Audit",
            subtitle: "Sleep, stress, soreness, and readiness",
            userMessage: "Audit my recovery and health habits for training.",
            prompt: """
            Review recovery quality for someone training 4-6 days per week.
            Return exactly:
            1) Daily recovery checklist
            2) Red flags for overreaching
            3) Sleep/hydration/protein targets
            4) What to adjust first when fatigue rises
            """
        ),
        QuickAskPrompt(
            id: "muscle-gain-nutrition",
            icon: "fork.knife.circle.fill",
            title: "Muscle Gain Nutrition",
            subtitle: "Fuel strength and recovery better",
            userMessage: "Create nutrition guidelines to gain muscle.",
            prompt: """
            Create a simple muscle-gain nutrition framework for training performance.
            Return exactly:
            1) Calorie and protein strategy
            2) Meal timing around workouts
            3) Easy high-protein meal ideas
            4) Weekly check-in adjustments
            """
        ),
        QuickAskPrompt(
            id: "running-speed-endurance",
            icon: "figure.run",
            title: "Run Faster + Longer",
            subtitle: "Build pace and endurance safely",
            userMessage: "Help me improve both running speed and endurance.",
            prompt: """
            Build a running progression that improves speed and endurance at the same time.
            Return exactly:
            1) Key weekly workouts
            2) Pacing guidance by workout type
            3) Warm-up/cool-down protocol
            4) Injury-risk safeguards
            """
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty && !isStreaming {
                            Text("Pick a guided prompt to generate focused coaching for strength, endurance, and overall fitness.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryTextColor)
                                .padding(.bottom, 8)
                            floatingPromptRows
                        }

                        ForEach(messages) { msg in
                            messageRow(msg)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                                .id(msg.id)
                        }
                        if isStreaming && messages.last?.id != lastStreamedAssistantID {
                            typingRow().id("progress")
                        }
                        
                        // Web search results disabled
                    }
                    .padding()
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
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
                    .overlay {
                        // Top fade overlay to improve legibility against navigation chrome.
                        VStack(spacing: 0) {
                            // Top fade - only visible when scrolled down from top
                            if shouldShowTopFade {
                                LinearGradient(
                                    stops: [
                                        .init(color: AppTheme.backgroundColor.opacity(0.95), location: 0.0),
                                        .init(color: AppTheme.backgroundColor.opacity(0.75), location: 0.30),
                                        .init(color: .clear, location: 0.70)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 120)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                            }
                            
                            Spacer()
                        }
                        .animation(.easeInOut(duration: 0.2), value: shouldShowTopFade)
                    }
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
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    // While streaming, follow only when pinned and not actively dragging
                    if isStreaming { autoFollow = isPinnedToBottom && !userIsDragging }
                }
                .contentShape(Rectangle())
                .onTapGesture { dismissKeyboard() }
                .onChange(of: messages.count) { _, _ in
                    // Only auto-scroll when new messages are added, not during streaming
                    if !isStreaming {
                        withAnimation(.snappy) { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    }
                }
                .onChange(of: displayedText) { _, _ in
                    // While streaming, follow new content until user scrolls up
                    if isStreaming && autoFollow {
                        withAnimation(.linear(duration: 0.12)) { proxy.scrollTo("progress", anchor: .bottom) }
                    }
                }
                .onChange(of: isStreaming) { wasStreaming, nowStreaming in
                    // When streaming ends, do one final scroll without animation to settle
                    if wasStreaming && !nowStreaming {
                        autoFollow = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
                // Web search disabled – no source auto-scroll
            }
        }
        .safeAreaInset(edge: .bottom) {
            if shouldShowBottomPromptBar {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Training Prompt Packs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Spacer()
                        if waitingForFirstChunk {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.secondaryTextColor))
                                    .scaleEffect(0.75)
                                Text("Generating…")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.secondaryTextColor)
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(quickPrompts) { template in
                                promptCard(template)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .background(
                    VStack(spacing: 0) {
                        Divider()
                        Rectangle()
                            .fill(.ultraThinMaterial)
                    }
                    .ignoresSafeArea()
                )
            }
        }
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 14) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")

                    Button(role: .destructive) { clearHistory() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Clear")
                        .disabled(messages.isEmpty)
                }
            }
            
            // Center placeholder removed (web search disabled)
            
            // Right side - Save button
            ToolbarItem(placement: .topBarTrailing) {
                Button { save() } label: { Image(systemName: "tray.and.arrow.down") }
                    .accessibilityLabel("Save")
                    .disabled(messages.isEmpty)
            }
        }
        .appBackground(AppTheme.gradientRuns)
        .foregroundColor(AppTheme.textColor)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    dismissKeyboard()
                    if isStreaming {
                        userIsDragging = true
                        autoFollow = false
                    }
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        userIsDragging = false
                        if isStreaming { autoFollow = isPinnedToBottom }
                    }
                }
        )
        .alert("Error", isPresented: .constant(errorText != nil)) { Button("OK", role: .cancel) { errorText = nil } } message: { Text(errorText ?? "") }
        .alert("Saved", isPresented: $showSaved) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Conversation saved")
        }
        .confirmationDialog("Clear Chat History?", isPresented: $showClearConfirmation) {
            Button("Clear All Messages", role: .destructive) {
                performClear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear the current conversation and start fresh. The AI will lose all context from this session.")
        }
        .task {
            floatingPromptAnimation = true
            await prewarm()
        }
        .onDisappear {
            // Cancel any ongoing streaming when the view disappears
            streamTask?.cancel()
            streamTask = nil
            isStreaming = false
            waitingForFirstChunk = false
        }
    }

    private func prewarm() async {
        await WorkoutPlanGenerator.shared.prewarmIfPossible()
    }

    // With @AppStorage, state syncs to UserDefaults automatically across views.
    // No manual syncing needed to avoid feedback loops.
    private func updateWebSearchState() { }

    // Web search disabled; no toggle or detection needed

    private func send(template: QuickAskPrompt) {
        send(
            question: template.prompt,
            userMessage: template.userMessage,
            appendUserMessage: true
        )
    }

    private func send(question: String, userMessage: String, appendUserMessage: Bool) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming else { return }

        Haptics.playImpact(.light)

        if appendUserMessage {
            withAnimation(.snappy) {
                messages.append(.init(role: .user, text: userMessage))
            }
        }
        isStreaming = true
        waitingForFirstChunk = true
        autoFollow = true
        let req = WorkoutPlanRequest(
            goal: requestBase.goal,
            extraContext: question,
            weightUnit: requestBase.weightUnit,
            distanceUnit: requestBase.distanceUnit,
            modelContext: modelContext,
            mode: .ask
        )
        streamTask?.cancel()
        streamTask = Task {
            do {
                var isFirstChunk = true
                
                // Start clear and gradually become visible
                await MainActor.run {
                    streamingOpacity = 0.2
                    displayedText = ""
                    fullBufferedText = ""
                    let placeholder = Message(role: .assistant, text: "Generating…")
                    withAnimation(.snappy) { messages.append(placeholder) }
                    lastStreamedAssistantID = placeholder.id
                    withAnimation(.easeInOut(duration: 0.25)) {
                        streamingOpacity = 1.0
                    }
                }

                // Web search disabled: no searching indicator

                for try await chunk in WorkoutPlanGenerator.shared.generateAskStream(request: req, history: messages.map { ($0.role == .user ? "User" : "Assistant", $0.text) }) {
                    // Check for cancellation
                    if Task.isCancelled { break }

                    // Web search/tool indicators removed

                    await MainActor.run {
                        if isFirstChunk {
                            waitingForFirstChunk = false
                            fullBufferedText = chunk
                            displayedText = fullBufferedText
                            if let streamingID = lastStreamedAssistantID,
                               let idx = messages.lastIndex(where: { $0.id == streamingID }) {
                                messages[idx].text = displayedText
                            }
                            isFirstChunk = false
                        } else {
                            fullBufferedText += chunk
                            displayedText = fullBufferedText
                            if let streamingID = lastStreamedAssistantID,
                               let idx = messages.lastIndex(where: { $0.id == streamingID }) {
                                messages[idx].text = displayedText
                            }
                        }
                    }
                }

                // Ensure final text is fully displayed
                await MainActor.run {
                    if let streamingID = lastStreamedAssistantID,
                       let idx = messages.lastIndex(where: { $0.id == streamingID }) {
                        displayedText = fullBufferedText
                        messages[idx].text = fullBufferedText.isEmpty ? "No response generated. Please try again." : fullBufferedText
                    }
                }
            } catch is CancellationError {
                // Silently handle cancellation
                await MainActor.run { }
            } catch {
                // Check if this is a context overflow error
                let errorMessage = error.localizedDescription.lowercased()
                let isContextOverflow = errorMessage.contains("context") && 
                                       (errorMessage.contains("length") || 
                                        errorMessage.contains("limit") || 
                                        errorMessage.contains("overflow") ||
                                        errorMessage.contains("too long") ||
                                        errorMessage.contains("maximum"))
                
                if isContextOverflow {
                    // Auto-reset with conversation summary
                    print("🔄 Context overflow detected - auto-resetting with summary")
                    
                    // Summarize recent conversation
                    let summary = await WorkoutPlanGenerator.summarizeConversation(
                        messages.map { ($0.role == .user ? "User" : "Assistant", $0.text) }
                    )
                    
                    await MainActor.run {
                        // Add system message about reset
                        let resetMessage = Message(
                            role: .assistant, 
                            text: "💡 **Context refreshed**: The conversation was getting long, so I've refreshed my memory to keep responses fast and accurate. I still remember the key points from our discussion and we can continue seamlessly!"
                        )
                        withAnimation(.snappy) {
                            messages.append(resetMessage)
                        }
                        
                        // Store summary for next request
                        WorkoutPlanGenerator.lastConversationSummary = summary
                        
                        Haptics.notify(.success)
                    }
                    
                    // Reset the model context
                    Task { @MainActor in
                        WorkoutPlanGenerator.shared.resetModelContext()
                    }
                    
                    // Retry the question automatically
                    await MainActor.run {
                        isStreaming = false
                        waitingForFirstChunk = false
                    }
                    
                    // Small delay then retry
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    await MainActor.run {
                        send(
                            question: question,
                            userMessage: userMessage,
                            appendUserMessage: false
                        )
                    }
                    return
                } else {
                    // Other errors - show to user
                    await MainActor.run {
                        errorText = error.localizedDescription
                        if let streamingID = lastStreamedAssistantID,
                           let idx = messages.lastIndex(where: { $0.id == streamingID }) {
                            messages[idx].text = "Unable to generate response. Please try again."
                        }
                    }
                }
            }
            await MainActor.run {
                isStreaming = false
                waitingForFirstChunk = false
                lastStreamedAssistantID = nil
                streamingOpacity = 1.0
                streamTask = nil
                autoFollow = false
            }
        }
    }


    private func save() {
        let full = messages.map { ($0.role == .user ? "You: " : "AI: ") + $0.text }.joined(separator: "\n\n")
        let convo = AIConversation(
            mode: "ask",
            goal: requestBase.goal,
            prompt: messages.first?.text ?? "",
            response: full,
            model: WorkoutPlanGenerator.shared.persistenceModelIdentifier()
        )
        modelContext.insert(convo)
        if PersistenceSave.commit(modelContext, action: "save changes") {
            showSaved = true
            Haptics.notify(.success)
        } else {
            errorText = "Couldn’t save your conversation. Please try again."
        }
    }
    
    private func clearHistory() {
        showClearConfirmation = true
    }
    
    private func performClear() {
        // Cancel any ongoing streaming
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        waitingForFirstChunk = false
        
        // Clear all state
        withAnimation(.snappy) {
            messages.removeAll()
        }
        displayedText = ""
        fullBufferedText = ""
        streamingOpacity = 0.5
        lastStreamedAssistantID = nil
        
        // Clear conversation summary
        WorkoutPlanGenerator.lastConversationSummary = nil
        
        // Reset model context
        Task { @MainActor in
            WorkoutPlanGenerator.shared.resetModelContext()
        }
    }

    // Search results UI removed

    private var shouldShowBottomPromptBar: Bool {
        messages.contains(where: { $0.role == .user })
    }

    @ViewBuilder
    private var floatingPromptRows: some View {
        VStack(spacing: 14) {
            floatingPromptRow(
                prompts: [quickPrompts[0], quickPrompts[3], quickPrompts[1]],
                xShift: floatingPromptAnimation ? -10 : 10
            )
            floatingPromptRow(
                prompts: [quickPrompts[2], quickPrompts[5], quickPrompts[4]],
                xShift: floatingPromptAnimation ? 8 : -8
            )
            floatingPromptRow(
                prompts: [quickPrompts[1], quickPrompts[4], quickPrompts[0]],
                xShift: floatingPromptAnimation ? -6 : 6
            )
            .padding(.bottom, 8)
        }
        .onAppear {
            floatingPromptAnimation = true
        }
    }

    @ViewBuilder
    private func floatingPromptRow(prompts: [QuickAskPrompt], xShift: CGFloat) -> some View {
        HStack(spacing: 10) {
            ForEach(prompts) { template in
                floatingQuestionChip(template)
            }
        }
        .padding(.horizontal, 8)
        .offset(x: xShift)
        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: floatingPromptAnimation)
    }

    @ViewBuilder
    private func floatingQuestionChip(_ template: QuickAskPrompt) -> some View {
        Button {
            send(template: template)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: template.icon)
                    .font(.caption.weight(.semibold))
                Text(template.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppTheme.secondaryBackgroundColor.opacity(0.92))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(AppTheme.textColor.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isStreaming)
        .opacity(isStreaming ? 0.65 : 1.0)
    }

    @ViewBuilder
    private func promptCard(_ template: QuickAskPrompt) -> some View {
        Button {
            send(template: template)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: template.icon)
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(AppTheme.accentColor.opacity(0.14))
                        .clipShape(Circle())
                    Text(template.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(template.subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryTextColor)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("Tap to ask")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accentColor)
            }
            .frame(width: 208, height: 120, alignment: .topLeading)
            .padding(12)
            .background(AppTheme.secondaryBackgroundColor.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.textColor.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isStreaming)
        .opacity(isStreaming ? 0.65 : 1.0)
    }

    @ViewBuilder
    private func messageRow(_ msg: Message) -> some View {
        HStack(alignment: .bottom) {
            if msg.role == .assistant {
                bubbleView(text: msg.text, isAssistant: true)
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubbleView(text: msg.text, isAssistant: false)
            }
        }
    }

    @ViewBuilder
    private func bubbleView(text: String, isAssistant: Bool) -> some View {
        let isCurrentlyStreaming = isAssistant && isStreaming &&
                                    lastStreamedAssistantID != nil &&
                                    messages.last?.id == lastStreamedAssistantID
        let showGeneratingState = isCurrentlyStreaming && waitingForFirstChunk && text == "Generating…"

        let hasVerifiedContent = text.contains("=== VERIFIED") || text.contains("VERIFIED INFORMATION")
        let hasCitations = text.contains("[1]") || text.contains("[2]") || text.contains("source")
        let bubbleFill: Color = isAssistant
            ? AppTheme.secondaryBackgroundColor.opacity(hasVerifiedContent || hasCitations ? 0.96 : 0.90)
            : AppTheme.accentColor.opacity(0.22)

        VStack(alignment: .leading, spacing: 0) {
            if hasVerifiedContent || hasCitations {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Verified")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.green.opacity(0.1))
                .cornerRadius(8)
                .padding(.top, 6)
                .padding(.leading, 6)
            }

            if showGeneratingState {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.textColor))
                        .scaleEffect(0.85)
                    Text("Generating…")
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
                    .strokeBorder(
                        hasVerifiedContent || hasCitations
                            ? Color.green.opacity(0.35)
                            : AppTheme.textColor.opacity(0.12),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .opacity(isCurrentlyStreaming ? streamingOpacity : 1.0)
    }


    @ViewBuilder
    private func typingRow() -> some View {
        HStack {
            bubbleTyping()
            Spacer(minLength: 40)
        }
    }

    private func bubbleTyping() -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppTheme.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(0.7)
                    .scaleEffect(animationPhase(i))
                    .animation(.easeInOut(duration: 0.8).repeatForever().delay(Double(i) * 0.2), value: isStreaming)
            }
        }
        .padding(10)
        .background(AppTheme.secondaryBackgroundColor.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func animationPhase(_ index: Int) -> CGFloat {
        return isStreaming ? 1.0 : 0.8
    }
    
    // Computed properties for fade visibility based on scroll position
    private var shouldShowTopFade: Bool {
        // Only show if we have content and are scrolled away from the top
        // scrollOffset is positive when at top, negative when scrolled down
        guard !messages.isEmpty else { return false }
        return scrollOffset < -10
    }
    
    private var isPinnedToBottom: Bool {
        if contentHeight <= scrollViewHeight + 1 { return true }
        let scrolledDistance = abs(scrollOffset)
        let maxScrollDistance = max(0, contentHeight - scrollViewHeight)
        let distanceFromBottom = maxScrollDistance - scrolledDistance
        return distanceFromBottom < 12
    }
}

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Clickable Source Card
// Search source cards and shimmering dots removed
