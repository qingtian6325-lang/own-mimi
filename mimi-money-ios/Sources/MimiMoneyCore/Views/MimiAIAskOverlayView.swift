import SwiftUI

/// 待发送的附件（小窗里先贴上，和文字一次发送）
public struct AIPendingAttachment: Identifiable, Equatable {
    public let id: UUID
    public var imageData: Data?
    public var label: String

    public init(id: UUID = UUID(), imageData: Data? = nil, label: String) {
        self.id = id
        self.imageData = imageData
        self.label = label
    }
}

/// AI 记账浮层：
/// - **首页 / 选图**：先底部小窗 + 三快捷气泡；上滑 /「展开」/ 发送 → 真整页
/// - **手动→AI**：直接进真整页聊天
/// - **整页下滑 /「关闭」** → 退出
public struct MimiAIAskOverlayView: View {
    @ObservedObject public var store: MimiStore
    @ObservedObject public var aiEngine: MimiAIEngine
    public var initialAttachments: [AIPendingAttachment]
    public var startExpanded: Bool
    public var onDismiss: () -> Void
    public var onOpenManual: () -> Void
    public var onOpenImportExport: () -> Void

    @State private var inputText: String = ""
    @State private var pendingAttachments: [AIPendingAttachment] = []
    @State private var isExpanded: Bool = false
    @State private var showAttachmentPanel: Bool = false
    @State private var showAlbumPicker: Bool = false
    @State private var showCameraPicker: Bool = false
    @State private var dragOffset: CGFloat = 0
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let bottomAnchorID = "mimi-ai-overlay-bottom-anchor"
    #if canImport(Speech) && canImport(AVFoundation)
    @StateObject private var speechTranscriber = SpeechTranscriber()
    #endif

    public init(
        store: MimiStore,
        aiEngine: MimiAIEngine,
        initialAttachments: [AIPendingAttachment] = [],
        startExpanded: Bool = false,
        onDismiss: @escaping () -> Void,
        onOpenManual: @escaping () -> Void,
        onOpenImportExport: @escaping () -> Void = {}
    ) {
        self.store = store
        self.aiEngine = aiEngine
        self.initialAttachments = initialAttachments
        self.startExpanded = startExpanded
        self.onDismiss = onDismiss
        self.onOpenManual = onOpenManual
        self.onOpenImportExport = onOpenImportExport
        _pendingAttachments = State(initialValue: initialAttachments)
        _isExpanded = State(initialValue: startExpanded)
    }

    public var body: some View {
        ZStack {
            if isExpanded {
                fullPage
                    .offset(y: max(0, dragOffset))
                    .transition(.opacity)
            } else {
                compactChrome
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(MimiMotion.sheet(reduceMotion: reduceMotion), value: isExpanded)
        .animation(MimiMotion.interactive(reduceMotion: reduceMotion), value: dragOffset)
        .onAppear {
            BookkeepingEntryPreference.rememberAI()
            isExpanded = startExpanded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                inputFocused = true
            }
        }
        .onChange(of: aiEngine.answerJustCompleted) { _, done in
            if done {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    aiEngine.answerJustCompleted = false
                }
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showAlbumPicker) {
            PHPickerImageView { imageData in
                pendingAttachments.append(AIPendingAttachment(imageData: imageData, label: "照片"))
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            UIKitImagePicker(sourceType: .camera) { image in
                if let data = image.jpegData(compressionQuality: 0.85) {
                    pendingAttachments.append(AIPendingAttachment(imageData: data, label: "拍照"))
                }
            }
        }
        #endif
    }

    // MARK: - Compact（底部小窗）

    private var compactChrome: some View {
        ZStack(alignment: .bottom) {
            MimiTheme.scrim
                .ignoresSafeArea()
                .onTapGesture {
                    inputFocused = false
                    onDismiss()
                }
                .accessibilityLabel(MimiL10n.string("关闭问账"))
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 0) {
                suggestionBubbles
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                compactCard
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
            .offset(y: min(0, dragOffset))
        }
    }

    private var compactCard: some View {
        VStack(spacing: 0) {
            expandChromeControl

            headerRow(title: "记账查账，问问题")
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            if !pendingAttachments.isEmpty {
                attachmentBlock
            }

            if showAttachmentPanel {
                AIAttachmentPanelView(
                    onPickFromAlbum: { showAlbumPicker = true },
                    onTakePhoto: { showCameraPicker = true },
                    onOpenImportExport: {
                        showAttachmentPanel = false
                        onOpenImportExport()
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            listeningHint
            inputRow
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MimiTheme.cardBackground)
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 6)
        )
    }

    // MARK: - Full page（真整页）

    private var fullPage: some View {
        VStack(spacing: 0) {
            dismissChromeControl
                .padding(.top, 4)

            headerRow(title: "来记笔账吧")
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider().opacity(0.45)

            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if aiEngine.answerJustCompleted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(MimiTheme.balanceGreen)
                    Text("回答完毕", bundle: .mimiModule)
                        .mimiFont(13, weight: .semibold)
                        .foregroundColor(MimiTheme.balanceGreen)
                }
                .padding(.vertical, 8)
            }

            if !pendingAttachments.isEmpty {
                attachmentBlock
            }

            if showAttachmentPanel {
                AIAttachmentPanelView(
                    onPickFromAlbum: { showAlbumPicker = true },
                    onTakePhoto: { showCameraPicker = true },
                    onOpenImportExport: {
                        showAttachmentPanel = false
                        onOpenImportExport()
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            listeningHint
            inputRow
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MimiTheme.background.ignoresSafeArea())
    }

    // MARK: - Shared pieces

    /// Compact: handle + explicit expand (HIG — swipe must not be the only path).
    private var expandChromeControl: some View {
        VStack(spacing: 2) {
            Capsule()
                .fill(MimiTheme.strokeSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            Button {
                withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                    isExpanded = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .mimiFont(11, weight: .bold)
                    Text("展开", bundle: .mimiModule)
                        .mimiFont(12, weight: .semibold)
                }
                .foregroundColor(MimiTheme.textSecondary)
                .frame(minHeight: MimiHIG.minTouch)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("展开为全屏问账"))
            .accessibilityHint(MimiL10n.string("也可上滑手柄展开"))
        }
        .highPriorityGesture(expandDragGesture)
    }

    /// Full page: handle + explicit close via swipe-down alternative already in header X.
    private var dismissChromeControl: some View {
        VStack(spacing: 2) {
            Capsule()
                .fill(MimiTheme.strokeSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            Button {
                inputFocused = false
                onDismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .mimiFont(11, weight: .bold)
                    Text("关闭", bundle: .mimiModule)
                        .mimiFont(12, weight: .semibold)
                }
                .foregroundColor(MimiTheme.textSecondary)
                .frame(minHeight: MimiHIG.minTouch)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("关闭全屏问账"))
            .accessibilityHint(MimiL10n.string("也可下滑关闭"))
        }
        .highPriorityGesture(expandDragGesture)
    }

    private func headerRow(title: String) -> some View {
        HStack(spacing: 10) {
            MimiAskMascotView(size: 32)
            Text(title)
                .mimiFont(16, weight: .bold)
                .foregroundColor(MimiTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            BookkeepingModeSwitchButton(title: "手动记账") {
                BookkeepingEntryPreference.rememberManual()
                inputFocused = false
                onOpenManual()
            }

            Button {
                inputFocused = false
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .mimiFont(12, weight: .bold)
                    .foregroundColor(MimiTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().strokeBorder(MimiTheme.strokeSubtle, lineWidth: 1))
                    .mimiMinTouchTarget()
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("关闭问账"))
        }
    }

    private var suggestionBubbles: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MimiAIEngine.exampleQuestions, id: \.self) { question in
                Button {
                    inputText = question
                    sendComposed()
                } label: {
                    Text(question)
                        .mimiFont(14)
                        .foregroundColor(MimiTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(MimiTheme.cardBackground)
                                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
                        )
                }
                .mimiPressable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attachmentBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pendingAttachmentSummary)
                .mimiFont(12, weight: .medium)
                .foregroundColor(MimiTheme.textSecondary)
                .padding(.horizontal, 4)
            pendingAttachmentStrip
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var pendingAttachmentSummary: String {
        let labels = pendingAttachments.map(\.label)
        if labels.isEmpty { return "" }
        if labels.count == 1 { return "已选择：\(labels[0])，可继续打字后一起发送" }
        return "已选择 \(labels.count) 项：\(labels.joined(separator: "、"))，可继续打字后一起发送"
    }

    private var pendingAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(pendingAttachments) { item in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            #if canImport(UIKit)
                            if let data = item.imageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                attachmentPlaceholder(item.label)
                            }
                            #else
                            attachmentPlaceholder(item.label)
                            #endif
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Button {
                            pendingAttachments.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .mimiFont(18)
                                .foregroundStyle(.white, Color.black.opacity(0.55))
                        }
                        .offset(x: 6, y: -6)
                        .accessibilityLabel(MimiL10n.string("移除附件"))
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func attachmentPlaceholder(_ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "doc.fill")
                .mimiFont(20)
            Text(label)
                .mimiFont(10, weight: .medium)
        }
        .foregroundColor(MimiTheme.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MimiTheme.fillSubtle)
    }

    @ViewBuilder
    private var listeningHint: some View {
        #if canImport(Speech) && canImport(AVFoundation)
        if speechTranscriber.isRecording {
            Text("正在聆听：\(speechTranscriber.partialText)")
                .mimiFont(12)
                .foregroundColor(MimiTheme.expenseBlue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
        }
        #endif
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(aiEngine.messages) { msg in
                        bubble(msg)
                            .id(msg.id)
                    }
                    if aiEngine.isAnswering {
                        thinkingRow
                            .id("thinking")
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: isExpanded) { _, expanded in
                if expanded { scrollToBottom(proxy, animated: true) }
            }
            .onChange(of: aiEngine.messages) { _, _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: aiEngine.isAnswering) { _, _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: inputFocused) { _, focused in
                if focused { scrollToBottom(proxy, animated: true) }
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            if reduceMotion {
                ProgressView()
                    .controlSize(.small)
                    .tint(MimiTheme.expenseBlue)
            } else {
                TimelineView(.animation(minimumInterval: 0.35, paused: false)) { context in
                    let phase = Int(context.date.timeIntervalSinceReferenceDate * 3) % 3
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(MimiTheme.expenseBlue.opacity(i == phase ? 1 : 0.35))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }
            MimiAskMascotView(size: 22)
            Text("咪咪思考中…", bundle: .mimiModule)
                .mimiFont(14, weight: .medium)
                .foregroundColor(MimiTheme.expenseBlue)
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MimiL10n.string("咪咪思考中"))
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                TextField(
                    isExpanded ? "任何事情都能问我" : "发消息或按住说话...",
                    text: $inputText,
                    axis: .vertical
                )
                .mimiFont(14)
                .lineLimit(1...4)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { sendComposed() }

                #if canImport(Speech) && canImport(AVFoundation)
                if inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Image(systemName: speechTranscriber.isRecording ? "mic.fill" : "mic")
                        .mimiFont(15, weight: .semibold)
                        .foregroundColor(speechTranscriber.isRecording ? MimiTheme.dangerRed : MimiTheme.textMuted)
                        .mimiMinTouchTarget(40)
                        .accessibilityLabel(speechTranscriber.isRecording ? "正在聆听，松开关闭" : "按住说话")
                        .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 60, pressing: { pressing in
                            if pressing {
                                Task {
                                    if await speechTranscriber.requestAuthorization() {
                                        speechTranscriber.startRecording()
                                    }
                                }
                            } else if speechTranscriber.isRecording {
                                let text = speechTranscriber.stopRecording()
                                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                                    inputText = text
                                }
                            }
                        }, perform: {})
                }
                #endif

                Button {
                    withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                        showAttachmentPanel.toggle()
                    }
                } label: {
                    Image(systemName: showAttachmentPanel ? "xmark" : "plus")
                        .mimiFont(15, weight: .bold)
                        .foregroundColor(MimiTheme.textMuted)
                        .mimiMinTouchTarget(40)
                }
                .mimiPressable()
                .accessibilityLabel(showAttachmentPanel ? "收起附件" : "添加照片或导入")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(MimiTheme.fillSubtle))

            Button(action: sendComposed) {
                Image(systemName: "arrow.up")
                    .mimiFont(14, weight: .bold)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend ? MimiTheme.expenseBlue : MimiTheme.controlDisabled))
                    .mimiMinTouchTarget()
            }
            .mimiPressable()
            .disabled(!canSend)
            .accessibilityLabel(MimiL10n.string("发送"))
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
    }

    // MARK: - Bubbles

    @ViewBuilder
    private func bubble(_ message: AIChatMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 36) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                if message.isUser, let images = aiEngine.userMessageImages[message.id], !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, data in
                                #if canImport(UIKit)
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                #endif
                            }
                        }
                    }
                }

                ForEach(Array(message.blocks.enumerated()), id: \.offset) { idx, block in
                    switch block {
                    case .pendingAnswer:
                        EmptyView()

                    case .text(let text):
                        if message.isUser {
                            MimiChatMarkdownText(text, size: 15)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(MimiTheme.tintBlueSoft)
                                )
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                MimiChatMarkdownText(text, size: 15)
                                    .fixedSize(horizontal: false, vertical: true)
                                if idx == message.blocks.count - 1 {
                                    Text("内容由AI生成", bundle: .mimiModule)
                                        .mimiFont(11)
                                        .foregroundColor(MimiTheme.textMuted)
                                }
                            }
                        }

                    case .draftBills(let drafts):
                        draftCard(messageId: message.id, drafts: drafts)

                    case .categoryTable(let expenseRows, let incomeRows, let customNote):
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(expenseRows.enumerated()), id: \.offset) { _, row in
                                Text("\(row.0)：\(row.1)")
                                    .mimiFont(13)
                                    .foregroundColor(MimiTheme.textSecondary)
                            }
                            if !customNote.isEmpty {
                                Text(customNote)
                                    .mimiFont(12)
                                    .foregroundColor(MimiTheme.textMuted)
                            }
                            if !incomeRows.isEmpty {
                                Text("收入分类已包含在上方说明里", bundle: .mimiModule)
                                    .mimiFont(12)
                                    .foregroundColor(MimiTheme.textMuted)
                            }
                        }

                    case .spendingSummary(let title, let amount, let count, let details):
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).mimiFont(15, weight: .bold)
                            Text("总支出 \(MimiTheme.formatRM(amount)) · 共 \(count) 笔")
                                .mimiFont(14, weight: .semibold)
                                .foregroundColor(MimiTheme.expenseBlue)
                            Text(details)
                                .mimiFont(13)
                                .foregroundColor(MimiTheme.textSecondary)
                        }
                    }
                }
            }

            if !message.isUser { Spacer(minLength: 24) }
        }
    }

    private func draftCard(messageId: UUID, drafts: [ParsedDraftBill]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(drafts) { draft in
                HStack(spacing: 10) {
                    MimiStickerIconView(
                        iconName: draft.iconName,
                        categoryName: draft.categoryPath,
                        transactionType: draft.type,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.categoryPath)
                            .mimiFont(14, weight: .semibold)
                        Text("\(draft.accountName) · \(draft.note)")
                            .mimiFont(12)
                            .foregroundColor(MimiTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text((draft.type == .income ? "+" : "-") + MimiTheme.formatRM(draft.amount))
                        .mimiFont(14, weight: .bold, design: .rounded)
                        .foregroundColor(draft.type == .income ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)
                }
            }
            HStack(spacing: 10) {
                Button { aiEngine.cancelDrafts(messageId: messageId) } label: {
                    Text("取消", bundle: .mimiModule)
                        .mimiFont(13, weight: .semibold)
                        .foregroundColor(MimiTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(MimiTheme.fillSubtle))
                }
                .mimiPressable()
                Button { aiEngine.confirmDrafts(messageId: messageId, in: store) } label: {
                    Text("确认记账", bundle: .mimiModule)
                        .mimiFont(13, weight: .semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(MimiTheme.expenseBlue))
                }
                .mimiPressable()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MimiTheme.fillSubtle))
    }

    // MARK: - Gestures / Actions

    private var expandDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if isExpanded {
                    dragOffset = max(0, value.translation.height)
                } else if value.translation.height < -24 {
                    dragOffset = value.translation.height
                } else {
                    dragOffset = 0
                }
            }
            .onEnded { value in
                if !isExpanded && value.translation.height < -80 {
                    withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                        isExpanded = true
                    }
                    dragOffset = 0
                } else if isExpanded && value.translation.height > 120 {
                    dragOffset = 0
                    inputFocused = false
                    onDismiss()
                } else {
                    withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func sendComposed() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingAttachments.compactMap(\.imageData)
        guard !text.isEmpty || !images.isEmpty else { return }

        inputText = ""
        pendingAttachments = []
        showAttachmentPanel = false
        withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
            isExpanded = true
        }
        aiEngine.sendComposed(text: text, imageDataList: images, store: store)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let performScroll = {
            if animated {
                withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
        DispatchQueue.main.async {
            performScroll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            performScroll()
        }
    }
}
