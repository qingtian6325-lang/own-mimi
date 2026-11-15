import XCTest
@testable import MimiMoneyCore

@MainActor
final class StoreAndBudgetTests: XCTestCase {
    func testCalculatorChainedExpressionEvaluation() {
        XCTAssertEqual(KeypadCalculator.evaluate("15.5+4.5-2"), 18.0, accuracy: 0.001)
        XCTAssertEqual(KeypadCalculator.evaluate("10-25"), 0.0, accuracy: 0.001)
        XCTAssertEqual(KeypadCalculator.evaluate("38.78+"), 38.78, accuracy: 0.001)
    }

    func testDynamicDailyBudgetFormulaAndEdgeCases() {
        let daily = DynamicBudgetEngine.calculateDailyBudget(
            monthlyBudget: 3200.00,
            spentBeforeToday: 1262.52,
            remainingDaysIncludingToday: 21
        )
        XCTAssertEqual(daily, 92.26, accuracy: 0.01)

        XCTAssertEqual(
            DynamicBudgetEngine.calculateDailyBudget(monthlyBudget: 3200, spentBeforeToday: 3500, remainingDaysIncludingToday: 5),
            0.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DynamicBudgetEngine.calculateDailyBudget(monthlyBudget: 3200, spentBeforeToday: 3100, remainingDaysIncludingToday: 0),
            100.0,
            accuracy: 0.001
        )
    }

    func testBillingPeriodStartDay25() {
        let cal = Calendar(identifier: .gregorian)
        let mid = cal.date(from: DateComponents(year: 2026, month: 11, day: 13))!
        let period = BillingPeriodEngine.period(containing: mid, startDay: 25)
        let startComps = cal.dateComponents([.year, .month, .day], from: period.start)
        let endComps = cal.dateComponents([.year, .month, .day], from: period.end)
        XCTAssertEqual(startComps.year, 2026)
        XCTAssertEqual(startComps.month, 10)
        XCTAssertEqual(startComps.day, 25)
        XCTAssertEqual(endComps.month, 11)
        XCTAssertEqual(endComps.day, 24)

        let onStart = cal.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let next = BillingPeriodEngine.period(containing: onStart, startDay: 25)
        XCTAssertEqual(cal.component(.day, from: next.start), 25)
        XCTAssertEqual(cal.component(.month, from: next.start), 11)

        let store = MimiStore(inMemory: true)
        store.resetToCleanEmpty()
        store.setMonthStartDay(25)
        store.updateMonthlyBudget(1000)
        let inPeriod = TransactionItem(
            ledgerId: store.currentLedgerId,
            type: .expense,
            amount: 100,
            primaryCategoryId: "exp_food",
            accountId: "acc_tng",
            date: mid
        )
        let outPeriod = TransactionItem(
            ledgerId: store.currentLedgerId,
            type: .expense,
            amount: 50,
            primaryCategoryId: "exp_food",
            accountId: "acc_tng",
            date: cal.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        )
        store.addTransaction(inPeriod)
        store.addTransaction(outPeriod)
        let p = BillingPeriodEngine.period(containing: mid, startDay: 25)
        XCTAssertEqual(store.expenseTotal(in: p), 100, accuracy: 0.001)
        XCTAssertFalse(p.contains(outPeriod.date))
    }

    func testAccountBalanceReconciliationAndAuditLogsOnCreateEditDelete() {
        let store = MimiStore(inMemory: true)
        let tngId = "acc_tng"
        let pbbId = "acc_pbb"
        let initialTng = store.accounts.first(where: { $0.id == tngId })!.balance

        let tx = TransactionItem(
            ledgerId: store.currentLedgerId,
            type: .expense,
            amount: 5.90,
            currency: .myr,
            primaryCategoryId: "exp_food",
            subCategoryId: "exp_food_snack",
            accountId: tngId,
            note: "示例商户消费"
        )
        store.addTransaction(tx)
        XCTAssertEqual(store.accounts.first(where: { $0.id == tngId })!.balance, initialTng - 5.90, accuracy: 0.001)
        XCTAssertEqual(store.auditLogs.first?.action, .created)

        var edited = tx
        edited.amount = 8.30
        edited.accountId = pbbId
        store.updateTransaction(edited)
        XCTAssertEqual(store.accounts.first(where: { $0.id == tngId })!.balance, initialTng, accuracy: 0.001)
        XCTAssertEqual(store.auditLogs.first?.action, .updated)

        store.deleteTransaction(id: tx.id)
        XCTAssertEqual(store.auditLogs.first?.action, .deleted)
    }

    func testTransferAndExcludeFromStatsDoNotAffectMonthlyExpense() {
        let store = MimiStore(inMemory: true)
        let beforeExpense = store.monthlyExpenseTotal(year: 2026, month: 11)
        let tngBefore = store.accounts.first(where: { $0.id == "acc_tng" })!.balance
        let pbbBefore = store.accounts.first(where: { $0.id == "acc_pbb" })!.balance
        let transfer = TransactionItem(
            ledgerId: store.currentLedgerId,
            type: .transfer,
            amount: 100.0,
            currency: .myr,
            primaryCategoryId: "transfer",
            accountId: "acc_tng",
            targetAccountId: "acc_pbb",
            note: "转账RM100"
        )
        store.addTransaction(transfer)
        XCTAssertEqual(store.monthlyExpenseTotal(year: 2026, month: 11), beforeExpense, accuracy: 0.001)
        XCTAssertEqual(store.accounts.first(where: { $0.id == "acc_tng" })!.balance, tngBefore - 100, accuracy: 0.001)
        XCTAssertEqual(store.accounts.first(where: { $0.id == "acc_pbb" })!.balance, pbbBefore + 100, accuracy: 0.001)
        let srcLogs = store.auditLogs(for: "TNGewallet")
        let dstLogs = store.auditLogs(for: "PBBank")
        XCTAssertTrue(srcLogs.contains { $0.transactionId == transfer.id && !$0.isInflow })
        XCTAssertTrue(dstLogs.contains { $0.transactionId == transfer.id && $0.isInflow })
        XCTAssertEqual(dstLogs.first(where: { $0.transactionId == transfer.id })?.deltaAmount ?? 0, 100, accuracy: 0.001)
    }

    func testNewAccountEmptyOpeningBalancePersistsZero() {
        let store = MimiStore(inMemory: true)
        let opening = AccountBalanceEditPrefill.parseNewAccountOpeningBalance("")
        store.addAccount(AccountItem(
            id: "acc_empty_opening",
            name: "空期初",
            subtitle: "自定义账户",
            iconName: "💳",
            balance: opening,
            initialBalance: opening
        ))
        let created = store.accounts.first(where: { $0.id == "acc_empty_opening" })!
        XCTAssertEqual(created.balance, 0, accuracy: 0.0001)
        XCTAssertEqual(created.initialBalance, 0, accuracy: 0.0001)
    }

    func testCustomAccountNameResolvesWithoutFallingBackToTNG() {
        let store = MimiStore(inMemory: true)
        store.addAccount(AccountItem(
            id: "acc_custom_wallet",
            name: "备用金",
            subtitle: "自定义账户",
            iconName: "💳",
            balance: 50
        ))
        let tngBefore = store.accounts.first(where: { $0.id == "acc_tng" })!.balance
        let tx = TransactionItem(
            type: .expense,
            categoryPath: "餐饮-餐厅",
            amount: 10,
            accountName: "备用金",
            note: "自定义账户支出"
        )
        store.addTransaction(tx)
        XCTAssertEqual(tx.accountId, "acc_custom_wallet")
        XCTAssertEqual(store.accounts.first(where: { $0.id == "acc_custom_wallet" })!.balance, 40, accuracy: 0.001)
        XCTAssertEqual(store.accounts.first(where: { $0.id == "acc_tng" })!.balance, tngBefore, accuracy: 0.001)
    }

    func testCleanEmptyAppStateAndCSVImportExport() {
        let cleanState = MimiStore.makeCleanEmptyAppState()
        XCTAssertTrue(cleanState.transactions.isEmpty)
        XCTAssertTrue(cleanState.auditLogs.isEmpty)
        XCTAssertEqual(cleanState.accounts.reduce(0.0) { $0 + $1.balance }, 0.0, accuracy: 0.001)

        let store = MimiStore(inMemory: true)
        store.resetToCleanEmpty()
        XCTAssertEqual(store.totalRecordsCount, 0)
        XCTAssertEqual(store.recordedDaysCount, 0)
        XCTAssertEqual(store.streakDaysCount, 0)
        XCTAssertEqual(store.netWorth, 0.0, accuracy: 0.001)

        let fixture = Self.syntheticDualTableCSV
        let parsed = MimiCSVService.parseMimiCSV(fixture)
        XCTAssertEqual(parsed.count, 5)
        XCTAssertEqual(parsed.filter { $0.type == .transfer }.count, 1)
        XCTAssertEqual(parsed.filter { $0.type == .expense }.count, 3)
        XCTAssertEqual(parsed.filter { $0.type == .income }.count, 1)

        let importedCount = store.importMimiCSV(fixture, replaceExisting: true)
        XCTAssertEqual(importedCount, 5)
        XCTAssertEqual(store.totalRecordsCount, 5)
        XCTAssertGreaterThan(store.recordedDaysCount, 0)

        let exported = store.exportMimiCSV()
        XCTAssertTrue(exported.contains("日期,时间,类型,金额,一级分类,二级分类,标签,账户,计入收支,计入预算,所属账本,备注,分摊明细"))
        XCTAssertTrue(exported.contains("日期,时间,类型,金额,转入账户,转出账户,备注"))
        XCTAssertTrue(exported.contains("账户互转"))

        let fromTemplate = MimiCSVService.parseMimiCSV(MimiCSVService.standardImportTemplate)
        XCTAssertEqual(fromTemplate.count, 3)
        XCTAssertEqual(fromTemplate.filter { $0.type == .expense }.count, 2)
        XCTAssertEqual(fromTemplate.filter { $0.type == .income }.count, 1)

        let simplified = """
        日期,时间,类型,金额,一级分类,二级分类,账户,备注
        2026-11-08,21:59:00,支出,38.78,交通,加油充电,PBBank,示例
        2026-11-06,10:00:00,收入,1000.00,职业收入,工资,CIMB,示例
        """
        let simplifiedParsed = MimiCSVService.parseMimiCSV(simplified)
        XCTAssertEqual(simplifiedParsed.count, 2)
        XCTAssertEqual(simplifiedParsed.first(where: { $0.type == .expense })?.amount ?? 0, 38.78, accuracy: 0.001)
        XCTAssertEqual(simplifiedParsed.first(where: { $0.type == .income })?.amount ?? 0, 1000.0, accuracy: 0.001)

        // Kapi-compatible xlsx round-trip
        do {
            let xlsxData = try MimiKapiXLSXService.exportXLSX(transactions: parsed)
            let reparsed = try MimiKapiXLSXService.parseXLSX(data: xlsxData)
            XCTAssertEqual(reparsed.count, parsed.count)
            XCTAssertEqual(reparsed.filter { $0.type == .transfer }.count, 1)
            let importedXLSX = try store.importKapiXLSX(xlsxData, replaceExisting: true)
            XCTAssertEqual(importedXLSX, parsed.count)
        } catch {
            XCTFail("xlsx round-trip failed: \(error)")
        }
    }

    /// Anonymous dual-table fixture for parser/import tests (not personal data).
    private static let syntheticDualTableCSV = """
    日期,时间,类型,金额,一级分类,二级分类,标签,账户,计入收支,计入预算,所属账本,备注,分摊明细
    2026-11-01,12:00:00,支出,12.50,餐饮,餐厅,,TNGewallet,是,是,Main Ledger,示例午餐,
    2026-11-02,08:30:00,支出,40.00,交通,加油充电,,PBBank,是,是,Main Ledger,示例加油,
    2026-11-03,09:00:00,支出,5.90,餐饮,零食甜品,,TNGewallet,是,是,Main Ledger,"多行
    示例备注",
    2026-11-04,10:00:00,收入,1000.00,职业收入,工资,,CIMB,是,,Main Ledger,示例工资,
    日期,时间,类型,金额,转入账户,转出账户,备注
    2026-11-05,18:00:00,账户互转,50,TNGewallet,PBBank,示例互转
    """

    func testLedgerTagAndScheduledTransactionsCRUD() {
        let store = MimiStore(inMemory: true)

        // Ledger CRUD
        let initialLedgerCount = store.ledgers.count
        store.addLedger(name: "旅行账本", currency: .sgd, monthlyBudget: 1500.0)
        XCTAssertEqual(store.ledgers.count, initialLedgerCount + 1)
        XCTAssertEqual(store.currentLedger.name, "旅行账本")
        XCTAssertEqual(store.currentLedger.currency, .sgd)
        XCTAssertEqual(store.currentLedger.monthlyBudget, 1500.0, accuracy: 0.001)

        let newId = store.currentLedgerId
        store.renameLedger(id: newId, newName: "新马泰之旅")
        XCTAssertEqual(store.currentLedger.name, "新马泰之旅")

        store.switchLedger(id: "ledger_main")
        XCTAssertEqual(store.currentLedgerId, "ledger_main")

        store.deleteLedger(id: newId)
        XCTAssertEqual(store.ledgers.count, initialLedgerCount)

        // Tag CRUD
        let initialTagCount = store.tags.count
        store.addTag("年货")
        XCTAssertEqual(store.tags.count, initialTagCount + 1)
        XCTAssertTrue(store.tags.contains("年货"))

        let taggedTx = TransactionItem(
            ledgerId: store.currentLedgerId,
            type: .expense,
            amount: 88.0,
            primaryCategoryId: "餐饮",
            tags: ["年货", "家庭"]
        )
        store.addTransaction(taggedTx)
        XCTAssertEqual(store.transactions(forTag: "年货").count, 1)

        store.deleteTag("年货")
        XCTAssertFalse(store.tags.contains("年货"))

        // Scheduled Bookkeeping
        let sched = ScheduledTransactionItem(
            title: "健身房月卡",
            type: .expense,
            amount: 199.0,
            categoryPath: "休闲娱乐-运动健身",
            accountName: "PBBank"
        )
        store.addScheduledTransaction(sched)
        XCTAssertTrue(store.scheduledTransactions.contains(where: { $0.id == sched.id }))

        store.toggleScheduledTransaction(id: sched.id)
        XCTAssertFalse(store.scheduledTransactions.first(where: { $0.id == sched.id })!.isEnabled)

        let txCountBefore = store.transactions.count
        store.executeScheduledTransactionNow(id: sched.id)
        XCTAssertEqual(store.transactions.count, txCountBefore + 1)
        XCTAssertEqual(store.transactions.first?.amount ?? 0.0, 199.0, accuracy: 0.001)

        store.deleteScheduledTransaction(id: sched.id)
        XCTAssertFalse(store.scheduledTransactions.contains(where: { $0.id == sched.id }))

        // User settings
        store.setNickname("景豪专属")
        XCTAssertEqual(store.userNickname, "景豪专属")
    }

    func testInitialCapitalAndNegativeBalanceHandling() {
        // 1. Negative formatting verification
        XCTAssertEqual(MimiTheme.formatRM(-700.0), "-RM700.00")
        XCTAssertEqual(MimiTheme.formatRM(700.0), "RM700.00")
        XCTAssertEqual(MimiTheme.formatRM(0.0), "RM0.00")

        // 2. Spending 700 with 0 starting capital results in -700.00 balance and net worth
        let store = MimiStore(inMemory: true)
        store.resetToCleanEmpty()
        let tngAccount = store.accounts.first(where: { $0.id == "acc_tng" || $0.name == "TNGewallet" })!
        XCTAssertEqual(tngAccount.balance, 0.0, accuracy: 0.001)

        let expense700 = TransactionItem(
            type: .expense,
            categoryPath: "餐饮-晚餐",
            amount: 700.0,
            accountName: tngAccount.name
        )
        store.addTransaction(expense700)

        let updatedTng = store.accounts.first(where: { $0.id == "acc_tng" || $0.name == "TNGewallet" })!
        XCTAssertEqual(updatedTng.balance, -700.0, accuracy: 0.001)
        XCTAssertEqual(store.netWorth, -700.0, accuracy: 0.001)
        XCTAssertEqual(MimiTheme.formatRM(updatedTng.balance), "-RM700.00")

        // 3. Setting initial starting capital (forward mode: 1000 initial - 700 spend = 300 balance)
        store.setAccountInitialBalance(accountId: "acc_tng", initialBalance: 1000.0)
        let tngWithInitial = store.accounts.first(where: { $0.id == "acc_tng" || $0.name == "TNGewallet" })!
        XCTAssertEqual(tngWithInitial.initialBalance, 1000.0, accuracy: 0.001)
        XCTAssertEqual(tngWithInitial.balance, 300.0, accuracy: 0.001)
        XCTAssertEqual(store.netWorth, 300.0, accuracy: 0.001)

        // 4. Calibrating current real balance (reverse mode: current 500 - (-700 delta) = 1200 initial)
        store.updateAccountBalance(accountId: "acc_tng", newBalance: 500.0)
        let tngCalibrated = store.accounts.first(where: { $0.id == "acc_tng" || $0.name == "TNGewallet" })!
        XCTAssertEqual(tngCalibrated.balance, 500.0, accuracy: 0.001)
        XCTAssertEqual(tngCalibrated.initialBalance, 1200.0, accuracy: 0.001)
        XCTAssertEqual(store.netWorth, 500.0, accuracy: 0.001)
    }

    func testBudgetAdjustmentAndCategoryBudgetManagement() {
        let store = MimiStore(inMemory: true)
        let initialBudget = store.monthlyBudgetTotal
        store.updateMonthlyBudget(initialBudget + 500.0)
        XCTAssertEqual(store.monthlyBudgetTotal, initialBudget + 500.0, accuracy: 0.001)

        store.setCategoryBudget(categoryName: "餐饮", monthlyLimit: 750.0, iconName: "food")
        XCTAssertEqual(store.categoryBudgets.first(where: { $0.categoryName == "餐饮" })?.monthlyLimit ?? 0.0, 750.0, accuracy: 0.001)

        store.removeCategoryBudget(categoryName: "餐饮")
        XCTAssertNil(store.categoryBudgets.first(where: { $0.categoryName == "餐饮" }))
    }

    func testExportCSVWithDateFiltering() {
        let store = MimiStore(inMemory: true)
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: now),
              let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return }

        let exported = store.exportMimiCSV(startDate: yesterday, endDate: tomorrow)
        XCTAssertTrue(exported.contains("日期,时间,类型,金额,一级分类"))
    }

    func testReceiptImageCrossSandboxBase64SaveAndLoad() {
        let store = MimiStore(inMemory: true)
        let sampleBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46] // JPEG magic header
        let rawData = Data(sampleBytes)

        let label = store.saveReceiptImage(data: rawData)
        XCTAssertTrue(label.hasPrefix("base64:"), "Lightweight receipt image should be stored with base64 prefix for guaranteed cross-sandbox persistence")

        let loadedData = store.loadReceiptImageData(filename: label)
        XCTAssertNotNil(loadedData)
        XCTAssertEqual(loadedData, rawData)

        // Also test bare base64 loading
        let bare = rawData.base64EncodedString()
        let loadedBare = store.loadReceiptImageData(filename: bare)
        XCTAssertEqual(loadedBare, rawData)
    }

    func testCategoryBudgetsSortedDescendingByUsageRatio() {
        // User scenario:
        // - Category A: budget 100, spent 80 -> 80%
        // - Category B: budget 200, spent 190 -> 95%
        // - Category C: budget 100, spent 20 -> 20%
        // Expected order: Category B (95%), Category A (80%), Category C (20%)
        let budgets: [CategoryBudgetItem] = [
            CategoryBudgetItem(id: "cat_a", categoryId: "exp_餐饮", categoryName: "餐饮", iconName: "food", monthlyLimit: 100, sortOrder: 0),
            CategoryBudgetItem(id: "cat_b", categoryId: "exp_购物", categoryName: "购物", iconName: "bag", monthlyLimit: 200, sortOrder: 1),
            CategoryBudgetItem(id: "cat_c", categoryId: "exp_交通", categoryName: "交通", iconName: "car", monthlyLimit: 100, sortOrder: 2)
        ]
        let spentMap: [String: Double] = [
            "餐饮": 80,
            "购物": 190,
            "交通": 20
        ]
        let sorted = MimiStore.sortCategoryBudgetsByUsageRatio(budgets) { category in
            spentMap[category] ?? 0
        }
        XCTAssertEqual(sorted.map { $0.categoryName }, ["购物", "餐饮", "交通"])

        // Also verify via store.sortedCategoryBudgets(in:)
        let store = MimiStore(inMemory: true)
        store.resetToCleanEmpty()
        var ledger = store.currentLedger
        ledger.categoryBudgets = budgets
        store.currentLedger = ledger
        let now = Date()
        store.addTransaction(TransactionItem(type: .expense, categoryPath: "餐饮-午餐", amount: 80, accountName: "TNGewallet", date: now))
        store.addTransaction(TransactionItem(type: .expense, categoryPath: "购物-日用", amount: 190, accountName: "TNGewallet", date: now))
        store.addTransaction(TransactionItem(type: .expense, categoryPath: "交通-打车", amount: 20, accountName: "TNGewallet", date: now))

        let period = store.currentBillingPeriod(now: now)
        let storeSorted = store.sortedCategoryBudgets(in: period)
        XCTAssertEqual(storeSorted.map { $0.categoryName }, ["购物", "餐饮", "交通"])
    }

    func testTagRenameDeleteAndSharedString18ArtifactSanitization() {
        let store = MimiStore(inMemory: true)
        store.resetToCleanEmpty()

        let tx = TransactionItem(
            ledgerId: store.currentLedgerId,
            type: .expense,
            amount: 35.0,
            primaryCategoryId: "餐饮",
            note: "18",
            tags: ["18", "旧标签"]
        )
        store.addTransaction(tx)
        store.tags.append("18")
        store.tags.append("旧标签")

        store.sanitizeImportedSharedStringArtifacts()
        XCTAssertFalse(store.tags.contains("18"))
        XCTAssertEqual(store.transactions.first?.tags, ["旧标签"])
        XCTAssertEqual(store.transactions.first?.note, "")

        store.renameTag(oldName: "旧标签", newName: "新标签")
        XCTAssertFalse(store.tags.contains("旧标签"))
        XCTAssertTrue(store.tags.contains("新标签"))
        XCTAssertEqual(store.transactions.first?.tags, ["新标签"])

        store.deleteTag("新标签")
        XCTAssertFalse(store.tags.contains("新标签"))
        XCTAssertTrue(store.transactions.first?.tags.isEmpty ?? false)
    }

    func testCategoryBillsScopedTransactionsFiltering() {
        let store = MimiStore(inMemory: true)
        store.resetToCleanEmpty()

        let cal = MimiCalendar.gregorian
        let d1 = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 6, day: 20))!
        let d3 = cal.date(from: DateComponents(year: 2026, month: 11, day: 10))!

        let tx1 = TransactionItem(type: .expense, categoryPath: "餐饮-早餐", amount: 15.0, date: d1)
        let tx2 = TransactionItem(type: .expense, categoryPath: "餐饮-晚餐", amount: 45.0, date: d2)
        let tx3 = TransactionItem(type: .expense, categoryPath: "交通-打车", amount: 30.0, date: d3)

        store.addTransaction(tx1)
        store.addTransaction(tx2)
        store.addTransaction(tx3)

        // All 2026 expenses
        let yearlyExpenses = store.transactions.filter {
            cal.component(.year, from: $0.date) == 2026 && $0.type == .expense
        }
        XCTAssertEqual(yearlyExpenses.count, 3)

        // Filter for "餐饮" category
        let foodYearly = yearlyExpenses.filter {
            let primary = $0.categoryPath.components(separatedBy: "-").first ?? $0.categoryPath
            return primary == "餐饮"
        }
        XCTAssertEqual(foodYearly.count, 2)
        let foodSum = foodYearly.reduce(0.0) { $0 + $1.amount }
        XCTAssertEqual(foodSum, 60.0, accuracy: 0.001)
    }
}

