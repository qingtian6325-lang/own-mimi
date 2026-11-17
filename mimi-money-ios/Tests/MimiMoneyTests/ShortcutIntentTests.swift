import XCTest
@testable import MimiMoneyCore

@MainActor
final class ShortcutIntentTests: XCTestCase {
    /// 与旧示例截图等价的账单草稿（餐饮-零食甜品 RM5.90、TNGewallet），
    /// 走 Gemini 结构化结果的同一条换算路径构造，不经任何文字解析。
    private func sampleDraft() -> ParsedDraftBill {
        GeminiBillDTO(
            type: "expense",
            amount: 5.90,
            counterparty: "示例商户",
            counterpartyKind: "merchant",
            account: "TNGewallet",
            primaryCategory: "餐饮",
            subCategory: "零食甜品",
            occurredAt: "2026-11-08 16:56",
            note: ""
        ).toDraftBill(now: Date())
    }

    func testShortcutRecognizeAndConfirmSavesDirectly() {
        let store = MimiStore(inMemory: true)
        let initialCount = store.transactions.count
        let draft = sampleDraft()
        let saved = ShortcutActionCoordinator.recordRecognizedDraft(draft, in: store)
        XCTAssertEqual(store.transactions.count, initialCount + 1)
        XCTAssertEqual(saved.amount, 5.90, accuracy: 0.001)
        XCTAssertNil(store.pendingEditTransactionId)
    }

    func testShortcutModifyButtonDeepLinksIntoAppBillEditor() {
        let store = MimiStore(inMemory: true)
        let draft = sampleDraft()
        let saved = ShortcutActionCoordinator.recordRecognizedDraft(draft, in: store)
        let url = ShortcutActionCoordinator.markForInAppModification(transactionId: saved.id, in: store)
        XCTAssertEqual(url.absoluteString, "mimimoney://edit-bill?id=\(saved.id.uuidString)")

        store.pendingEditTransactionId = nil
        let handled = ShortcutActionCoordinator.handleIncomingURL(url, in: store)
        XCTAssertTrue(handled)
        XCTAssertEqual(store.pendingEditTransactionId, saved.id)
    }

    func testQuickScanURLSchemeWithRealParameters() {
        let store = MimiStore(inMemory: true)
        let initialCount = store.transactions.count
        let url = URL(string: "mimimoney://quick-scan?amount=25.00&note=Starbucks&account=CIMB")!
        let handled = ShortcutActionCoordinator.handleIncomingURL(url, in: store)
        XCTAssertTrue(handled)
        XCTAssertEqual(store.transactions.count, initialCount + 1)
        XCTAssertEqual(store.pendingShortcutSnippetBill?.amount ?? 0.0, 25.00, accuracy: 0.001)
        XCTAssertEqual(store.pendingShortcutSnippetBill?.accountName, "CIMB")
    }

    // MARK: - v1.1.2 确认型流程：暂存 → 确认才落盘 / 修改转编辑 / 单次消费幂等

    func testStagePendingScanDoesNotRecordUntilFinalized() {
        let store = MimiStore(inMemory: true)
        let initialCount = store.transactions.count
        let tngBefore = store.accounts.first(where: { $0.id == "acc_tng" })?.balance ?? 0
        let draft = sampleDraft()

        let staged = ShortcutActionCoordinator.stageRecognizedDraft(draft, in: store)
        XCTAssertFalse(staged.isConfirmed)
        XCTAssertEqual(store.transactions.count, initialCount, "暂存阶段不应落盘")
        XCTAssertEqual(store.pendingScanTransactions.count, 1)
        let tngStaged = store.accounts.first(where: { $0.id == "acc_tng" })?.balance ?? 0
        XCTAssertEqual(tngStaged, tngBefore, accuracy: 0.001, "暂存阶段不应影响余额")

        let finalized = ShortcutActionCoordinator.finalizePendingScan(id: staged.id, in: store)
        XCTAssertNotNil(finalized)
        XCTAssertEqual(finalized?.isConfirmed, true)
        XCTAssertEqual(store.transactions.count, initialCount + 1)
        XCTAssertEqual(store.pendingScanTransactions.count, 0)
        let tngAfter = store.accounts.first(where: { $0.id == "acc_tng" })?.balance ?? 0
        XCTAssertEqual(tngAfter, tngBefore - 5.90, accuracy: 0.001, "落盘后余额才扣款")
    }

    func testFinalizePendingScanIsIdempotent() {
        let store = MimiStore(inMemory: true)
        let initialCount = store.transactions.count
        let draft = sampleDraft()
        let staged = ShortcutActionCoordinator.stageRecognizedDraft(draft, in: store)

        XCTAssertNotNil(ShortcutActionCoordinator.finalizePendingScan(id: staged.id, in: store))
        XCTAssertNil(ShortcutActionCoordinator.finalizePendingScan(id: staged.id, in: store), "第二次消费必须返回 nil")
        XCTAssertEqual(store.transactions.count, initialCount + 1, "绝不重复记账")
    }

    func testConsumePendingScanForEditRecordsUnconfirmedAndDeepLinks() {
        let store = MimiStore(inMemory: true)
        let initialCount = store.transactions.count
        let draft = sampleDraft()
        let staged = ShortcutActionCoordinator.stageRecognizedDraft(draft, in: store)

        let editing = ShortcutActionCoordinator.consumePendingScanForEdit(id: staged.id, in: store)
        XCTAssertNotNil(editing)
        XCTAssertEqual(editing?.isConfirmed, false, "修改路径转入的记录保持未确认")
        XCTAssertEqual(store.transactions.count, initialCount + 1)
        XCTAssertEqual(store.pendingEditTransactionId, staged.id)
        XCTAssertEqual(store.pendingScanTransactions.count, 0)

        // 重复点「修改」：不重复记账，只重新定位
        let again = ShortcutActionCoordinator.consumePendingScanForEdit(id: staged.id, in: store)
        XCTAssertNotNil(again)
        XCTAssertEqual(store.transactions.count, initialCount + 1)
        // 修改路径消费后，确认路径不得再落盘一笔
        XCTAssertNil(ShortcutActionCoordinator.finalizePendingScan(id: staged.id, in: store))
        XCTAssertEqual(store.transactions.count, initialCount + 1)
    }

    func testDiscardPendingScanNeverRecords() {
        let store = MimiStore(inMemory: true)
        let initialCount = store.transactions.count
        let draft = sampleDraft()
        let staged = ShortcutActionCoordinator.stageRecognizedDraft(draft, in: store)
        store.discardPendingScan(id: staged.id)
        XCTAssertEqual(store.pendingScanTransactions.count, 0)
        XCTAssertNil(ShortcutActionCoordinator.finalizePendingScan(id: staged.id, in: store))
        XCTAssertEqual(store.transactions.count, initialCount)
    }

    // MARK: - v1.1.3 确认卡按钮决策：取消类错误 → 打开编辑；其他错误 → 作废

    func testScanConfirmationFollowUpCancellationOpensEditor() {
        // 点「View」(deny) / 下滑关卡 → CancellationError → 打开 App 改这笔
        XCTAssertTrue(ScanConfirmationFollowUp.isCancellation(CancellationError()))
        XCTAssertEqual(ScanConfirmationFollowUp.followUp(for: CancellationError()), .openEditor)
    }

    func testScanConfirmationFollowUpCancelNamedErrorOpensEditor() {
        // 个别系统路径可能换一种错误类型回传取消：类型名含 cancel 同样算取消
        struct FakeUserCancelledError: Error {}
        XCTAssertEqual(ScanConfirmationFollowUp.followUp(for: FakeUserCancelledError()), .openEditor)
    }

    func testScanConfirmationFollowUpOtherErrorsDiscard() {
        struct StubError: Error {}
        XCTAssertFalse(ScanConfirmationFollowUp.isCancellation(StubError()))
        XCTAssertEqual(ScanConfirmationFollowUp.followUp(for: StubError()), .discard)
        XCTAssertEqual(ScanConfirmationFollowUp.followUp(for: NSError(domain: "test", code: 42)), .discard)
    }

    // MARK: - v1.1.4 iOS 26 选项卡（requestChoice）：文案与后续决策（纯逻辑）

    func testScanChoicePlanCopyMatchesKapiCard() {
        XCTAssertEqual(ScanChoicePlan.viewOptionTitle, "View")
        XCTAssertEqual(ScanChoicePlan.gotItOptionTitle, "Got it")
        XCTAssertEqual(ScanChoicePlan.promptText, "已识别记录以上信息，打开「咪咪记账」查看更多")
    }

    func testScanChoicePlanViewOpensEditorAndDoesNotFinalizeInPerform() {
        XCTAssertTrue(ScanChoicePlan.opensEditor(for: .view))
        XCTAssertFalse(ScanChoicePlan.finalizesInPerform(for: .view))
    }

    func testScanChoicePlanGotItFinalizesInPerformAndDoesNotOpenEditor() {
        XCTAssertFalse(ScanChoicePlan.opensEditor(for: .gotIt))
        XCTAssertTrue(ScanChoicePlan.finalizesInPerform(for: .gotIt))
    }

    // v1.2.1：识别改纯 AI 后，quick-scan 只认带 amount 参数的快速记账；
    // 只带 text 的链接不再解析文字、不记账，只打开手动记账页。
    func testQuickScanURLSchemeWithTextOnlyDoesNotRecord() {
        let store = MimiStore(inMemory: true)
        let initialCount = store.transactions.count
        let raw = "-RM38.78\nPayment - PBB\nPetronas Gas\n08/11/2026".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "mimimoney://quick-scan?text=\(raw)")!
        let handled = ShortcutActionCoordinator.handleIncomingURL(url, in: store)
        XCTAssertTrue(handled)
        XCTAssertEqual(store.transactions.count, initialCount)
        XCTAssertNil(store.pendingShortcutSnippetBill)
        XCTAssertTrue(store.isRecordSheetPresented)
    }

    func testShortcutInstallURLIsConfigured() {
        XCTAssertEqual(
            ShortcutActionCoordinator.shortcutInstallURL,
            "https://www.icloud.com/shortcuts/6c6c112911434258b8c9fc8da452194f"
        )
    }

    func testFinalizeAllPendingScansRecoversStrandedScans() {
        let store = MimiStore(inMemory: true)
        let initialCount = store.transactions.count
        let staged = ShortcutActionCoordinator.stageRecognizedDraft(sampleDraft(), in: store)
        XCTAssertEqual(store.pendingScanTransactions.count, 1)

        let recovered = store.finalizeAllPendingScans()
        XCTAssertEqual(recovered, 1)
        XCTAssertEqual(store.pendingScanTransactions.count, 0)
        XCTAssertEqual(store.transactions.count, initialCount + 1)
        XCTAssertEqual(store.transactions.first(where: { $0.id == staged.id })?.isConfirmed, true)
    }
}
