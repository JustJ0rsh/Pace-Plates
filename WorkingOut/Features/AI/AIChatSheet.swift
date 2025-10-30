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

    let requestBase: WorkoutPlanRequest

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [Message] = []
    @State private var input: String = ""
    @State private var isStreaming: Bool = false
    @State private var errorText: String? = nil
    @State private var showSaved: Bool = false
    @FocusState private var inputFocused: Bool

    @State private var streamingOpacity: Double = 0.5
    @State private var lastStreamedAssistantID: UUID? = nil
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var showClearConfirmation: Bool = false
    @State private var displayedText: String = ""
    @State private var fullBufferedText: String = ""
    @State private var isUsingTools: Bool = false
    @AppStorage("allowAIWebSearch") private var webSearchEnabled: Bool = false
    @State private var currentSearchResults: [WebSearchResult] = []
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollViewHeight: CGFloat = 0
    @State private var autoFollow: Bool = true
    @State private var userIsDragging: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { msg in
                            messageRow(msg)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                                .id(msg.id)
                        }
                        if isStreaming { typingRow().id("progress") }
                        
                        // Show search results if available
                        if !currentSearchResults.isEmpty {
                            searchResultsPanel
                                .id("sources")
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                        }
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
                        // Material fade overlays - positioned inside the scroll view
                        VStack(spacing: 0) {
                            // Top fade - only visible when scrolled down from top
                            if shouldShowTopFade {
                                ZStack {
                                    // Background gradient fade for seamless blending
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color(red: 0.09, green: 0.04, blue: 0.18), location: 0.0),
                                            .init(color: Color(red: 0.09, green: 0.04, blue: 0.18).opacity(0.9), location: 0.05),
                                            .init(color: Color(red: 0.09, green: 0.04, blue: 0.18).opacity(0.7), location: 0.15),
                                            .init(color: Color(red: 0.09, green: 0.04, blue: 0.18).opacity(0.4), location: 0.35),
                                            .init(color: Color(red: 0.09, green: 0.04, blue: 0.18).opacity(0.15), location: 0.5),
                                            .init(color: .clear, location: 0.65)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    
                                    // Subtle material overlay for depth
                                    Rectangle()
                                        .fill(.regularMaterial)
                                        .opacity(0.3)
                                        .mask(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: .black, location: 0.0),
                                                    .init(color: .black.opacity(0.5), location: 0.3),
                                                    .init(color: .clear, location: 0.65)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                                .frame(height: 120)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                            }
                            
                            Spacer()
                            
                            // Bottom fade - only visible when not at bottom
                            if shouldShowBottomFade {
                                ZStack {
                                    // Background gradient fade for seamless blending
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0.35),
                                            .init(color: Color(red: 0.01, green: 0.08, blue: 0.20).opacity(0.15), location: 0.5),
                                            .init(color: Color(red: 0.01, green: 0.08, blue: 0.20).opacity(0.4), location: 0.65),
                                            .init(color: Color(red: 0.01, green: 0.08, blue: 0.20).opacity(0.7), location: 0.85),
                                            .init(color: Color(red: 0.01, green: 0.08, blue: 0.20).opacity(0.9), location: 0.95),
                                            .init(color: Color(red: 0.01, green: 0.08, blue: 0.20), location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    
                                    // Subtle material overlay for depth
                                    Rectangle()
                                        .fill(.regularMaterial)
                                        .opacity(0.3)
                                        .mask(
                                            LinearGradient(
                                                stops: [
                                                    .init(color: .clear, location: 0.35),
                                                    .init(color: .black.opacity(0.5), location: 0.7),
                                                    .init(color: .black, location: 1.0)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                                .frame(height: 120)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: shouldShowTopFade)
                        .animation(.easeInOut(duration: 0.2), value: shouldShowBottomFade)
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
                .onTapGesture { inputFocused = false; dismissKeyboard() }
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
                .onChange(of: currentSearchResults) { _, _ in
                    // Scroll to show sources when they appear
                    if !currentSearchResults.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation { proxy.scrollTo("sources", anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                HStack {
                    TextField("Ask about nutrition, training, recovery…", text: $input, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($inputFocused)
                        .onSubmit(send)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            ZStack {
                                Circle()
                                    .fill(AppTheme.accentColor)
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.2),
                                                Color.clear
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        )
                        .shadow(color: AppTheme.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming)
                .opacity((input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming) ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Left side - Clear button
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .destructive) { clearHistory() } label: { Label("Clear", systemImage: "trash") }
                    .disabled(messages.isEmpty)
            }
            
            // Center - Web search status and toggle
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if isUsingTools {
                        HStack(spacing: 4) {
                            ShimmeringDotsView()
                            Text("Searching...")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.orange.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.orange.opacity(0.3), lineWidth: 1)
                                )
                        )
                        .shadow(color: .orange.opacity(0.2), radius: 4, x: 0, y: 2)
                    }

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            toggleWebSearch()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: webSearchEnabled ? "network" : "network.slash")
                                .font(.system(size: 12))
                                .foregroundStyle(webSearchEnabled ? .blue : .gray)
                                .scaleEffect(webSearchEnabled ? 1.1 : 1.0)
                            Text("Web")
                                .font(.system(size: 12, weight: webSearchEnabled ? .semibold : .medium))
                                .foregroundStyle(webSearchEnabled ? .blue : .gray)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(webSearchEnabled ? .blue.opacity(0.15) : .gray.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(webSearchEnabled ? .blue.opacity(0.4) : .gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: webSearchEnabled ? .blue.opacity(0.2) : .clear, radius: 3, x: 0, y: 1)
                        .scaleEffect(webSearchEnabled ? 1.05 : 1.0)
                    }
                    .disabled(isStreaming)
                    .buttonStyle(.plain)
                }
            }
            
            // Right side - Save button
            ToolbarItem(placement: .topBarTrailing) {
                Button { save() } label: { Label("Save", systemImage: "tray.and.arrow.down") }
                    .disabled(messages.isEmpty)
            }
        }
        .appBackground(AppTheme.gradientAI)
        .foregroundColor(AppTheme.textColor)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    inputFocused = false; dismissKeyboard()
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
        .confirmationDialog("Clear Chat History?", isPresented: $showClearConfirmation) {
            Button("Clear All Messages", role: .destructive) {
                performClear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear the current conversation and start fresh. The AI will lose all context from this session.")
        }
        .task { await prewarm() }
        .onDisappear {
            // Cancel any ongoing streaming when the view disappears
            streamTask?.cancel()
            streamTask = nil
            isStreaming = false
        }
    }

    private func prewarm() async {
        await WorkoutPlanGenerator.shared.prewarmIfPossible()

        // Also prewarm tool session if web search is enabled
        if webSearchEnabled {
            await WorkoutPlanGenerator.shared.prewarmToolSessionIfNeeded()
        }
    }

    // With @AppStorage, state syncs to UserDefaults automatically across views.
    // No manual syncing needed to avoid feedback loops.
    private func updateWebSearchState() { }

    private func toggleWebSearch() {
        webSearchEnabled.toggle()

        if webSearchEnabled {
            Haptics.playImpact(.light)
            // Prewarm in background without blocking the main thread
            Task {
                await WorkoutPlanGenerator.shared.prewarmToolSessionIfNeeded()
            }
        } else {
            Haptics.playImpact(.medium)
        }
    }

    private func shouldTriggerWebSearch(for query: String) -> Bool {
        // Enhanced detection for immediate UI feedback - must match WorkoutPlanGenerator logic
        let lower = query.lowercased()

        // First, exclude personalized/subjective queries
        let personalizedPatterns = [
            "for me", "my workout", "should i", "can i", "what should i do",
            "recommend", "suggest", "advice", "help me", "good workout for me",
            "today", "this week", "my plan", "my training", "my schedule",
            "i feel", "i'm going", "i want", "i need", "my goal",
            "when my", "when i", "if my", "if i", "my thighs", "my legs",
            "my arms", "my back", "i'm sore", "i am sore", "what to do when",
            "what is good to do", "what should i eat", "how do i"
        ]
        
        if personalizedPatterns.contains(where: { lower.contains($0) }) {
            return false
        }

        // Always factual keywords (high confidence - show immediately)
        let alwaysFactualKeywords = ["what is", "who is", "define", "definition", "research shows", "study found", "evidence",
                                   "clinical", "medical", "science", "scientific", "benefits of", "side effects",
                                   "contraindications", "drug", "medication", "supplement facts", "vitamin",
                                   "micronutrient", "macronutrient", " RDA ", "recommended daily",
                                   "current guidelines", "latest research", "recent study", "2024", "2025"]

        // Check for always factual keywords first (immediate trigger)
        if alwaysFactualKeywords.contains(where: { lower.contains($0) }) {
            return true
        }

        // Critical health/nutrition topics
        let criticalHealthKeywords = ["side effects", "contraindications", "allergy", "pregnancy",
                                    "medication", "drug interaction", " RDA ", "daily requirement",
                                    "toxicity", "deficiency", "chronic", "acute", "symptoms"]
        if criticalHealthKeywords.contains(where: { lower.contains($0) }) {
            return true
        }

        // Check for specific factual phrases (not personalized)
        let factualPhrases = ["tell me about", "explain how", "describe the", "what are the effects",
                            "what causes", "what happens when", "is it safe to", "is it healthy to",
                            "how effective is", "does it work", "what's the evidence for"]

        if factualPhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        // Default: don't show searching indicator
        return false
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        
        // Clear input immediately and dismiss keyboard
        input = ""
        inputFocused = false
        Haptics.playImpact(.light)
        
        withAnimation(.snappy) { messages.append(.init(role: .user, text: question)) }
        isStreaming = true
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
                    isUsingTools = false
                    withAnimation(.easeInOut(duration: 2.0)) {
                        streamingOpacity = 1.0
                    }
                }

                // Check if this query should trigger web search (enhanced detection)
                let shouldTriggerTools = webSearchEnabled && shouldTriggerWebSearch(for: req.extraContext)

                if shouldTriggerTools {
                    print("🎯 UI: Detected factual query, will show searching indicator: \(req.extraContext)")
                    await MainActor.run {
                        // Show searching indicator immediately for high-confidence queries
                        let lowerQuery = req.extraContext.lowercased()
                        let immediateKeywords = ["what is", "define", "benefits", "research", "study", "evidence", "side effects", " RDA ",
                                               "clinical", "medical", "contraindications", "how much", "what are", "tell me"]

                        let delay = immediateKeywords.contains(where: { lowerQuery.contains($0) }) ? 0.2 : 0.5

                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            if !isUsingTools {
                                print("🔍 UI: Showing searching indicator with haptic feedback")
                                isUsingTools = true
                                Haptics.playImpact(.soft)
                            }
                        }
                    }
                }
                
                // Start character reveal task
                let revealTask = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 8_000_000) // 8ms between chars for smooth reveal
                        await MainActor.run {
                            guard isStreaming else { return }
                            if displayedText.count < fullBufferedText.count {
                                let nextIndex = fullBufferedText.index(fullBufferedText.startIndex, offsetBy: displayedText.count + 1)
                                displayedText = String(fullBufferedText[..<nextIndex])
                                
                                // Update the message with the revealed text
                                if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
                                    messages[idx].text = displayedText
                                }
                            }
                        }
                    }
                }
                
                for try await chunk in WorkoutPlanGenerator.shared.generateAskStream(request: req, history: messages.map { ($0.role == .user ? "User" : "Assistant", $0.text) }) {
                    // Check for cancellation
                    if Task.isCancelled { break }

                    // Check if this chunk contains tool call indicators or results
                    let lowerChunk = chunk.lowercased()
                    if (lowerChunk.contains("websearch") || lowerChunk.contains("searching") || lowerChunk.contains("verifying") ||
                       lowerChunk.contains("tool") || lowerChunk.contains("research") || lowerChunk.contains("web search") ||
                       lowerChunk.contains("web context") || lowerChunk.contains("verified") || lowerChunk.contains("sources") ||
                       lowerChunk.contains("=== verified") || lowerChunk.contains("web results") || lowerChunk.contains("citations")) &&
                        !lowerChunk.contains("unable to verify") && !lowerChunk.contains("failed") {
                        await MainActor.run {
                            if !isUsingTools {
                                print("🔍 UI: Detected tool usage in response chunk: \(chunk)")
                                Haptics.playImpact(.soft)
                                // Capture search results when tool is used
                                currentSearchResults = WebSearchService.shared.lastSearchResults
                            }
                            isUsingTools = true
                        }
                    } else if lowerChunk.contains("source") || lowerChunk.contains("[1]") || lowerChunk.contains("according to") ||
                             lowerChunk.contains("study") || lowerChunk.contains("evidence") || lowerChunk.contains("research shows") ||
                             lowerChunk.contains("studies show") || lowerChunk.contains("clinical evidence") {
                        // Keep tool indicator on when sources are being cited
                        await MainActor.run {
                            if !isUsingTools {
                                print("🔍 UI: Detected source citation in response chunk: \(chunk)")
                                // Capture search results when citations are detected
                                currentSearchResults = WebSearchService.shared.lastSearchResults
                            }
                            isUsingTools = true
                        }
                    }

                    await MainActor.run {
                        // Only create the assistant message when we have actual content
                        if isFirstChunk {
                            fullBufferedText = chunk
                            let newAssistant = Message(role: .assistant, text: "")
                            withAnimation(.snappy) { messages.append(newAssistant) }
                            lastStreamedAssistantID = newAssistant.id
                            isFirstChunk = false
                        } else {
                            fullBufferedText += chunk
                        }
                    }
                }
                
                // Wait for all characters to be revealed
                while displayedText.count < fullBufferedText.count && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000) // Check every 50ms
                }
                
                revealTask.cancel()
                
                // Ensure final text is fully displayed
                await MainActor.run {
                    if let idx = messages.lastIndex(where: { $0.role == .assistant }) {
                        messages[idx].text = fullBufferedText
                    }
                    // Reset tool usage indicator
                    isUsingTools = false
                }
            } catch is CancellationError {
                // Silently handle cancellation
                await MainActor.run {
                    isUsingTools = false
                }
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
                        isUsingTools = false
                    }
                    
                    // Small delay then retry
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    send() // Retry with fresh context
                    return
                } else {
                    // Other errors - show to user
                    await MainActor.run {
                        errorText = error.localizedDescription
                        isUsingTools = false
                    }
                }
            }
            await MainActor.run {
                isStreaming = false
                lastStreamedAssistantID = nil
                streamingOpacity = 1.0
                streamTask = nil
                isUsingTools = false
                autoFollow = false
            }
        }
    }


    private func save() {
        let full = messages.map { ($0.role == .user ? "You: " : "AI: ") + $0.text }.joined(separator: "\n\n")
        let convo = AIConversation(mode: "ask", goal: requestBase.goal, prompt: messages.first?.text ?? "", response: full, model: "on-device")
        modelContext.insert(convo)
        try? modelContext.save()
    }
    
    private func clearHistory() {
        showClearConfirmation = true
    }
    
    private func performClear() {
        // Cancel any ongoing streaming
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        
        // Clear all state
        withAnimation(.snappy) {
            messages.removeAll()
        }
        displayedText = ""
        fullBufferedText = ""
        streamingOpacity = 0.5
        lastStreamedAssistantID = nil
        input = ""
        
        // Clear conversation summary
        WorkoutPlanGenerator.lastConversationSummary = nil
        
        // Reset model context
        Task { @MainActor in
            WorkoutPlanGenerator.shared.resetModelContext()
        }
    }

    @ViewBuilder
    private var searchResultsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
                
                Text("Sources")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { withAnimation { currentSearchResults = [] } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(currentSearchResults.enumerated()), id: \.offset) { index, result in
                        ClickableSourceCard(result: result, index: index + 1)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.08), Color.blue.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
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

        let hasVerifiedContent = text.contains("=== VERIFIED") || text.contains("VERIFIED INFORMATION")
        let hasCitations = text.contains("[1]") || text.contains("[2]") || text.contains("source")

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

            MarkdownView(text: text)
                .padding(14)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: isAssistant ? [
                                hasVerifiedContent || hasCitations ?
                                    AppTheme.secondaryBackgroundColor.opacity(0.5) :
                                    AppTheme.secondaryBackgroundColor.opacity(0.4),
                                hasVerifiedContent || hasCitations ?
                                    AppTheme.secondaryBackgroundColor.opacity(0.3) :
                                    AppTheme.secondaryBackgroundColor.opacity(0.2)
                            ] : [
                                AppTheme.accentColor.opacity(0.3),
                                AppTheme.accentColor.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: hasVerifiedContent || hasCitations ? [
                                Color.green.opacity(0.3),
                                Color.green.opacity(0.1)
                            ] : [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
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
        .background(AppTheme.secondaryBackgroundColor.opacity(0.55))
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
    
    private var shouldShowBottomFade: Bool {
        // Only show if we have content and are not at the bottom
        // Check if content extends beyond viewport
        guard !messages.isEmpty else { return false }
        let isContentScrollable = contentHeight > scrollViewHeight
        if !isContentScrollable { return false }
        
        // Calculate approximate distance from bottom
        let scrolledDistance = abs(scrollOffset)
        let maxScrollDistance = max(0, contentHeight - scrollViewHeight)
        let distanceFromBottom = maxScrollDistance - scrolledDistance
        
        return distanceFromBottom > 10
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
struct ClickableSourceCard: View {
    let result: WebSearchResult
    let index: Int
    
    var body: some View {
        Link(destination: URL(string: result.url) ?? URL(string: "https://duckduckgo.com")!) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    // Citation number badge
                    ZStack {
                        Circle()
                            .fill(sourceColor.gradient)
                            .frame(width: 32, height: 32)
                        
                        Text("\(index)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.source)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(sourceColor)
                            .textCase(.uppercase)
                        
                        Text(result.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer(minLength: 0)
                    
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(sourceColor.opacity(0.7))
                }
                
                Text(result.snippet)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(width: 280)
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
            .shadow(color: sourceColor.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var sourceColor: Color {
        switch result.source.lowercased() {
        case "duckduckgo": return .blue
        case "reddit": return .orange
        case "wikipedia": return .purple
        default: return .gray
        }
    }
}

// MARK: - Shimmering Dots Component
struct ShimmeringDotsView: View {
    @State private var currentDot = 0
    @State private var scale: Double = 1.0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.orange)
                    .frame(width: index == currentDot ? 6 : 4, height: index == currentDot ? 6 : 4)
                    .opacity(index == currentDot ? 1.0 : 0.4)
                    .scaleEffect(scale)
                    .animation(.easeInOut(duration: 0.3), value: currentDot)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: scale)
            }
        }
        .onAppear {
            startAnimation()
            // Add subtle pulsing effect
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                scale = 1.1
            }
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.35)) {
                currentDot = (currentDot + 1) % 3
            }
        }
    }
}
