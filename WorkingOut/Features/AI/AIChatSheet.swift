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
    // Web search removed to reduce tokens and latency
    // Web search removed
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
                // Web search disabled – no source auto-scroll
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
            
            // Center placeholder removed (web search disabled)
            
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
    }

    // With @AppStorage, state syncs to UserDefaults automatically across views.
    // No manual syncing needed to avoid feedback loops.
    private func updateWebSearchState() { }

    // Web search disabled; no toggle or detection needed

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
                    withAnimation(.easeInOut(duration: 2.0)) {
                        streamingOpacity = 1.0
                    }
                }

                // Web search disabled: no searching indicator
                
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

                    // Web search/tool indicators removed

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
                    }
                    
                    // Small delay then retry
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    send() // Retry with fresh context
                    return
                } else {
                    // Other errors - show to user
                    await MainActor.run { errorText = error.localizedDescription }
                }
            }
            await MainActor.run {
                isStreaming = false
                lastStreamedAssistantID = nil
                streamingOpacity = 1.0
                streamTask = nil
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

    // Search results UI removed

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
// Search source cards and shimmering dots removed
