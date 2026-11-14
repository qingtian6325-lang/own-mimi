import XCTest
@testable import MimiMoneyCore

@MainActor
final class GeminiAndChatTests: XCTestCase {

private var originalExecutor: (@Sendable (String, [String: Any], TimeInterval) async throws -> [String: Any])!
private var originalBackoff: (@Sendable () -> TimeInterval)!

override func setUp() {
super.setUp()
originalExecutor = GeminiClient.singleRequestExecutor
originalBackoff = GeminiClient.retryBackoffSeconds
}

override func tearDown() {
GeminiClient.singleRequestExecutor = originalExecutor
GeminiClient.retryBackoffSeconds = originalBackoff
super.tearDown()
}

// MARK: - Gemini 结构化输出 fixtures 解析

func testGeminiFixtureExpenseRestaurantTNG() throws {
// 模拟 Gemini generateContent 响应：candidates[0].content.parts[0].text 是结构化 JSON
let responseJSON = """
{"candidates":[{"content":{"parts":[{"text":"{\\"type\\":\\"expense\\",\\"amount\\":38.99,\\"counterparty\\":\\"示例餐厅\\",\\"counterpartyKind\\":\\"merchant\\",\\"account\\":\\"TNGewallet\\",\\"primaryCategory\\":\\"餐饮\\",\\"subCategory\\":\\"餐厅\\",\\"occurredAt\\":\\"2026-11-10 20:07\\",\\"note\\":\\"示例餐厅 消费\\"}"}]}}]}
"""
let dto = try decodeDTO(fromGenerateContentResponse: responseJSON)
let draft = dto.toDraftBill(now: Date())
XCTAssertEqual(draft.type,.expense)
XCTAssertEqual(draft.amount, 38.99, accuracy: 0.001)
XCTAssertEqual(draft.primaryCategoryId, "exp_food")
XCTAssertEqual(draft.subCategoryId, "exp_food_restaurant")
XCTAssertEqual(draft.categoryDisplayName, "餐饮-餐厅")
XCTAssertEqual(draft.accountId, "acc_tng")
XCTAssertEqual(draft.accountDisplayName, "TNGewallet")
XCTAssertEqual(draft.merchantOrNote, "示例餐厅 消费")

let cal = Calendar(identifier:.gregorian)
let comps = cal.dateComponents([.year,.month,.day,.hour,.minute], from: draft.occurredAt)
XCTAssertEqual(comps.year, 2026)
XCTAssertEqual(comps.month, 11)
XCTAssertEqual(comps.day, 10)
XCTAssertEqual(comps.hour, 20)
XCTAssertEqual(comps.minute, 7)
}

func testGeminiFixtureIncomeFromPersonUsesLocalNoteRule() throws {
// Gemini 没给备注时，本地按「{姓名} 转账」兜底生成
let dto = GeminiBillDTO(
type: "income",
amount: 150.0,
counterparty: "示例联系人",
counterpartyKind: "person",
account: "PBBank",
primaryCategory: "别人转账",
subCategory: "",
occurredAt: "2026-11-08 21:59",
note: ""
)
let draft = dto.toDraftBill(now: Date())
XCTAssertEqual(draft.type,.income)
XCTAssertEqual(draft.primaryCategoryId, "inc_custom_transfer")
XCTAssertEqual(draft.accountId, "acc_pbb")
XCTAssertEqual(draft.merchantOrNote, "示例联系人 转账")
}

func testGeminiFixtureExpenseToPersonNoteRuleAndCategory() throws {
let dto = GeminiBillDTO(
type: "expense",
amount: 200.0,
counterparty: "示例联系人",
counterpartyKind: "person",
account: "TNGewallet",
primaryCategory: "资金往来",
subCategory: "人情往来",
occurredAt: "2026-11-09 12:00",
note: ""
)
let draft = dto.toDraftBill(now: Date())
XCTAssertEqual(draft.type,.expense)
XCTAssertEqual(draft.categoryDisplayName, "资金往来-人情往来")
XCTAssertEqual(draft.merchantOrNote, "转账给示例联系人")
}

func testGeminiFixtureFuelStationCategory() throws {
let dto = GeminiBillDTO(
type: "expense",
amount: 38.78,
counterparty: "Petronas",
counterpartyKind: "merchant",
account: "PBBank",
primaryCategory: "交通",
subCategory: "加油充电",
occurredAt: "2026-11-05 08:30",
note: "Petronas 消费"
)
let draft = dto.toDraftBill(now: Date())
XCTAssertEqual(draft.primaryCategoryId, "exp_transport")
XCTAssertEqual(draft.subCategoryId, "exp_trans_fuel")
XCTAssertEqual(draft.categoryDisplayName, "交通-加油充电")
}

func testGeminiSchemaConstrainsCategoriesAndAccounts() {
let schema = GeminiClient.recognitionResponseSchema()
let properties = schema["properties"] as? [String: Any]
let primary = properties?["primaryCategory"] as? [String: Any]
let primaryEnum = primary?["enum"] as? [String] ?? []
XCTAssertTrue(primaryEnum.contains("餐饮"))
XCTAssertTrue(primaryEnum.contains("别人转账"))
let account = properties?["account"] as? [String: Any]
let accountEnum = account?["enum"] as? [String] ?? []
XCTAssertTrue(accountEnum.contains("TNGewallet"))
XCTAssertTrue(accountEnum.contains("PBBank"))
let typeProp = properties?["type"] as? [String: Any]
XCTAssertEqual(typeProp?["enum"] as? [String], ["expense", "income", "transfer"])
}

func testGeminiSchemaHasNoEmptyEnumValues() {
// 回归（v1.2.3）：enum 里混空字符串会被 Google 以 HTTP 400 拒绝
// （"enum[N]: cannot be empty"），v1.2.0–v1.2.2 的 subCategory/targetAccount 中招。
let schema = GeminiClient.recognitionResponseSchema()
let properties = schema["properties"] as? [String: Any]
XCTAssertNotNil(properties)
for (name, rawProp) in properties ?? [:] {
guard let prop = rawProp as? [String: Any],
let values = prop["enum"] as? [String] else { continue }
XCTAssertFalse(values.contains(""), "schema enum \(name) 不得含空字符串")
XCTAssertFalse(values.contains(where: { $0.trimmingCharacters(in:.whitespaces).isEmpty }), "schema enum \(name) 不得含空白字符串")
}
// 「可为空」的两个字段必须改走 nullable，而不是空 enum 值
let sub = properties?["subCategory"] as? [String: Any]
XCTAssertEqual(sub?["nullable"] as? Bool, true)
let target = properties?["targetAccount"] as? [String: Any]
XCTAssertEqual(target?["nullable"] as? Bool, true)
}

func testGeminiOccurredAtParsing() {
let parsed = GeminiBillDTO.parseOccurredAt("2026-11-10 20:07")
XCTAssertNotNil(parsed)
let cal = Calendar(identifier:.gregorian)
let comps = cal.dateComponents([.month,.day,.hour], from: parsed!)
XCTAssertEqual(comps.month, 11)
XCTAssertEqual(comps.day, 10)
XCTAssertEqual(comps.hour, 20)
XCTAssertNil(GeminiBillDTO.parseOccurredAt("不是日期"))
XCTAssertNil(GeminiBillDTO.parseOccurredAt(""))
}

// MARK: - 备注格式规则

func testNoteFormatterRules() {
XCTAssertEqual(
BillNoteFormatter.makeNote(type:.expense, counterparty: "示例餐厅", counterpartyKind: "merchant", modelNote: nil),
"示例餐厅 消费"
)
XCTAssertEqual(
BillNoteFormatter.makeNote(type:.expense, counterparty: "示例联系人", counterpartyKind: "person", modelNote: nil),
"转账给示例联系人"
)
XCTAssertEqual(
BillNoteFormatter.makeNote(type:.income, counterparty: "示例联系人", counterpartyKind: "person", modelNote: nil),
"示例联系人 转账"
)
XCTAssertEqual(
BillNoteFormatter.makeNote(type:.transfer, counterparty: "", counterpartyKind: "merchant", modelNote: nil),
"账户转账"
)
// Gemini 给了干净备注时优先用它
XCTAssertEqual(
BillNoteFormatter.makeNote(type:.expense, counterparty: "SHELL", counterpartyKind: "merchant", modelNote: "SHELL 加油"),
"SHELL 加油"
)
// 带杂讯的备注（百分比/超长）被本地规则替换
XCTAssertEqual(
BillNoteFormatter.makeNote(type:.expense, counterparty: "SHELL", counterpartyKind: "merchant", modelNote: "earn points (lunch 79%"),
"SHELL 消费"
)
XCTAssertFalse(BillNoteFormatter.isCleanNote("这一句备注实在是太长太长了远远超过三十个字的上限啊啊啊啊啊啊啊啊还不够长继续凑字数"))
XCTAssertTrue(BillNoteFormatter.isCleanNote("转账给示例联系人"))
}

// MARK: - 金额合理性拦截

func testAmountSanityInterception() {
XCTAssertTrue(BillAmountSanity.isSuspicious(amount: 0))
XCTAssertTrue(BillAmountSanity.isSuspicious(amount: -12.5))
XCTAssertTrue(BillAmountSanity.isSuspicious(amount: 100_000.01))
XCTAssertFalse(BillAmountSanity.isSuspicious(amount: 100_000))
XCTAssertFalse(BillAmountSanity.isSuspicious(amount: 38.99))
// 状态栏电量百分比误读的真实案例
XCTAssertTrue(BillAmountSanity.isSuspicious(amount: 79, sourceText: "9:54 1 $ 79 (RM38.99)"))
XCTAssertTrue(BillAmountSanity.isSuspicious(amount: 85, sourceText: "电量 85% 信号"))
// 正文确有 RM79 交易时不误伤
XCTAssertFalse(BillAmountSanity.isSuspicious(amount: 79, sourceText: "Payment RM79.00 成功"))
XCTAssertFalse(BillAmountSanity.isSuspicious(amount: 50, sourceText: "午餐 RM50"))
}

// MARK: - 记账句 / 问账句判别

func testMessageClassifier() {
let engine = MimiAIEngine()
func kind(of message: String) -> BillMessageKind {
BillMessageClassifier.classify(message, draftCount: engine.parseNaturalLanguageBills(message).count)
}
XCTAssertEqual(kind(of: "午餐 38"),.billDraft)
XCTAssertEqual(kind(of: "打车 50 TNG"),.billDraft)
XCTAssertEqual(kind(of: "午饭 24.5 咖啡 12.9 打车 18"),.billDraft)
// Kapi 示例问题必须判为问账（即使里面有金额数字）
XCTAssertEqual(kind(of: "查询本月单笔消费超过200块的账单"),.question)
XCTAssertEqual(kind(of: "我本周支出最高的一笔是什么？"),.question)
XCTAssertEqual(kind(of: "我最近一次购物买了什么？"),.question)
XCTAssertEqual(kind(of: "这个月花了多少"),.question)
XCTAssertEqual(kind(of: "今天天气怎么样"),.question)
XCTAssertEqual(kind(of: "你好"),.question)
}

// MARK: - 聊天草稿确认才入账

func testChatDraftConfirmAndCancelFlow() async {
let store = MimiStore(inMemory: true)
let engine = MimiAIEngine()
engine.clearHistory()
let countBefore = store.transactions.count

engine.handleUserMessage("午餐 38", store: store)
let firstReady = await waitUntilDraftReady(engine: engine)
XCTAssertTrue(firstReady, "记账句应生成草稿消息")
guard let draftMessage = engine.messages.last(where: { $0.hasDraftBills }) else {
XCTFail("记账句应生成草稿消息")
return
}
// 确认前不入账
XCTAssertEqual(store.transactions.count, countBefore)
engine.confirmDrafts(messageId: draftMessage.id, in: store)
XCTAssertEqual(store.transactions.count, countBefore + 1)
XCTAssertTrue(store.transactions.contains(where: { $0.amount == 38.0 && $0.categoryPath == "餐饮-餐厅" }))

engine.handleUserMessage("打车 50", store: store)
let secondReady = await waitUntilDraftReady(engine: engine)
XCTAssertTrue(secondReady, "第二句应生成草稿消息")
guard let secondDraft = engine.messages.last(where: { $0.hasDraftBills }) else {
XCTFail("第二句应生成草稿消息")
return
}
engine.cancelDrafts(messageId: secondDraft.id)
XCTAssertEqual(store.transactions.count, countBefore + 1)
engine.clearHistory()
}

/// `sendComposed` 在 Task 里填草稿；等思考结束且出现草稿再断言。
private func waitUntilDraftReady(engine: MimiAIEngine, timeoutSeconds: TimeInterval = 2.0) async -> Bool {
let deadline = Date().addingTimeInterval(timeoutSeconds)
while Date() < deadline {
if !engine.isAnswering, engine.messages.contains(where: { $0.hasDraftBills }) {
return true
}
try? await Task.sleep(nanoseconds: 20_000_000)
}
return !engine.isAnswering && engine.messages.contains(where: { $0.hasDraftBills })
}

// MARK: - Context 汇总数学

func testMonthlySummaryLinesMath() {
let now = DefaultCatalog.makeDate(year: 2026, month: 11, day: 15, hour: 12)
let txs: [TransactionItem] = [
TransactionItem(type:.expense, categoryPath: "餐饮-餐厅", amount: 100, accountName: "TNGewallet", note: "A", date: DefaultCatalog.makeDate(year: 2026, month: 11, day: 2)),
TransactionItem(type:.expense, categoryPath: "交通-加油充电", amount: 50.5, accountName: "PBBank", note: "B", date: DefaultCatalog.makeDate(year: 2026, month: 11, day: 3)),
TransactionItem(type:.expense, categoryPath: "餐饮-餐厅", amount: 999, accountName: "TNGewallet", note: "不计统计", includeInStats: false, date: DefaultCatalog.makeDate(year: 2026, month: 11, day: 4)),
TransactionItem(type:.income, categoryPath: "职业收入", amount: 2800, accountName: "PBBank", note: "工资", date: DefaultCatalog.makeDate(year: 2026, month: 11, day: 1)),
TransactionItem(type:.expense, categoryPath: "购物-生活用品", amount: 200, accountName: "CIMB", note: "C", date: DefaultCatalog.makeDate(year: 2026, month: 10, day: 20))
]
let lines = LedgerContextBuilder.monthlySummaryLines(transactions: txs, monthsBack: 6, now: now)
XCTAssertEqual(lines.count, 2)
XCTAssertTrue(lines[0].contains("2026年11月"))
XCTAssertTrue(lines[0].contains("RM150.50"))
XCTAssertTrue(lines[0].contains("RM2800.00"))
XCTAssertTrue(lines[0].contains("共 3 笔"))
XCTAssertTrue(lines[1].contains("2026年10月"))
XCTAssertTrue(lines[1].contains("RM200.00"))
}

func testRelevantTransactionsCapAndKeywordPriority() {
let now = DefaultCatalog.makeDate(year: 2026, month: 11, day: 15, hour: 12)
var txs: [TransactionItem] = []
for index in 0..<40 {
txs.append(TransactionItem(
type:.expense,
categoryPath: "购物-生活用品",
amount: Double(index + 1),
accountName: "TNGewallet",
note: "购物\(index)",
date: DefaultCatalog.makeDate(year: 2026, month: 11, day: 1 + (index % 14), hour: 10)
))
}
txs.append(TransactionItem(
type:.expense,
categoryPath: "餐饮-餐厅",
amount: 88,
accountName: "TNGewallet",
note: "大餐",
date: DefaultCatalog.makeDate(year: 2026, month: 9, day: 1)
))
let capped = LedgerContextBuilder.relevantTransactions(from: txs, question: "随便问问", now: now)
XCTAssertEqual(capped.count, LedgerContextBuilder.maxRecentRecords)

let matched = LedgerContextBuilder.relevantTransactions(from: txs, question: "我最近一次餐饮买了什么", now: now)
XCTAssertEqual(matched.first?.categoryPath, "餐饮-餐厅")
}

func testBuildContextStructureAndCap() {
let store = MimiStore(inMemory: true)
let context = LedgerContextBuilder.buildContext(store: store, question: "本月花了多少", now: Date())
XCTAssertTrue(context.contains("【月度收支汇总（近6个月）】"))
XCTAssertTrue(context.contains("【账户余额】"))
XCTAssertTrue(context.contains("【预算】"))
XCTAssertLessThanOrEqual(context.count, LedgerContextBuilder.maxCharacters + 32)
}

// MARK: - v1.2.2 超时按路径区分（问账长超时与识别不再共用）

func testTimeoutConfigurationPerPath() {
XCTAssertEqual(GeminiClient.recognitionTimeoutSeconds, 30)
XCTAssertEqual(GeminiClient.chatTimeoutSeconds, 60)
XCTAssertEqual(GeminiClient.testConnectionProbeTimeoutSeconds, 30)
}

// MARK: - v1.2.2 测试连接探针：走 generateContent 的最小请求形状

func testConnectionProbeBodyShape() {
let body = GeminiClient.testConnectionProbeBody(model: "gemini-3.8-flash")
let contents = body["contents"] as? [[String: Any]]
let parts = contents?.first?["parts"] as? [[String: Any]]
XCTAssertEqual(parts?.first?["text"] as? String, "请只回复：OK")
let generationConfig = body["generationConfig"] as? [String: Any]
XCTAssertNotNil(generationConfig?["thinkingConfig"], "探针应带思考抑制，与真实调用走同一条路")
XCTAssertNil(body["systemInstruction"], "探针是最小请求，不带系统提示/账目数据")
}

// MARK: - v1.2.2 思考抑制按模型世代选字段 + 400 剥离回退

func testThinkingSuppressionPerModelFamily() {
// 官方文档定案：gemini-3.8-flash 只支持 low/medium/high，没有 minimal、不能关思考
let for38 = GeminiClient.thinkingSuppressionConfig(forModel: "gemini-3.8-flash")
XCTAssertEqual(for38["thinkingLevel"] as? String, "low")
XCTAssertNil(for38["thinkingBudget"])
// 3.x Lite 系列支持 minimal
let forLite = GeminiClient.thinkingSuppressionConfig(forModel: "gemini-3.1-flash-lite")
XCTAssertEqual(forLite["thinkingLevel"] as? String, "minimal")
XCTAssertNil(forLite["thinkingBudget"])
// 2.5 系用 thinkingBudget: 0 关闭（含 2.5 Lite：2.5 规则优先于 lite 规则）
let for25 = GeminiClient.thinkingSuppressionConfig(forModel: "gemini-2.5-flash")
XCTAssertEqual(for25["thinkingBudget"] as? Int, 0)
XCTAssertNil(for25["thinkingLevel"])
let for25Lite = GeminiClient.thinkingSuppressionConfig(forModel: "gemini-2.5-flash-lite")
XCTAssertEqual(for25Lite["thinkingBudget"] as? Int, 0)
XCTAssertNil(for25Lite["thinkingLevel"])
}

func testBodyByRemovingThinkingConfig() {
let body: [String: Any] = ["generationConfig": ["temperature": 0.2, "thinkingConfig": ["thinkingLevel": "minimal"]]]
let stripped = GeminiClient.bodyByRemovingThinkingConfig(body)
let config = stripped?["generationConfig"] as? [String: Any]
XCTAssertNil(config?["thinkingConfig"])
XCTAssertEqual(config?["temperature"] as? Double, 0.2)
XCTAssertNil(GeminiClient.bodyByRemovingThinkingConfig(["generationConfig": ["temperature": 0.2]]))
XCTAssertNil(GeminiClient.bodyByRemovingThinkingConfig(["contents": []]))
}

// MARK: - v1.2.2 瞬时错误重试（429/5xx/超时，最多一次，带退避）

func testRetryableErrorClassification() {
XCTAssertTrue(GeminiClient.isRetryable(.httpStatus(429, "rate")))
XCTAssertTrue(GeminiClient.isRetryable(.httpStatus(500, "boom")))
XCTAssertTrue(GeminiClient.isRetryable(.httpStatus(503, "unavailable")))
XCTAssertTrue(GeminiClient.isRetryable(.transport("请求超时")))
XCTAssertFalse(GeminiClient.isRetryable(.httpStatus(400, "bad request")))
XCTAssertFalse(GeminiClient.isRetryable(.httpStatus(403, "forbidden")))
XCTAssertFalse(GeminiClient.isRetryable(.missingAPIKey))
XCTAssertFalse(GeminiClient.isRetryable(.emptyResponse))
XCTAssertFalse(GeminiClient.isRetryable(.decodingFailed("x")))
}

func testPerformRequestRetriesTransientFailureExactlyOnce() async {
final class Counter { var value = 0 }
let counter = Counter()
GeminiClient.retryBackoffSeconds = { 0 }
GeminiClient.singleRequestExecutor = { _, _, _ in
counter.value += 1
throw GeminiError.httpStatus(429, "rate limited")
}
do {
_ = try await GeminiClient.performRequest(model: "gemini-3.8-flash", body: ["contents": []], timeout: 1)
XCTFail("持续 429 应最终抛错")
} catch let error as GeminiError {
guard case .httpStatus(let code, _) = error else {
XCTFail("应抛 HTTP 错误，实际：\(error)")
return
}
XCTAssertEqual(code, 429)
} catch {
XCTFail("不应抛其他错误：\(error)")
}
XCTAssertEqual(counter.value, 2, "瞬时错误只重试一次：首发 + 1 次重试")
}

func testPerformRequestSucceedsAfterOneTransientRetry() async throws {
final class Counter { var value = 0 }
let counter = Counter()
GeminiClient.retryBackoffSeconds = { 0 }
GeminiClient.singleRequestExecutor = { _, _, _ in
counter.value += 1
if counter.value == 1 {
throw GeminiError.transport("请求超时")
}
return ["candidates": []]
}
let json = try await GeminiClient.performRequest(model: "gemini-3.8-flash", body: ["contents": []], timeout: 1)
XCTAssertNotNil(json["candidates"])
XCTAssertEqual(counter.value, 2)
}

func testPerformRequestDoesNotRetryClientErrors() async {
final class Counter { var value = 0 }
let counter = Counter()
GeminiClient.retryBackoffSeconds = { 0 }
GeminiClient.singleRequestExecutor = { _, _, _ in
counter.value += 1
throw GeminiError.httpStatus(403, "forbidden")
}
do {
_ = try await GeminiClient.performRequest(model: "gemini-3.8-flash", body: ["contents": []], timeout: 1)
XCTFail("403 应直接抛错")
} catch let error as GeminiError {
guard case .httpStatus(let code, _) = error else {
XCTFail("应抛 HTTP 错误，实际：\(error)")
return
}
XCTAssertEqual(code, 403)
} catch {
XCTFail("不应抛其他错误：\(error)")
}
XCTAssertEqual(counter.value, 1, "客户端错误不重试")
}

// MARK: - v1.2.4 AI 接入修复回归

func testTransferDraftKeepsTargetAccount() {
let dto = GeminiBillDTO(
type: "transfer",
amount: 100,
counterparty: "",
counterpartyKind: "merchant",
account: "TNGewallet",
targetAccount: "PBBank",
primaryCategory: "转账",
subCategory: nil,
occurredAt: "2026-11-11 12:00",
note: "账户转账"
)
let draft = dto.toDraftBill(now: Date())
XCTAssertEqual(draft.type, .transfer)
XCTAssertEqual(draft.accountDisplayName, "TNGewallet")
XCTAssertEqual(draft.targetAccountId, "acc_pbb")
XCTAssertEqual(draft.targetAccountDisplayName, "PBBank")

let store = MimiStore(inMemory: true)
let tx = ShortcutActionCoordinator.makeTransaction(from: draft, in: store, isConfirmed: true)
XCTAssertEqual(tx.targetAccountId, "acc_pbb")
XCTAssertEqual(tx.targetAccountName, "PBBank")
}

func testSuspiciousAmountUsesDraftNoteEvidence() {
// Gemini 路径没有 OCR 原文时，用电量区间整数 + 空/纯数字备注拦截
XCTAssertTrue(BillAmountSanity.isSuspicious(amount: 79, draftNote: ""))
XCTAssertTrue(BillAmountSanity.isSuspicious(amount: 85, draftNote: "85"))
XCTAssertTrue(BillAmountSanity.isSuspicious(amount: 79, sourceText: nil, draftNote: "   "))
XCTAssertFalse(BillAmountSanity.isSuspicious(amount: 79, draftNote: "SHELL 消费"))
XCTAssertFalse(BillAmountSanity.isSuspicious(amount: 38.99, draftNote: ""))
}

func testLocalAnswerDoesNotHijackCategorySpecificSpendingQuestion() {
let store = MimiStore(inMemory: true)
// 细分类问题应交给 Gemini，不返回整月汇总
XCTAssertNil(LocalBookkeepingAnswerer.blocks(for: "餐饮花了多少", in: store))
XCTAssertNil(LocalBookkeepingAnswerer.blocks(for: "交通这个月花了多少", in: store))
// 整月泛问仍可本地答
let monthBlocks = LocalBookkeepingAnswerer.blocks(for: "这个月花了多少", in: store)
XCTAssertNotNil(monthBlocks)
XCTAssertTrue(monthBlocks?.contains(where: {
if case .spendingSummary = $0 { return true }
return false
}) == true)
}

func testImagePreprocessorShrinksOversizedJPEGWhenPossible() {
// 构造一块假「大」数据：无 UIKit 时至少保证函数幂等且不崩
let tiny = Data([0xFF, 0xD8, 0xFF, 0xD9])
let prepared = GeminiImagePreprocessor.prepareForUpload(tiny)
XCTAssertFalse(prepared.isEmpty)
XCTAssertLessThanOrEqual(prepared.count, max(tiny.count, GeminiImagePreprocessor.maxUploadBytes))
}

func testNaturalLanguagePrefersLastUsedAccountWhenUnspecified() {
let engine = MimiAIEngine()
let bills = engine.parseNaturalLanguageBills(
"午餐 38",
preferredAccountId: "acc_pbb",
preferredAccountName: "PBBank"
)
XCTAssertEqual(bills.count, 1)
XCTAssertEqual(bills[0].accountId, "acc_pbb")
XCTAssertEqual(bills[0].accountDisplayName, "PBBank")
}

func testGroqExtractJSONObjectTextFromFence() throws {
let raw = """
```json
{"type":"expense","amount":1}
```
"""
let extracted = try GroqClient.extractJSONObjectText(from: raw)
XCTAssertTrue(extracted.hasPrefix("{"))
XCTAssertTrue(extracted.contains("\"amount\":1"))
}

func testGroqConnectionProbeBodyUsesVisionCapableDefaultModel() {
let body = GroqClient.testConnectionProbeBody(model: GroqSettings.defaultModelName)
XCTAssertEqual(body["model"] as? String, "qwen/qwen3.8-27b")
XCTAssertEqual(body["reasoning_effort"] as? String, "none")
XCTAssertEqual(AIEngineProvider.groq.supportsImageInput, true)
}

func testLegacyLLMAPIKeyIsNotPersistedInUserDefaults() {
UserDefaults.standard.set("sk-leak-test", forKey: "mimi_llm_api_key")
let engine = MimiAIEngine()
engine.clearLegacyPlaintextAPIKeyIfNeeded()
XCTAssertNil(UserDefaults.standard.string(forKey: "mimi_llm_api_key"))
engine.saveAPISettings(key: "should-not-persist", baseURL: "https://example.com", model: "x")
XCTAssertNil(UserDefaults.standard.string(forKey: "mimi_llm_api_key"), "旧自定义 LLM Key 不得再写进 UserDefaults")
}

func testClassifierRoutesDateAndAmountQueriesToQuestion() {
    XCTAssertEqual(BillMessageClassifier.classify("查看11月8日的消费记录", draftCount: 0), .question)
    XCTAssertEqual(BillMessageClassifier.classify("帮我查一下超过100的账单", draftCount: 0), .question)
}

func testGeminiParseOccurredAtHandlesExtraFormatsAndPreservesNowTime() throws {
    let tz = MimiNaturalLanguageDateParser.malaysiaTimeZone
    var cal = MimiNaturalLanguageDateParser.calendar(in: tz)
    cal.timeZone = tz
    let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 15, minute: 20)))

    let dmy = try XCTUnwrap(GeminiBillDTO.parseOccurredAt("08/11/2026 14:30", now: now, timeZone: tz))
    XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute], from: dmy), DateComponents(year: 2026, month: 11, day: 8, hour: 14, minute: 30))

    let en12h = try XCTUnwrap(GeminiBillDTO.parseOccurredAt("10 Nov 2026 8:07 PM", now: now, timeZone: tz))
    XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute], from: en12h), DateComponents(year: 2026, month: 11, day: 10, hour: 20, minute: 7))

    let dateOnly = try XCTUnwrap(GeminiBillDTO.parseOccurredAt("2026-11-08", now: now, timeZone: tz))
    XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute], from: dateOnly), DateComponents(year: 2026, month: 11, day: 8, hour: 15, minute: 20))
}

func testQuestionSystemPromptAndCrossGroupCategoryResolution() {
    let prompt = LedgerContextBuilder.questionSystemPrompt()
    XCTAssertFalse(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

    let resolved = DefaultCatalog.resolveCategoryIds(from: "购物-咖啡", type: .expense)
    XCTAssertEqual(resolved.primaryId, "exp_food")
    XCTAssertEqual(resolved.subId, "exp_food_coffee")
}

// MARK: - Helpers

private func decodeDTO(fromGenerateContentResponse jsonText: String) throws -> GeminiBillDTO {
let data = Data(jsonText.utf8)
let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
let candidates = object?["candidates"] as? [[String: Any]]
let content = candidates?.first?["content"] as? [String: Any]
let parts = content?["parts"] as? [[String: Any]]
let text = parts?.first?["text"] as? String
guard let text else {
XCTFail("fixture 响应缺少 text")
throw GeminiError.emptyResponse
}
return try JSONDecoder().decode(GeminiBillDTO.self, from: Data(text.utf8))
}
}
