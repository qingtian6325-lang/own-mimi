import SwiftUI

public struct MimiRootContainerView: View {
    @ObservedObject public var store: MimiStore
    @StateObject private var aiEngine = MimiAIEngine()
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentMainPage: String = "记录"
    @State private var isDrawerOpen: Bool = false
    @State private var showStatsView: Bool = false
    @State private var showAllRecordsCalendar: Bool = false
    @State private var showRecordSheet: Bool = false
    @State private var openRecordSheetInAIMode: Bool = false
    /// 金标 AI 记账：首页浮层（不是整页 sheet）
    @State private var showAIAskOverlay: Bool = false
    /// 手动→AI 时直接全屏；首页 / 选图仍先小窗
    @State private var aiOverlayStartExpanded: Bool = false
    @State private var aiOverlayAttachments: [AIPendingAttachment] = []
    @State private var activeBillForEdit: TransactionItem?
    @State private var showAssetsManager: Bool = false
    @State private var showBudgetManager: Bool = false
    @State private var showCategoryManager: Bool = false
    @State private var activeSettingsTitle: String?
    @State private var showHomeAlbumPicker: Bool = false
    @State private var showHomeCameraPicker: Bool = false
    @State private var homeRecognizedDraft: ParsedDraftBill?
    @State private var homeRecognitionFailureText: String?

    @MainActor
    public init(store: MimiStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .top) {
            HomeRecordView(
                store: store,
                onOpenDrawer: {
                    withAnimation(MimiMotion.drawer(reduceMotion: reduceMotion)) {
                        isDrawerOpen = true
                    }
                },
                onSwitchToStats: {
                    pushOpen { showStatsView = true }
                },
                onOpenSearchOrCalendar: {
                    pushOpen { showAllRecordsCalendar = true }
                },
                onOpenRecordSheet: { aiMode in
                    if aiMode {
                        aiOverlayAttachments = []
                        aiOverlayStartExpanded = false
                        withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                            showAIAskOverlay = true
                        }
                    } else {
                        BookkeepingEntryPreference.rememberManual()
                        openRecordSheetInAIMode = false
                        showRecordSheet = true
                    }
                },
                onSelectTransaction: { tx in
                    activeBillForEdit = tx
                },
                onOpenBudgetManager: {
                    pushOpen { showBudgetManager = true }
                },
                onOpenAssetsManager: {
                    pushOpen { showAssetsManager = true }
                },
                onPickFromAlbum: {
                    showHomeAlbumPicker = true
                },
                onTakePhoto: {
                    showHomeCameraPicker = true
                },
                onOpenImportExport: {
                    pushOpen { activeSettingsTitle = DrawerDestination.importExport.rawValue }
                }
            )
            .allowsHitTesting(!isAnyFeaturePageOpen)
            .accessibilityHidden(isAnyFeaturePageOpen)
            .compositingGroup()

            // Top floating Shortcut Snippet Overlay when triggered via URL / Quick-Scan
            if let snippetBill = store.pendingShortcutSnippetBill {
                ZStack(alignment: .top) {
                    // Tap anywhere outside to dismiss
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                                store.pendingShortcutSnippetBill = nil
                            }
                        }

                    ScreenshotResultSnippetView(
                        transaction: snippetBill,
                        onModifyTapped: {
                            withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                                store.pendingShortcutSnippetBill = nil
                            }
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + MimiMotion.handoffDelay(.sheet, reduceMotion: reduceMotion)
                            ) {
                                pushOpen { activeBillForEdit = snippetBill }
                            }
                        },
                        onConfirmTapped: {
                            withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                                store.pendingShortcutSnippetBill = nil
                            }
                        },
                        onCloseTapped: {
                            withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                                store.pendingShortcutSnippetBill = nil
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.height < -15 {
                                    withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                                        store.pendingShortcutSnippetBill = nil
                                    }
                                }
                            }
                    )
                }
                .transition(MimiMotion.snippetTransition)
                .zIndex(20)
                .onAppear {
                    // Auto-dismiss after 5 seconds so it never blocks the user screen indefinitely
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        if store.pendingShortcutSnippetBill?.id == snippetBill.id {
                            withAnimation(MimiMotion.quick(reduceMotion: reduceMotion)) {
                                store.pendingShortcutSnippetBill = nil
                            }
                        }
                    }
                }
            }

            // 问账条面板（相册/拍照）识别出的账单草稿：App 内确认后才入账
            if let homeDraft = homeRecognizedDraft {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            homeRecognizedDraft = nil
                        }

                    ScreenshotResultSnippetView(
                        transaction: TransactionItem(
                            type: homeDraft.type,
                            categoryPath: homeDraft.categoryPath,
                            iconName: homeDraft.iconName,
                            amount: homeDraft.amount,
                            accountName: homeDraft.accountName,
                            targetAccountName: homeDraft.targetAccountName,
                            note: homeDraft.note,
                            date: homeDraft.date
                        ),
                        onModifyTapped: {
                            let saved = ShortcutActionCoordinator.recordRecognizedDraft(homeDraft, in: store)
                            homeRecognizedDraft = nil
                            pushOpen { activeBillForEdit = saved }
                        },
                        onConfirmTapped: {
                            _ = ShortcutActionCoordinator.recordRecognizedDraft(homeDraft, in: store)
                            homeRecognizedDraft = nil
                        },
                        onCloseTapped: {
                            homeRecognizedDraft = nil
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .transition(MimiMotion.snippetTransition)
                .zIndex(25)
            }

            if showAIAskOverlay {
                MimiAIAskOverlayView(
                    store: store,
                    aiEngine: aiEngine,
                    initialAttachments: aiOverlayAttachments,
                    startExpanded: aiOverlayStartExpanded,
                    onDismiss: {
                        withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                            showAIAskOverlay = false
                            aiOverlayAttachments = []
                            aiOverlayStartExpanded = false
                        }
                    },
                    onOpenManual: {
                        BookkeepingEntryPreference.rememberManual()
                        withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                            showAIAskOverlay = false
                            aiOverlayAttachments = []
                            aiOverlayStartExpanded = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pageHandoffDelay) {
                            openRecordSheetInAIMode = false
                            showRecordSheet = true
                        }
                    },
                    onOpenImportExport: {
                        withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                            showAIAskOverlay = false
                            aiOverlayAttachments = []
                            aiOverlayStartExpanded = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pageHandoffDelay) {
                            pushOpen { activeSettingsTitle = DrawerDestination.importExport.rawValue }
                        }
                    }
                )
                .transition(
                    aiOverlayStartExpanded
                        ? .opacity
                        : MimiMotion.sheetTransition
                )
                .zIndex(55)
            }

            if isDrawerOpen {
                SideDrawerMenuView(
                    store: store,
                    onClose: {
                        // 面板已自行滑出，这里只卸视图
                        isDrawerOpen = false
                    },
                    onSelectDestination: { dest in
                        isDrawerOpen = false
                        handleDrawerSelection(dest)
                    }
                )
                .zIndex(30)
            }

            // 功能页：打开从右往左推进，返回从左往右退出
            // Note: mimiEdgeSwipeBack is handled directly within each feature page and subpage,
            // ensuring secondary drill-downs pop back to their parent views rather than dismissing to Home.
            if showStatsView {
                MimiStatsView(
                    store: store,
                    onOpenDrawer: {
                        pushClose { showStatsView = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pageHandoffDelay) {
                            isDrawerOpen = true
                        }
                    },
                    onSwitchToHome: {
                        pushClose { showStatsView = false }
                    },
                    onOpenAssets: {
                        pushClose { showStatsView = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pageHandoffDelay) {
                            pushOpen { showAssetsManager = true }
                        }
                    }
                )
                .transition(MimiMotion.pageTransition(reduceMotion: reduceMotion))
                .zIndex(40)
            }

            if showAllRecordsCalendar {
                AllRecordsCalendarView(
                    store: store,
                    onDismiss: { pushClose { showAllRecordsCalendar = false } },
                    onSelectTransaction: { tx in
                        activeBillForEdit = tx
                    },
                    onOpenStats: {
                        pushClose { showAllRecordsCalendar = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pageHandoffDelay) {
                            pushOpen { showStatsView = true }
                        }
                    },
                    onOpenAsk: {
                        pushClose { showAllRecordsCalendar = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pageHandoffDelay) {
                            aiOverlayAttachments = []
                            aiOverlayStartExpanded = false
                            withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                                showAIAskOverlay = true
                            }
                        }
                    },
                    onOpenRecord: {
                        pushClose { showAllRecordsCalendar = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pageHandoffDelay) {
                            BookkeepingEntryPreference.rememberManual()
                            openRecordSheetInAIMode = false
                            showRecordSheet = true
                        }
                    }
                )
                .transition(MimiMotion.pageTransition(reduceMotion: reduceMotion))
                .zIndex(41)
            }

            if showAssetsManager {
                AssetsAndAccountDetailView(
                    store: store,
                    aiEngine: aiEngine,
                    onDismiss: { pushClose { showAssetsManager = false } }
                )
                .transition(MimiMotion.pageTransition(reduceMotion: reduceMotion))
                .zIndex(42)
            }

            if showBudgetManager {
                BudgetManagementView(
                    store: store,
                    onDismiss: { pushClose { showBudgetManager = false } }
                )
                .transition(MimiMotion.pageTransition(reduceMotion: reduceMotion))
                .zIndex(43)
            }

            if showCategoryManager {
                CategoryManagementView(
                    store: store,
                    onDismiss: { pushClose { showCategoryManager = false } }
                )
                .transition(MimiMotion.pageTransition(reduceMotion: reduceMotion))
                .zIndex(44)
            }

            if let settingsTitle = activeSettingsTitle {
                SettingsAndShortcutsGuideView(
                    store: store,
                    aiEngine: aiEngine,
                    initialSectionTitle: settingsTitle,
                    onDismiss: { pushClose { activeSettingsTitle = nil } },
                    onModifyTransactionFromPopup: { tx in
                        activeBillForEdit = tx
                    }
                )
                .transition(MimiMotion.pageTransition(reduceMotion: reduceMotion))
                .zIndex(45)
            }
        }
        // 不用整棵 ZStack 挂 .animation(value:)——会连带首页一起重绘，又卡又糊。
        // 过场只靠 pushOpen / pushClose / sheet 的 withAnimation。
        .sheet(isPresented: $showRecordSheet) {
            RecordAndAISheetView(
                store: store,
                aiEngine: aiEngine,
                initialAIMode: openRecordSheetInAIMode,
                onDismiss: { showRecordSheet = false },
                onOpenCategorySettings: {
                    showRecordSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + sheetHandoffDelay) {
                        pushOpen { showCategoryManager = true }
                    }
                },
                onEditRecognizedTransaction: { savedTx in
                    showRecordSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + sheetHandoffDelay) {
                        activeBillForEdit = savedTx
                    }
                },
                onOpenImportExport: {
                    showRecordSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + sheetHandoffDelay) {
                        pushOpen { activeSettingsTitle = DrawerDestination.importExport.rawValue }
                    }
                },
                onSwitchToAIOverlay: {
                    BookkeepingEntryPreference.rememberAI()
                    showRecordSheet = false
                    aiOverlayAttachments = []
                    aiOverlayStartExpanded = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + sheetHandoffDelay) {
                        withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
                            showAIAskOverlay = true
                        }
                    }
                }
            )
            // Full-screen bookkeeping; RecordAndAISheetView owns axis-lock dismiss (v1.3.13).
            .mimiInteractiveSheet(detents: [.large])
        }
        .sheet(item: $activeBillForEdit) { bill in
            BillDetailSheetView(
                store: store,
                transaction: bill,
                onDismiss: {
                    activeBillForEdit = nil
                    store.pendingEditTransactionId = nil
                }
            )
            .mimiInteractiveSheet(detents: [.large])
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showHomeAlbumPicker) {
            PHPickerImageView { imageData in
                recognizeHomeImage(imageData)
            }
        }
        .sheet(isPresented: $showHomeCameraPicker) {
            UIKitImagePicker(sourceType: .camera) { image in
                if let data = image.jpegData(compressionQuality: 0.85) {
                    recognizeHomeImage(data)
                }
            }
        }
        #endif
        .onAppear {
            syncFromShortcutIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                syncFromShortcutIfNeeded()
            }
        }
        .onChange(of: store.pendingEditTransactionId) { _, newId in
            if let id = newId,
               let match = store.transactions.first(where: { $0.id == id }) {
                activeBillForEdit = match
            }
        }
        .onChange(of: store.isRecordSheetPresented) { _, presented in
            if presented {
                openRecordSheetInAIMode = false
                showRecordSheet = true
                store.isRecordSheetPresented = false
            }
        }
        .onOpenURL { url in
            store.reloadFromDisk()
            _ = store.finalizeAllPendingScans()
            if ShortcutActionCoordinator.handleIncomingURL(url, in: store),
               let id = store.pendingEditTransactionId,
               let match = store.transactions.first(where: { $0.id == id }) {
                activeBillForEdit = match
            }
        }
        .environmentObject(languageStore)
        .environment(\.locale, languageStore.effectiveLocale)
        .alert(MimiL10n.string("AI 识别失败"), isPresented: Binding(
            get: { homeRecognitionFailureText != nil },
            set: { if !$0 { homeRecognitionFailureText = nil } }
        )) {
            Button(MimiL10n.string("好")) { homeRecognitionFailureText = nil }
        } message: {
            Text(homeRecognitionFailureText ?? "")
        }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { !store.hasCompletedOnboarding },
            set: { presented in
                if !presented { store.completeOnboarding() }
            }
        )) {
            OnboardingGuideView(store: store) {
                // Flag already set inside the guide
            }
        }
        #else
        .sheet(isPresented: Binding(
            get: { !store.hasCompletedOnboarding },
            set: { presented in
                if !presented { store.completeOnboarding() }
            }
        )) {
            OnboardingGuideView(store: store) {
                // Flag already set inside the guide
            }
        }
        #endif
    }

    private func syncFromShortcutIfNeeded() {
        store.reloadFromDisk()
        _ = store.finalizeAllPendingScans()
        if let id = store.pendingEditTransactionId,
           let match = store.transactions.first(where: { $0.id == id }) {
            activeBillForEdit = match
        }
    }

    private var isAnyFeaturePageOpen: Bool {
        showStatsView || showAllRecordsCalendar || showAssetsManager || showBudgetManager || showCategoryManager || activeSettingsTitle != nil
    }

    private var pageHandoffDelay: TimeInterval {
        MimiMotion.handoffDelay(.page, reduceMotion: reduceMotion)
    }

    private var sheetHandoffDelay: TimeInterval {
        MimiMotion.handoffDelay(.sheet, reduceMotion: reduceMotion)
    }

    private func pushOpen(_ updates: @escaping () -> Void) {
        withAnimation(MimiMotion.page(reduceMotion: reduceMotion), updates)
    }

    private func pushClose(_ updates: @escaping () -> Void) {
        withAnimation(MimiMotion.pageDismiss(reduceMotion: reduceMotion), updates)
    }

    /// 首页 ＋ 面板选图/拍照：先进入 AI 小窗，带上照片，用户可再打字后一次发送。
    private func openAIComposer(withImageData imageData: Data, label: String) {
        BookkeepingEntryPreference.rememberAI()
        aiOverlayAttachments = [AIPendingAttachment(imageData: imageData, label: label)]
        aiOverlayStartExpanded = false
        withAnimation(MimiMotion.sheet(reduceMotion: reduceMotion)) {
            showAIAskOverlay = true
        }
    }

    private func recognizeHomeImage(_ imageData: Data) {
        openAIComposer(withImageData: imageData, label: "照片")
    }

    private func handleDrawerSelection(_ destination: DrawerDestination) {
        pushOpen {
            switch destination {
            case .calendar:
                showAllRecordsCalendar = true
            case .stats:
                showStatsView = true
            case .assets:
                showAssetsManager = true
            case .budgets:
                showBudgetManager = true
            case .categories:
                showCategoryManager = true
            case .ledgers, .widgets, .tags, .importExport, .autoBookkeeping, .scheduledBookkeeping, .settings:
                activeSettingsTitle = destination.rawValue
            }
        }
    }
}
