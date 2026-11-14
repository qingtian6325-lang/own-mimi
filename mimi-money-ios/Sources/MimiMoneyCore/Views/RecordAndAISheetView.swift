import SwiftUI

public struct RecordAndAISheetView: View {
    @ObservedObject public var store: MimiStore
    @ObservedObject public var aiEngine: MimiAIEngine
    public var initialAIMode: Bool
    public var onDismiss: () -> Void
    public var onOpenCategorySettings: () -> Void
    public var onEditRecognizedTransaction: (TransactionItem) -> Void
    public var onOpenImportExport: () -> Void = {}
    /// 手动页点「AI 助手」→ 全屏 AI 记账
    public var onSwitchToAIOverlay: () -> Void = {}

    /// Intended tab from the presenting `sheet(item:)` route — re-applied on appear
    /// so a reused sheet never keeps a stale `@State selectedTab` (转账 → 支出 flake).
    private let intendedInitialTab: TransactionType
    /// Fresh per `sheet(item:)` open; drives `.id` / `.task(id:)` so UIPageViewController remounts.
    private let presentationID: UUID

    @State private var isAIMode: Bool
    @State private var selectedTab: TransactionType
    @State private var selectedGroupIndex: Int = 0
    @State private var selectedSubIndex: Int? = 5 // defaults to 零食甜品 or first sub
    @State private var expression: String = ""
    @State private var noteText: String = ""
    @State private var selectedAccountName: String
    @State private var targetAccountName: String = ""
    @State private var includeInStats: Bool = true
    @State private var includeInBudget: Bool = true
    @State private var markPendingReimbursement: Bool = false
    @State private var discountAmountText: String = ""
    @State private var showDiscountInput: Bool = false
    @State private var selectedCurrency: CurrencyCode = .myr
    @State private var aiInputText: String = ""
    @State private var selectedDate: Date = Date()
    @State private var showDatePickerSheet: Bool = false
    @State private var selectedTags: [String] = []
    @State private var attachedReceiptFilenames: [String] = []
    @State private var showImageSourceDialog: Bool = false
    @State private var showImagePickerSheet: Bool = false
    /// While true, sheet interactive dismiss is disabled so horizontal tab paging wins.
    @State private var suppressSheetDismiss: Bool = false
    #if canImport(UIKit)
    @State private var pickerSourceType: UIKitImagePicker.SourceType = .photoLibrary
    #endif
    @State private var activeViewerItem: ReceiptViewerItem? = nil
    @State private var showChatAttachmentPanel: Bool = false
    @State private var showChatAlbumPicker: Bool = false
    @State private var showChatCameraPicker: Bool = false
    @State private var recognitionFailureText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let chatBottomAnchorID = "mimi-record-ai-bottom-anchor"
    #if canImport(Speech) && canImport(AVFoundation)
    @StateObject private var speechTranscriber = SpeechTranscriber()
    #endif

    public init(
        store: MimiStore,
        aiEngine: MimiAIEngine,
        initialAIMode: Bool = false,
        initialTab: TransactionType = .expense,
        presentationID: UUID = UUID(),
        initialAccountName: String? = nil,
        onDismiss: @escaping () -> Void,
        onOpenCategorySettings: @escaping () -> Void,
        onEditRecognizedTransaction: @escaping (TransactionItem) -> Void,
        onOpenImportExport: @escaping () -> Void = {},
        onSwitchToAIOverlay: @escaping () -> Void = {}
    ) {
        self.store = store
        self.aiEngine = aiEngine
        self.initialAIMode = initialAIMode
        self.intendedInitialTab = initialTab
        self.presentationID = presentationID
        self.onDismiss = onDismiss
        self.onOpenCategorySettings = onOpenCategorySettings
        self.onEditRecognizedTransaction = onEditRecognizedTransaction
        self.onOpenImportExport = onOpenImportExport
        self.onSwitchToAIOverlay = onSwitchToAIOverlay
        _isAIMode = State(initialValue: initialAIMode)
        _selectedTab = State(initialValue: initialTab)
        let prefills = initialAccountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = store.defaultBookkeepingAccount?.name ?? "不选账户"
        _selectedAccountName = State(initialValue: prefills.isEmpty ? fallback : prefills)
    }

    private func applyIntendedTab() {
        selectedTab = intendedInitialTab
    }

    private var activeCategories: [CategoryGroup] {
        selectedTab == .income ? store.incomeCategories : store.expenseCategories
    }

    private var currentGroup: CategoryGroup? {
        guard !activeCategories.isEmpty else { return nil }
        let clamped = min(max(0, selectedGroupIndex), activeCategories.count - 1)
        return activeCategories[clamped]
    }

    private var evaluatedAmount: Double {
        KeypadCalculator.evaluate(expression)
    }

    private var composedCategoryPath: String {
        guard let group = currentGroup else { return "餐饮-零食甜品" }
        if let subIdx = selectedSubIndex, subIdx >= 0, subIdx < group.subcategories.count {
            return "\(group.name)-\(group.subcategories[subIdx].name)"
        }
        return group.name
    }

    private var currentIconName: String {
        guard let group = currentGroup else { return "food_snack" }
        if let subIdx = selectedSubIndex, subIdx >= 0, subIdx < group.subcategories.count {
            return group.subcategories[subIdx].iconName
        }
        return group.iconName
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isAIMode {
                aiChatTopHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                aiAssistantBody
            } else {
                sheetTopHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                manualBookkeepingBody
            }
        }
        .background(MimiTheme.cardBackground.ignoresSafeArea())
        .sheet(isPresented: $showDatePickerSheet) {
            MimiDatePickerSheet(
                selection: $selectedDate,
                title: "日期",
                mode: .dateAndTime,
                onDone: { showDatePickerSheet = false }
            )
            #if os(iOS)
            .mimiInteractiveSheet(detents: [.height(560)], showDragIndicator: false)
            .presentationCornerRadius(24)
            #endif
        }
        .sheet(isPresented: $showImageSourceDialog) {
            MimiChoiceSheet(
                title: "添加小票并自动识别",
                items: [
                    MimiChoiceItem(id: "camera", icon: "camera", title: "拍照真实小票", subtitle: "拍纸质小票立刻识别"),
                    MimiChoiceItem(id: "album", icon: "photo.on.rectangle", title: "从相册选择", subtitle: "小票或付款截图"),
                    MimiChoiceItem(id: "clipboard", icon: "doc.on.clipboard", title: "识别剪贴板图片", subtitle: "已复制的图片")
                ],
                onSelect: { item in
                    showImageSourceDialog = false
                    #if canImport(UIKit)
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + MimiMotion.handoffDelay(.sheet, reduceMotion: reduceMotion)
                    ) {
                        switch item.id {
                        case "camera":
                            pickerSourceType = .camera
                            showImagePickerSheet = true
                        case "album":
                            pickerSourceType = .photoLibrary
                            showImagePickerSheet = true
                        case "clipboard":
                            readFromClipboard()
                        default:
                            break
                        }
                    }
                    #endif
                },
                onCancel: { showImageSourceDialog = false }
            )
            #if os(iOS)
            .mimiInteractiveSheet(detents: [.height(360)], showDragIndicator: false)
            .presentationCornerRadius(24)
            #endif
        }
        .alert(MimiL10n.string("AI 识别失败"), isPresented: Binding(
            get: { recognitionFailureText != nil },
            set: { if !$0 { recognitionFailureText = nil } }
        )) {
            Button(MimiL10n.string("好")) { recognitionFailureText = nil }
        } message: {
            Text(recognitionFailureText ?? "")
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showImagePickerSheet) {
            UIKitImagePicker(sourceType: pickerSourceType) { pickedImage in
                if let data = pickedImage.jpegData(compressionQuality: 0.8) {
                    let filename = store.saveReceiptImage(data: data)
                    attachedReceiptFilenames.append(filename)
                    Task {
                        do {
                            let result = try await SmartReceiptRecognizer.recognize(imageData: data)
                            await MainActor.run {
                                applyDraft(result.draft)
                            }
                        } catch {
                            await MainActor.run {
                                recognitionFailureText = recognitionDialogText(for: error)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showChatAlbumPicker) {
            PHPickerImageView { imageData in
                recognizeChatImage(imageData, sourceLabel: "相册")
            }
        }
        .sheet(isPresented: $showChatCameraPicker) {
            UIKitImagePicker(sourceType: .camera) { pickedImage in
                if let data = pickedImage.jpegData(compressionQuality: 0.85) {
                    recognizeChatImage(data, sourceLabel: "拍照")
                }
            }
        }
        #endif
        #if os(iOS)
        .fullScreenCover(item: $activeViewerItem) { item in
            FullscreenReceiptViewer(imageData: item.imageData) {
                activeViewerItem = nil
            }
        }
        #else
        .sheet(item: $activeViewerItem) { item in
            FullscreenReceiptViewer(imageData: item.imageData) {
                activeViewerItem = nil
            }
        }
        #endif
        .onAppear {
            // Force intended tab even if SwiftUI reused @State across sheet(item:) swaps.
            applyIntendedTab()
        }
        // Remount-driven reset: more reliable than onAppear alone when UIPageViewController
        // keeps a stale page after 记账 → dismiss → 转账.
        .task(id: presentationID) {
            applyIntendedTab()
        }
        #if os(iOS)
        // Full-height bookkeeping (支出/收入/转账 + keypad). `.medium` was opening as a
        // half-sheet over the 记录页 budget card after v1.3.13/1.3.14 gesture chrome.
        // Keep swipe-down dismiss + horizontal tab paging (axis lock below).
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(suppressSheetDismiss)
        #endif
    }

    private var horizontalAxisLockGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                suppressSheetDismiss = BookkeepingSheetSwipePolicy.isHorizontalDominant(
                    dx: value.translation.width,
                    dy: value.translation.height
                )
            }
            .onEnded { _ in
                suppressSheetDismiss = false
            }
    }

    // MARK: - Top Header with ⇄ Mode Switcher (IMG_2245 & IMG_2247)

    // MARK: - AI Chat Header（金标：[猫头像] 来记笔账吧 · [⇌ 手动记账] [✕]）

    private var aiChatTopHeader: some View {
        HStack(spacing: 10) {
            MimiAskMascotView(size: 32)

            Text("来记笔账吧", bundle: .mimiModule)
                .mimiFont(17, weight: .bold)
                .foregroundColor(MimiTheme.textPrimary)

            Spacer(minLength: 8)

            BookkeepingModeSwitchButton(title: "手动记账") {
                withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                    isAIMode = false
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .mimiFont(13, weight: .bold)
                    .foregroundColor(MimiTheme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().strokeBorder(MimiTheme.strokeSubtle, lineWidth: 1))
                    .mimiMinTouchTarget()
            }
            .mimiPressable()
            .accessibilityLabel(MimiL10n.string("关闭"))
        }
    }

    /// 聊天层相册/拍照选图后：纯 AI（Gemini）识别，草稿进聊天等确认；
    /// 失败时在聊天里如实说明原因，不生成草稿、不落账，可重试。
    private func recognizeChatImage(_ imageData: Data, sourceLabel: String) {
        showChatAttachmentPanel = false
        Task {
            do {
                let result = try await SmartReceiptRecognizer.recognize(imageData: imageData)
                await MainActor.run {
                    aiEngine.appendRecognizedDraft(
                        result.draft,
                        sourceLabel: sourceLabel,
                        isSuspiciousAmount: result.isSuspiciousAmount
                    )
                }
            } catch {
                await MainActor.run {
                    aiEngine.appendRecognitionFailure(recognitionDialogText(for: error), sourceLabel: sourceLabel)
                }
            }
        }
    }

    /// 把识别失败统一换成给用户看的中文说明。
    private func recognitionDialogText(for error: Error) -> String {
        (error as? ReceiptRecognitionFailure)?.dialogText
            ?? ReceiptRecognitionFailure.failed(reason: error.localizedDescription).dialogText
    }

    private var sheetTopHeader: some View {
        HStack(spacing: 10) {
            if isAIMode {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .mimiFont(15, weight: .bold)
                        .foregroundColor(MimiTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(MimiTheme.fillSubtle))
                        .mimiMinTouchTarget()
                }
                .mimiPressable()
                .accessibilityLabel(MimiL10n.string("关闭"))
                BookkeepingModeSwitchButton(title: "手动记账") {
                    withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                        isAIMode = false
                    }
                }
                Spacer()
                Text("任何事都能问我", bundle: .mimiModule)
                    .mimiFont(16, weight: .bold)
                    .foregroundColor(MimiTheme.textPrimary)
                Spacer()
                Color.clear.frame(width: 44, height: 32)
            } else {
                // Gold: 支出 | 收入 | 转账 ····· AI 助手 · ✕
                HStack(spacing: 16) {
                    ForEach(
                        [
                            (TransactionType.expense, "支出"),
                            (TransactionType.income, "收入"),
                            (TransactionType.transfer, "转账")
                        ],
                        id: \.0
                    ) { tab, titleText in
                        Button {
                            selectedTab = tab
                            selectedGroupIndex = 0
                            selectedSubIndex = 0
                        } label: {
                            VStack(spacing: 4) {
                                Text(titleText)
                                    .mimiFont(15, weight: selectedTab == tab ? .bold : .medium)
                                    .foregroundColor(
                                        selectedTab == tab
                                            ? (tab == .income ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)
                                            : MimiTheme.textMuted
                                    )
                                Capsule()
                                    .fill(
                                        selectedTab == tab
                                            ? (tab == .income ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)
                                            : Color.clear
                                    )
                                    .frame(width: 18, height: 3)
                            }
                        }
                        .mimiPressable()
                    }
                }

                Spacer()

                BookkeepingModeSwitchButton(
                    title: "AI 助手",
                    leading: .mascot,
                    accessibilityName: "切换到 AI 记账"
                ) {
                    onSwitchToAIOverlay()
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .mimiFont(14, weight: .bold)
                        .foregroundColor(MimiTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(MimiTheme.fillSubtle))
                        .mimiMinTouchTarget()
                }
                .mimiPressable()
                .accessibilityLabel(MimiL10n.string("关闭"))
            }
        }
    }

    // MARK: - Manual Bookkeeping Mode (IMG_2245 & IMG_2246)

    private var manualBookkeepingBody: some View {
        VStack(spacing: 0) {
            // Page-style tabs so left/right swipe switches 支出|收入|转账;
            // presentationContentInteraction(.scrolls) + axis lock keep sheet dismiss vertical-only.
            TabView(selection: $selectedTab) {
                categoryTabPage(for: .expense)
                    .tag(TransactionType.expense)
                categoryTabPage(for: .income)
                    .tag(TransactionType.income)
                transferTabPage
                    .tag(TransactionType.transfer)
            }
            // Force UIPageViewController rebuild per sheet open — otherwise a prior
            // 支出 page can stick after dismiss even when selectedTab was re-inited.
            .id(presentationID)
            // PageTabViewStyle is iOS-only; macOS host `swift test` rejects `.page`.
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .simultaneousGesture(horizontalAxisLockGesture)
            .onChange(of: selectedTab) { _, _ in
                selectedGroupIndex = 0
                selectedSubIndex = 0
            }

            Divider()

            // Gold pills: 日期 · 账本 · 无账户 · 优惠 / 待报销 · 计入收支 · 计入预算 · 标签
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        showDatePickerSheet = true
                    } label: {
                        let f = DateFormatter()
                        let _ = { f.dateFormat = "M月d日" }()
                        pillLabel(icon: "calendar", text: f.string(from: selectedDate))
                    }
                    .mimiPressable()

                    if selectedTab != .transfer {
                        Menu {
                            ForEach(store.ledgers) { ledger in
                                Button(ledger.name) {
                                    store.currentLedgerName = ledger.name
                                }
                            }
                        } label: {
                            let ledgerName = store.currentLedgerName
                            let short = ledgerName.count > 6 ? String(ledgerName.prefix(4)) + "…" : ledgerName
                            pillLabel(icon: "book.closed", text: short.isEmpty ? "Main…" : short)
                        }

                        Menu {
                            Button(MimiL10n.string("不选账户")) { selectedAccountName = "不选账户" }
                            ForEach(store.accounts) { acc in
                                Button("\(acc.name) (\(MimiTheme.formatRM(acc.balance)))") {
                                    selectedAccountName = acc.name
                                }
                            }
                        } label: {
                            pillLabel(icon: "creditcard", text: selectedAccountName == "不选账户" ? "无账户" : selectedAccountName)
                        }

                        Button {
                            showDiscountInput.toggle()
                        } label: {
                            pillLabel(icon: "tag", text: discountAmountText.isEmpty ? "优惠" : "优惠 RM\(discountAmountText)")
                        }
                        .mimiPressable()
                        .accessibilityLabel(discountAmountText.isEmpty ? "添加优惠" : "优惠 RM\(discountAmountText)")

                        Button {
                            markPendingReimbursement.toggle()
                        } label: {
                            pillLabel(
                                icon: markPendingReimbursement ? "checkmark.circle.fill" : "clock",
                                text: "待报销"
                            )
                        }
                        .mimiPressable()

                        Button {
                            includeInStats.toggle()
                        } label: {
                            pillLabel(
                                icon: includeInStats ? "checkmark.circle.fill" : "slash.circle",
                                text: includeInStats ? "计入收支" : "不计入收支"
                            )
                        }
                        .mimiPressable()

                        Button {
                            includeInBudget.toggle()
                        } label: {
                            pillLabel(
                                icon: includeInBudget ? "checkmark.circle.fill" : "slash.circle",
                                text: includeInBudget ? "计入预算" : "不计入预算"
                            )
                        }
                        .mimiPressable()

                        Menu {
                            ForEach(store.tags, id: \.self) { tag in
                                Button {
                                    if selectedTags.contains(tag) {
                                        selectedTags.removeAll(where: { $0 == tag })
                                    } else {
                                        selectedTags.append(tag)
                                    }
                                } label: {
                                    if selectedTags.contains(tag) {
                                        Label(tag, systemImage: "checkmark")
                                    } else {
                                        Text(tag)
                                    }
                                }
                            }
                        } label: {
                            pillLabel(icon: "number", text: selectedTags.isEmpty ? "标签" : selectedTags.joined(separator: ","))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if showDiscountInput, selectedTab != .transfer {
                HStack(spacing: 10) {
                    Text("优惠金额", bundle: .mimiModule)
                        .mimiFont(13, weight: .medium)
                        .foregroundColor(MimiTheme.textSecondary)
                    TextField("0.00", text: $discountAmountText)
                        .mimiFont(15, weight: .semibold, design: .rounded)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(MimiTheme.fillSubtle))
                    Button(MimiL10n.string("完成")) {
                        showDiscountInput = false
                    }
                    .mimiFont(13, weight: .semibold)
                    .foregroundColor(MimiTheme.expenseBlue)
                    .frame(minHeight: MimiHIG.minTouch)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Amount + Note Row (gold: RM0.00 + MYR ⌄, 点击填写备注信息 + 相册/拍照)
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(expression.isEmpty ? "RM0.00" : "RM\(expression)")
                        .mimiFont(30, weight: .bold, design: .rounded)
                        .foregroundColor(selectedTab == .income ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)

                    Menu {
                        ForEach(CurrencyCode.allCases, id: \.self) { code in
                            Button(code.rawValue) { selectedCurrency = code }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(selectedCurrency.rawValue)
                                .mimiFont(12, weight: .semibold)
                            Image(systemName: "chevron.down")
                                .mimiFont(9, weight: .bold)
                        }
                        .foregroundColor(MimiTheme.textMuted)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 8) {
                    TextField("点击填写备注信息", text: $noteText)
                        .mimiFont(14)
                        .foregroundColor(MimiTheme.textPrimary)

                    Button {
                        showImageSourceDialog = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                            .mimiFont(15)
                            .foregroundColor(MimiTheme.textMuted)
                    }
                    .mimiPressable()

                    Button {
                        showImageSourceDialog = true
                    } label: {
                        Image(systemName: "camera")
                            .mimiFont(15)
                            .foregroundColor(MimiTheme.textMuted)
                    }
                    .mimiPressable()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MimiTheme.background))
                .padding(.horizontal, 16)

                if !attachedReceiptFilenames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(attachedReceiptFilenames.enumerated()), id: \.offset) { idx, path in
                                let data = store.loadReceiptImageData(filename: path)
                                ZStack(alignment: .topTrailing) {
                                    Group {
                                        #if canImport(UIKit)
                                        if let d = data, let img = UIImage(data: d) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 48, height: 48)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        } else {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(MimiTheme.chipFill)
                                                .frame(width: 48, height: 48)
                                        }
                                        #else
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(MimiTheme.chipFill)
                                            .frame(width: 48, height: 48)
                                        #endif
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let d = data ?? store.loadReceiptImageData(filename: path) {
                                            activeViewerItem = ReceiptViewerItem(imageData: d)
                                        }
                                    }

                                    Button {
                                        if idx < attachedReceiptFilenames.count {
                                            let removed = attachedReceiptFilenames.remove(at: idx)
                                            store.deleteReceiptImage(filename: removed)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .mimiFont(14)
                                            .foregroundColor(.white)
                                            .background(Circle().fill(Color.black.opacity(0.65)))
                                    }
                                    .offset(x: 3, y: -3)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Custom Calculator Keypad (IMG_2245)
            calculatorKeypad
        }
    }

    @ViewBuilder
    private func categoryTabPage(for tab: TransactionType) -> some View {
        let categories = tab == .income ? store.incomeCategories : store.expenseCategories
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
                    ForEach(Array(categories.enumerated()), id: \.element.id) { idx, group in
                        let isSelected = selectedTab == tab && idx == selectedGroupIndex
                        Button {
                            selectedTab = tab
                            selectedGroupIndex = idx
                            selectedSubIndex = group.subcategories.isEmpty ? nil : 0
                        } label: {
                            VStack(spacing: 6) {
                                MimiStickerIconView(
                                    iconName: group.displayBadgeToken,
                                    categoryName: group.name,
                                    transactionType: tab,
                                    useFirstCharIcon: group.useFirstCharIcon,
                                    size: 58,
                                    isSelected: isSelected
                                )
                                Text(group.name)
                                    .mimiFont(12, weight: isSelected ? .bold : .regular)
                                    .foregroundColor(isSelected ? MimiTheme.textPrimary : MimiTheme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        .mimiPressable()
                    }
                }
                .padding(.top, 6)

                if selectedTab == tab,
                   let group = currentGroupFor(tab: tab),
                   !group.subcategories.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(group.name) · 二级分类")
                            .mimiFont(11, weight: .semibold)
                            .foregroundColor(MimiTheme.textMuted)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                            ForEach(Array(group.subcategories.enumerated()), id: \.element.id) { sIdx, sub in
                                let isSubSelected = selectedSubIndex == sIdx
                                Button {
                                    selectedSubIndex = sIdx
                                } label: {
                                    VStack(spacing: 5) {
                                        MimiStickerIconView(
                                            iconName: sub.iconName,
                                            categoryName: sub.name,
                                            transactionType: tab,
                                            useFirstCharIcon: sub.useFirstCharIcon,
                                            size: 48,
                                            isSelected: isSubSelected
                                        )
                                        Text(sub.name)
                                            .mimiFont(11, weight: isSubSelected ? .bold : .regular)
                                            .foregroundColor(isSubSelected ? MimiTheme.expenseBlue : MimiTheme.textSecondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                    }
                                }
                                .mimiPressable()
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(MimiTheme.background)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func currentGroupFor(tab: TransactionType) -> CategoryGroup? {
        let categories = tab == .income ? store.incomeCategories : store.expenseCategories
        guard !categories.isEmpty else { return nil }
        let clamped = min(max(0, selectedGroupIndex), categories.count - 1)
        return categories[clamped]
    }

    private var transferTabPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            transferAccountPicker
                .padding(.top, 10)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    /// Gold transfer: 扣款账户 ⇄ 入款账户
    private var transferAccountPicker: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(store.accounts) { acc in
                    Button(acc.name) { selectedAccountName = acc.name }
                }
            } label: {
                transferAccountBox(
                    title: selectedAccountName.isEmpty || selectedAccountName == "不选账户" ? "扣款账户" : selectedAccountName,
                    subtitle: selectedAccountName.isEmpty || selectedAccountName == "不选账户" ? "选择转出" : "扣款账户"
                )
            }

            Button {
                let from = selectedAccountName
                selectedAccountName = targetAccountName
                targetAccountName = from
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .mimiFont(16, weight: .semibold)
                    .foregroundColor(MimiTheme.expenseBlue)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(MimiTheme.tintBlueChip))
            }
            .mimiPressable()

            Menu {
                ForEach(store.accounts) { acc in
                    Button(acc.name) { targetAccountName = acc.name }
                }
            } label: {
                transferAccountBox(
                    title: targetAccountName.isEmpty ? "入款账户" : targetAccountName,
                    subtitle: targetAccountName.isEmpty ? "选择转入" : "入款账户"
                )
            }
        }
    }

    private func transferAccountBox(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "creditcard")
                .mimiFont(22)
                .foregroundColor(MimiTheme.textSecondary)
            Text(title)
                .mimiFont(14, weight: .semibold)
                .foregroundColor(MimiTheme.textPrimary)
                .lineLimit(1)
            Text(subtitle)
                .mimiFont(11)
                .foregroundColor(MimiTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 16).fill(MimiTheme.background))
    }

    private func pillLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .mimiFont(11)
            Text(text)
                .mimiFont(12, weight: .medium)
        }
        .foregroundColor(MimiTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(MimiTheme.fillSubtle))
    }

    private var calculatorKeypad: some View {
        let rows: [[String]] = [
            ["7", "8", "9", "⌫"],
            ["4", "5", "6", "-"],
            ["1", "2", "3", "+"],
            ["再记", "0", ".", "完成"]
        ]

        return VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handleKeyTap(key)
                        } label: {
                            Text(key)
                                .mimiFont(key == "完成" || key == "再记" ? 15 : 20, weight: .semibold, design: .rounded)
                                .foregroundColor(key == "完成" ? .white : MimiTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(
                                            key == "完成"
                                                ? (selectedTab == .income ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)
                                                : Color.white
                                        )
                                )
                        }
                        .mimiPressable()
                    }
                }
            }
        }
        .padding(10)
        .background(MimiTheme.fillSubtle)
    }

    private func handleKeyTap(_ key: String) {
        switch key {
        case "⌫":
            if !expression.isEmpty {
                expression.removeLast()
            }
        case "再记":
            saveManualTransaction(dismissAfter: false)
        case "完成":
            saveManualTransaction(dismissAfter: true)
        default:
            expression.append(key)
        }
    }

    private func saveManualTransaction(dismissAfter: Bool) {
        let finalAmount = max(0.0, evaluatedAmount)
        guard finalAmount > 0 else {
            if dismissAfter { onDismiss() }
            return
        }
        if selectedTab == .transfer {
            let src = selectedAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
            let dst = targetAccountName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !src.isEmpty, src != "不选账户",
                  !dst.isEmpty, dst != "不选账户",
                  src != dst else {
                return
            }
        }
        let discountVal = Double(discountAmountText) ?? 0.0
        var tags = selectedTags
        if markPendingReimbursement, !tags.contains("待报销") {
            tags.append("待报销")
        }
        var tx = TransactionItem(
            type: selectedTab,
            categoryPath: selectedTab == .transfer ? "转账" : composedCategoryPath,
            iconName: selectedTab == .transfer ? "⇄" : currentIconName,
            amount: finalAmount,
            accountName: selectedAccountName,
            targetAccountName: selectedTab == .transfer ? targetAccountName : nil,
            note: noteText,
            discountAmount: discountVal,
            includeInStats: selectedTab == .transfer ? false : includeInStats,
            includeInBudget: selectedTab == .transfer ? false : includeInBudget,
            tags: tags,
            receiptImageLabels: attachedReceiptFilenames,
            date: selectedDate
        )
        tx.currency = selectedCurrency
        store.addTransaction(tx)
        expression = ""
        noteText = ""
        discountAmountText = ""
        selectedTags = []
        attachedReceiptFilenames = []
        markPendingReimbursement = false
        includeInBudget = true
        if dismissAfter {
            onDismiss()
        }
    }

    private func readFromClipboard() {
        #if canImport(UIKit)
        if let image = UIPasteboard.general.image, let pngData = image.pngData() {
            let filename = store.saveReceiptImage(data: pngData)
            attachedReceiptFilenames.append(filename)
            Task {
                do {
                    let result = try await SmartReceiptRecognizer.recognize(imageData: pngData)
                    await MainActor.run {
                        applyDraft(result.draft)
                    }
                } catch {
                    await MainActor.run {
                        recognitionFailureText = recognitionDialogText(for: error)
                    }
                }
            }
        } else {
            recognitionFailureText = "剪贴板里没有图片。AI 识别需要付款截图或收据照片，请先截屏、或把图片复制到剪贴板后再试。"
        }
        #endif
    }

    private func applyDraft(_ draft: ParsedDraftBill) {
        if draft.amount > 0 {
            expression = String(format: "%.2f", draft.amount)
        }
        if !draft.note.isEmpty && draft.note != "快捷记账" {
            noteText = draft.note
        }
        if !draft.accountName.isEmpty {
            selectedAccountName = draft.accountName
        }
        selectedDate = draft.date
        if draft.type == .income {
            selectedTab = .income
        } else {
            selectedTab = .expense
        }
        if let grpIdx = activeCategories.firstIndex(where: { $0.id == draft.primaryCategoryId || $0.name == draft.primaryCategoryId }) {
            selectedGroupIndex = grpIdx
            if let subId = draft.subCategoryId,
               let subIdx = activeCategories[grpIdx].subcategories.firstIndex(where: { $0.id == subId || $0.name == subId }) {
                selectedSubIndex = subIdx
            } else if !activeCategories[grpIdx].subcategories.isEmpty {
                selectedSubIndex = 0
            }
        }
    }

    // MARK: - AI Assistant Mode（金标 AI 记账）

    private var aiAssistantBody: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if aiEngine.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(MimiAIEngine.exampleQuestions, id: \.self) { question in
                                    Button {
                                        aiEngine.handleUserMessage(question, store: store)
                                    } label: {
                                        Text(question)
                                            .mimiFont(14)
                                            .foregroundColor(MimiTheme.textSecondary)
                                            .multilineTextAlignment(.leading)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 11)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(MimiTheme.fillSubtle)
                                            )
                                    }
                                    .mimiPressable()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }

                        ForEach(aiEngine.messages) { msg in
                            chatBubbleView(for: msg)
                                .id(msg.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.chatBottomAnchorID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .background(MimiTheme.cardBackground)
                .onAppear {
                    scrollChatToBottom(proxy, animated: false)
                }
                .onChange(of: isAIMode) { _, aiMode in
                    if aiMode {
                        scrollChatToBottom(proxy, animated: false)
                    }
                }
                .onChange(of: aiEngine.messages) { _, _ in
                    scrollChatToBottom(proxy, animated: true)
                }
                .onChange(of: aiEngine.isAnswering) { _, _ in
                    scrollChatToBottom(proxy, animated: true)
                }
            }

            if showChatAttachmentPanel {
                AIAttachmentPanelView(
                    onPickFromAlbum: { showChatAlbumPicker = true },
                    onTakePhoto: { showChatCameraPicker = true },
                    onOpenImportExport: {
                        showChatAttachmentPanel = false
                        onOpenImportExport()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(MimiTheme.cardBackground)
            }

            #if canImport(Speech) && canImport(AVFoundation)
            if speechTranscriber.isRecording {
                Text("正在聆听：\(speechTranscriber.partialText)")
                    .mimiFont(12)
                    .foregroundColor(MimiTheme.expenseBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            } else if !speechTranscriber.statusText.isEmpty {
                Text(speechTranscriber.statusText)
                    .mimiFont(12)
                    .foregroundColor(MimiTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            #endif

            // 金标输入条：胶囊内嵌 ＋；语音用独立 mic，避免长按抢 TextField 焦点
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    TextField("任何事情都能问我", text: $aiInputText)
                        .mimiFont(14)
                        .submitLabel(.send)
                        .onSubmit {
                            let prompt = aiInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !prompt.isEmpty else { return }
                            aiInputText = ""
                            aiEngine.handleUserMessage(prompt, store: store)
                        }

                    #if canImport(Speech) && canImport(AVFoundation)
                    if aiInputText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Image(systemName: speechTranscriber.isRecording ? "mic.fill" : "mic")
                            .mimiFont(15, weight: .semibold)
                            .foregroundColor(speechTranscriber.isRecording ? MimiTheme.dangerRed : MimiTheme.textMuted)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 60, pressing: { isPressing in
                                if isPressing {
                                    Task {
                                        if await speechTranscriber.requestAuthorization() {
                                            speechTranscriber.startRecording()
                                        }
                                    }
                                } else if speechTranscriber.isRecording {
                                    let recognized = speechTranscriber.stopRecording()
                                    if !recognized.trimmingCharacters(in: .whitespaces).isEmpty {
                                        aiInputText = recognized
                                    }
                                }
                            }, perform: {})
                    }
                    #endif

                    Button {
                        withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                            showChatAttachmentPanel.toggle()
                        }
                    } label: {
                        Image(systemName: showChatAttachmentPanel ? "xmark" : "plus")
                            .mimiFont(15, weight: .bold)
                            .foregroundColor(MimiTheme.textMuted)
                            .frame(width: 28, height: 28)
                    }
                    .mimiPressable()
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(MimiTheme.background)
                )

                Button {
                    let prompt = aiInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !prompt.isEmpty else { return }
                    aiInputText = ""
                    aiEngine.handleUserMessage(prompt, store: store)
                } label: {
                    Image(systemName: "arrow.up")
                        .mimiFont(14, weight: .bold)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(
                                aiInputText.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? MimiTheme.controlDisabled
                                    : MimiTheme.expenseBlue
                            )
                        )
                }
                .mimiPressable()
                .disabled(aiInputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(MimiTheme.cardBackground)
        }
    }

    private func scrollChatToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let performScroll = {
            if animated && !reduceMotion {
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(Self.chatBottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.chatBottomAnchorID, anchor: .bottom)
            }
        }
        DispatchQueue.main.async {
            performScroll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            performScroll()
        }
    }

    /// 聊天里的账单草稿卡：确认记账 / 取消，确认才入账。
    private func chatDraftCard(message: AIChatMessage, drafts: [ParsedDraftBill]) -> some View {
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
                            .foregroundColor(MimiTheme.textPrimary)
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
                Button {
                    aiEngine.cancelDrafts(messageId: message.id)
                } label: {
                    Text("取消", bundle: .mimiModule)
                        .mimiFont(13, weight: .semibold)
                        .foregroundColor(MimiTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(MimiTheme.fillSubtle))
                }
                .mimiPressable()

                Button {
                    aiEngine.confirmDrafts(messageId: message.id, in: store)
                } label: {
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
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MimiTheme.cardBackground))
    }

    @ViewBuilder
    private func chatBubbleView(for message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                ForEach(Array(message.blocks.enumerated()), id: \.offset) { idx, block in
                    switch block {
                    case .pendingAnswer:
                        HStack(spacing: 6) {
                            MimiAskMascotView(size: 22)
                            Text("咪咪思考中…", bundle: .mimiModule)
                                .mimiFont(14, weight: .medium)
                                .foregroundColor(MimiTheme.expenseBlue)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(MimiL10n.string("咪咪思考中"))

                    case .text(let text):
                        if message.isUser {
                            MimiChatMarkdownText(text, size: 15)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(MimiTheme.tintBlueSoft)
                                )
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                MimiChatMarkdownText(text, size: 15)
                                    .fixedSize(horizontal: false, vertical: true)
                                if idx == message.blocks.count - 1 {
                                    Text("\(aiGeneratedTimeLabel) 内容由AI生成")
                                        .mimiFont(11)
                                        .foregroundColor(MimiTheme.textMuted)
                                }
                            }
                        }

                    case .categoryTable(let expenseRows, let incomeRows, let customNote):
                        VStack(alignment: .leading, spacing: 10) {
                            categoryTableBox(rows: expenseRows)

                            if !incomeRows.isEmpty {
                                Text("标准收入分类如下：", bundle: .mimiModule)
                                    .mimiFont(13, weight: .bold)
                                    .foregroundColor(MimiTheme.textPrimary)
                                    .padding(.top, 4)
                                categoryTableBox(rows: incomeRows)
                            }

                            if !customNote.isEmpty {
                                Text(customNote)
                                    .mimiFont(12)
                                    .foregroundColor(MimiTheme.textSecondary)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(MimiTheme.fillSubtle)
                        )

                    case .spendingSummary(let title, let amount, let count, let details):
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .mimiFont(15, weight: .bold)
                                .foregroundColor(MimiTheme.textPrimary)
                            Text("总支出 \(MimiTheme.formatRM(amount)) · 共 \(count) 笔")
                                .mimiFont(14, weight: .semibold, design: .rounded)
                                .foregroundColor(MimiTheme.expenseBlue)
                            Text(details)
                                .mimiFont(13)
                                .foregroundColor(MimiTheme.textSecondary)
                            Text("\(aiGeneratedTimeLabel) 内容由AI生成")
                                .mimiFont(11)
                                .foregroundColor(MimiTheme.textMuted)
                        }

                    case .draftBills(let drafts):
                        chatDraftCard(message: message, drafts: drafts)
                    }
                }
            }

            if !message.isUser {
                Spacer(minLength: 28)
            }
        }
    }

    private var aiGeneratedTimeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private func categoryTableBox(rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("一级分类", bundle: .mimiModule)
                    .mimiFont(12, weight: .bold)
                    .frame(width: 82, alignment: .leading)
                Text("二级分类", bundle: .mimiModule)
                    .mimiFont(12, weight: .bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(MimiTheme.fillSubtle)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top) {
                    Text(row.0)
                        .mimiFont(12, weight: .semibold)
                        .foregroundColor(MimiTheme.textPrimary)
                        .frame(width: 82, alignment: .leading)
                    Text(row.1)
                        .mimiFont(12)
                        .foregroundColor(MimiTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                Divider()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MimiTheme.divider, lineWidth: 1)
        )
    }
}
