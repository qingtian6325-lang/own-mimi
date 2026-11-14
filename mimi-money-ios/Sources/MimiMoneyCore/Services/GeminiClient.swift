import Foundation
#if canImport(Security)
import Security
#endif

// MARK: - Keychain Helper (API keys live ONLY here — never UserDefaults / repo / logs)

public enum KeychainHelper {
private static let service = "com.jinghao.mimimoney.gemini"
private static let account = "gemini_api_key"

public static func saveGeminiAPIKey(_ key: String?) {
#if canImport(Security)
let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
let query: [String: Any] = [
kSecClass as String: kSecClassGenericPassword,
kSecAttrService as String: service,
kSecAttrAccount as String: account
]
SecItemDelete(query as CFDictionary)
guard !trimmed.isEmpty, let data = trimmed.data(using:.utf8) else { return}
var attributes = query
attributes[kSecValueData as String] = data
attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
SecItemAdd(attributes as CFDictionary, nil)
#endif
}

public static func readGeminiAPIKey() -> String? {
#if canImport(Security)
let query: [String: Any] = [
kSecClass as String: kSecClassGenericPassword,
kSecAttrService as String: service,
kSecAttrAccount as String: account,
kSecReturnData as String: true,
kSecMatchLimit as String: kSecMatchLimitOne
]
var item: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &item)
guard status == errSecSuccess, let data = item as? Data,
let value = String(data: data, encoding:.utf8),
!value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
return nil
}
return value.trimmingCharacters(in:.whitespacesAndNewlines)
#else
return nil
#endif
}
}

// MARK: - Gemini Settings

public enum GeminiSettings {
/// 出厂默认模型：Google 官方 Gemini API 定价页（ai.google.dev/gemini-api/docs/pricing，
/// 2026-11-11 核实）中 Free Tier 列为 "Free of charge" 的现行旗舰 Flash 模型。
public static let defaultModelName = "gemini-3.8-flash"

private static let modelUserDefaultsKey = "mimi_gemini_model_name"
private static let statusUserDefaultsKey = "mimi_gemini_last_call_status"
private static let statusDateUserDefaultsKey = "mimi_gemini_last_call_status_date"

public static var modelName: String {
get {
let saved = UserDefaults.standard.string(forKey: modelUserDefaultsKey)?
.trimmingCharacters(in:.whitespacesAndNewlines)
return (saved?.isEmpty == false) ? saved! : defaultModelName
}
set {
let trimmed = newValue.trimmingCharacters(in:.whitespacesAndNewlines)
UserDefaults.standard.set(trimmed.isEmpty ? defaultModelName : trimmed, forKey: modelUserDefaultsKey)
}
}

public static var apiKey: String? {
KeychainHelper.readGeminiAPIKey()
}

public static var hasAPIKey: Bool {
apiKey != nil
}

public static func saveAPIKey(_ key: String?) {
KeychainHelper.saveGeminiAPIKey(key)
}

/// 最近一次 Gemini 调用状态（只记成功/失败与原因简述，绝不记录 key）。
public static func recordCallStatus(success: Bool, message: String) {
let prefix = success ? "成功" : "失败"
UserDefaults.standard.set("\(prefix)：\(message)", forKey: statusUserDefaultsKey)
UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: statusDateUserDefaultsKey)
}

public static var lastCallStatusText: String? {
guard let text = UserDefaults.standard.string(forKey: statusUserDefaultsKey) else { return nil}
let ts = UserDefaults.standard.double(forKey: statusDateUserDefaultsKey)
guard ts > 0 else { return text}
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "zh_CN")
formatter.dateFormat = "MM-dd HH:mm"
return "\(text)（\(formatter.string(from: Date(timeIntervalSince1970: ts)))）"
}
}

// MARK: - Gemini Errors

public enum GeminiError: Error, CustomStringConvertible {
case missingAPIKey
case httpStatus(Int, String)
case emptyResponse
case decodingFailed(String)
case transport(String)

public var description: String {
switch self {
case .missingAPIKey:
return "尚未填写 \(AIEngineSettings.provider.displayName) API Key"
case .httpStatus(let code, let message):
if code == 429 {
return "HTTP 429：免费额度已用完或请求过于频繁"
}
return "HTTP \(code)：\(message)"
case .emptyResponse:
return "Gemini 返回为空"
case .decodingFailed(let detail):
return "Gemini 返回内容无法解析（\(detail)）"
case .transport(let detail):
return "网络请求失败（\(detail)）"
}
}
}

// MARK: - Gemini Bill DTO (structured output)

public struct GeminiBillDTO: Codable, Equatable, Sendable {
public var type: String // expense | income | transfer
public var amount: Double
public var counterparty: String // 商家名或对方姓名，照截图原文
public var counterpartyKind: String // merchant | person
public var account: String // 付款/收款账户名（App 现有账户之一）
public var targetAccount: String? // 仅转账时：对方账户
public var primaryCategory: String // 一级分类名（App 现有分类）
public var subCategory: String? // 二级分类名，无二级时为 null
public var occurredAt: String // "yyyy-MM-dd HH:mm"
public var note: String // 备注（按规则生成）

public init(
type: String,
amount: Double,
counterparty: String,
counterpartyKind: String,
account: String,
targetAccount: String? = nil,
primaryCategory: String,
subCategory: String? = nil,
occurredAt: String,
note: String
) {
self.type = type
self.amount = amount
self.counterparty = counterparty
self.counterpartyKind = counterpartyKind
self.account = account
self.targetAccount = targetAccount
self.primaryCategory = primaryCategory
self.subCategory = subCategory
self.occurredAt = occurredAt
self.note = note
}

/// 把 Gemini 的结构化结果换算成 App 统一的账单草稿。
/// 分类名再经 DefaultCatalog 按 id 解析校验；备注经 BillNoteFormatter 本地兜底。
public func toDraftBill(now: Date = Date()) -> ParsedDraftBill {
let txType: TransactionType
switch type.lowercased() {
case "income": txType = .income
case "transfer": txType = .transfer
default: txType = .expense
}

let primaryId: String
let subId: String?
let categoryDisplay: String
if txType == .transfer {
primaryId = "transfer"
subId = nil
categoryDisplay = "转账"
} else {
let subName = subCategory ?? ""
let path = subName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
? primaryCategory
: "\(primaryCategory)-\(subName)"
let resolved = DefaultCatalog.resolveCategoryIds(from: path, type: txType)
primaryId = resolved.primaryId
subId = resolved.subId
let display = DefaultCatalog.resolveCategoryDisplay(primaryId: primaryId, subId: subId, type: txType)
categoryDisplay = display.categoryPath
}

let accountId = DefaultCatalog.resolveAccountId(from: account)
let accountName = DefaultCatalog.resolveAccountName(from: accountId)
let resolvedTargetId: String?
let resolvedTargetName: String?
if txType == .transfer, let target = targetAccount?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty {
let tid = DefaultCatalog.resolveAccountId(from: target)
resolvedTargetId = tid
resolvedTargetName = DefaultCatalog.resolveAccountName(from: tid)
} else {
resolvedTargetId = nil
resolvedTargetName = nil
}
let note = BillNoteFormatter.makeNote(
type: txType,
counterparty: counterparty,
counterpartyKind: counterpartyKind,
modelNote: note
)

return ParsedDraftBill(
type: txType,
amount: amount,
currency:.myr,
primaryCategoryId: primaryId,
subCategoryId: subId,
categoryDisplayName: categoryDisplay,
accountId: accountId,
accountDisplayName: accountName,
targetAccountId: resolvedTargetId,
targetAccountDisplayName: resolvedTargetName,
merchantOrNote: note.isEmpty ? counterparty : note,
occurredAt: GeminiBillDTO.parseOccurredAt(occurredAt, now: now) ?? now
)
}

public static func parseOccurredAt(_ text: String, now: Date = Date(), timeZone: TimeZone = .current) -> Date? {
let trimmed = text.trimmingCharacters(in:.whitespacesAndNewlines)
guard !trimmed.isEmpty else { return nil}
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = timeZone
let formatsWithTime = [
"yyyy-MM-dd HH:mm",
"yyyy-MM-dd HH:mm:ss",
"yyyy/MM/dd HH:mm",
"yyyy/MM/dd HH:mm:ss",
"dd/MM/yyyy HH:mm",
"dd/MM/yyyy HH:mm:ss",
"dd-MM-yyyy HH:mm",
"dd-MM-yyyy HH:mm:ss",
"yyyy-MM-dd'T'HH:mm:ss",
"yyyy-MM-dd'T'HH:mm",
"d MMM yyyy HH:mm",
"dd MMM yyyy HH:mm",
"d MMM yyyy, HH:mm",
"dd MMM yyyy, HH:mm",
"d MMM yyyy, h:mm a",
"dd MMM yyyy, h:mm a",
"d MMM yyyy h:mm a",
"dd MMM yyyy h:mm a"
]
for format in formatsWithTime {
formatter.dateFormat = format
if let date = formatter.date(from: trimmed) {
return date
}
}
// 日期字符串缺少具体时刻或为中文自然日期时，保留 now 的时分而不虚构 00:00
let fallback = MimiNaturalLanguageDateParser.parse(
in: trimmed,
now: now,
fallbackDate: now,
timeZone: timeZone
)
return fallback.hasExplicitDateOrTime ? fallback.date : nil
}
}

// MARK: - Gemini REST Client

public enum GeminiClient {
/// 识别调用超时（v1.2.2：8 → 30 秒。纯 AI 无兜底，图大/网慢时 8 秒太紧）。
public static let recognitionTimeoutSeconds: TimeInterval = 30
/// 问账/聊天调用独立长超时（带最长 6000 字账目上下文，首字延迟远高于识别）。
public static let chatTimeoutSeconds: TimeInterval = 60
/// 测试连接的最小生成探针超时（内容极小，30 秒足够判通断）。
public static let testConnectionProbeTimeoutSeconds: TimeInterval = 30

/// 思考抑制配置：识别与查账都不需要长思考，默认思考会显著拖慢首字延迟。
/// 字段与取值按 Google 官方文档定案（ai.google.dev/gemini-api/docs/thinking）：
/// - Gemini 2.5 系用 thinkingBudget，Flash/Lite 可设 0 完全关闭思考；
/// - Gemini 3 系改用 thinkingLevel（给 3 系传 thinkingBudget 会直接 400），
///   其中 3.x Lite 系列支持 minimal，其余 3.x（含默认的 gemini-3.8-flash）
///   只支持 low/medium/high、没有 minimal、也不能完全关思考，最低给 low。
/// 若接口仍拒绝该字段，performRequest 会在 400 时自动去掉 thinkingConfig
/// 重发一次（见 bodyByRemovingThinkingConfig）。
public static func thinkingSuppressionConfig(forModel model: String) -> [String: Any] {
let name = model.lowercased()
if name.contains("2.5") {
return ["thinkingBudget": 0]
}
if name.contains("lite") {
return ["thinkingLevel": "minimal"]
}
return ["thinkingLevel": "low"]
}

/// 返回去掉 generationConfig.thinkingConfig 的请求体副本；原本没有该字段时返回 nil。
public static func bodyByRemovingThinkingConfig(_ body: [String: Any]) -> [String: Any]? {
guard var generationConfig = body["generationConfig"] as? [String: Any],
generationConfig["thinkingConfig"] != nil else {
return nil
}
generationConfig.removeValue(forKey: "thinkingConfig")
var copy = body
copy["generationConfig"] = generationConfig
return copy
}

private static func endpoint(model: String, action: String) -> URL? {
let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded):\(action)")
}

/// 单次网络执行体（默认走真实 URLSession）；单测可替换以离线统计重试次数。
static var singleRequestExecutor: @Sendable (String, [String: Any], TimeInterval) async throws -> [String: Any] = { model, body, timeout in
try await performNetworkRequest(model: model, body: body, timeout: timeout)
}

/// 瞬时错误重试的退避时长（秒）。官方 troubleshooting 建议对 429/5xx/超时
/// 做带 jitter 的指数退避重试；这里每条请求最多只重试一次，取约 1 秒短
/// 退避＋随机抖动，避免把识别（30s）/问账（60s）的总等待明显拉长。
/// 单测可覆写为 { 0 } 即时执行。
static var retryBackoffSeconds: @Sendable () -> TimeInterval = {
1.0 + Double.random(in: 0...0.5)
}

/// 是否值得重试一次：429（限流）、5xx（服务端错误）、传输层错误
/// （含 URLSession 超时，超时在执行体里归入 .transport）。
/// 400/403 等客户端错误、缺 key、空响应、解析失败重试也没有用，不重试。
static func isRetryable(_ error: GeminiError) -> Bool {
switch error {
case .httpStatus(let code, _):
return code == 429 || (500...599).contains(code)
case .transport:
return true
case .missingAPIKey, .emptyResponse, .decodingFailed:
return false
}
}

static func performRequest(
model: String,
body: [String: Any],
timeout: TimeInterval
) async throws -> [String: Any] {
do {
return try await performWithTransientRetry(model: model, body: body, timeout: timeout)
} catch let error as GeminiError {
// thinkingConfig 若被该模型/接口拒绝（HTTP 400），去掉后重发一次；
// key 无效同为 400，但文案可区分，不做无谓重发。
guard case .httpStatus(let code, let message) = error, code == 400,
!message.lowercased().contains("api key"),
let stripped = bodyByRemovingThinkingConfig(body) else {
throw error
}
return try await performWithTransientRetry(model: model, body: stripped, timeout: timeout)
}
}

/// 首发一次；命中 429/5xx/超时等瞬时错误时，短退避后最多再发一次。
private static func performWithTransientRetry(
model: String,
body: [String: Any],
timeout: TimeInterval
) async throws -> [String: Any] {
do {
return try await singleRequestExecutor(model, body, timeout)
} catch let error as GeminiError {
guard isRetryable(error) else {
throw error
}
let backoff = retryBackoffSeconds()
if backoff > 0 {
try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
}
return try await singleRequestExecutor(model, body, timeout)
}
}

private static func performNetworkRequest(
model: String,
body: [String: Any],
timeout: TimeInterval
) async throws -> [String: Any] {
guard let apiKey = GeminiSettings.apiKey else {
throw GeminiError.missingAPIKey
}
guard let url = endpoint(model: model, action: "generateContent") else {
throw GeminiError.transport("模型名无效")
}
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.timeoutInterval = timeout
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
request.httpBody = try JSONSerialization.data(withJSONObject: body)

let data: Data
let response: URLResponse
do {
(data, response) = try await URLSession.shared.data(for: request)
} catch {
throw GeminiError.transport(error.localizedDescription)
}
if let http = response as? HTTPURLResponse,!(200...299).contains(http.statusCode) {
let message = extractErrorMessage(from: data)
throw GeminiError.httpStatus(http.statusCode, message)
}
guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
throw GeminiError.decodingFailed("响应不是 JSON")
}
return json
}

private static func extractErrorMessage(from data: Data) -> String {
guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
let error = json["error"] as? [String: Any],
let message = error["message"] as? String else {
return "无详细信息"
}
return String(message.prefix(120))
}

private static func extractText(from responseJSON: [String: Any]) throws -> String {
guard let candidates = responseJSON["candidates"] as? [[String: Any]],
let content = candidates.first?["content"] as? [String: Any],
let parts = content["parts"] as? [[String: Any]] else {
throw GeminiError.emptyResponse
}
let text = parts.compactMap { $0["text"] as? String}.joined()
guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
throw GeminiError.emptyResponse
}
return text
}

// MARK: 测试连接（先查模型详情确认 key/模型名，再发一次最小 generateContent 真验证）
//
// v1.2.2：只查模型详情太轻——模型存在不等于真实生成路径可用（真机曾出现
// 「测试连接成功但问账每次超时」）。故 GET 通过后追加一次最小生成探针，
// 成功才算连接成功；文案区分「模型不存在/key 无效」与「模型存在但生成失败」。

/// 测试连接第二步的最小生成请求体（让模型只回复 OK），供单测验请求形状。
public static func testConnectionProbeBody(model: String) -> [String: Any] {
return [
"contents": [[
"role": "user",
"parts": [["text": "请只回复：OK"]]
]],
"generationConfig": [
"temperature": 0,
"maxOutputTokens": 64,
"thinkingConfig": thinkingSuppressionConfig(forModel: model)
]
]
}

public static func testConnection() async -> (success: Bool, message: String) {
guard let apiKey = GeminiSettings.apiKey else {
return (false, "尚未填写 Gemini API Key")
}
let model = GeminiSettings.modelName
let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded)") else {
return (false, "模型名无效")
}
var request = URLRequest(url: url)
request.httpMethod = "GET"
request.timeoutInterval = 10
request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
do {
let (data, response) = try await URLSession.shared.data(for: request)
if let http = response as? HTTPURLResponse {
guard (200...299).contains(http.statusCode) else {
let message = extractErrorMessage(from: data)
GeminiSettings.recordCallStatus(success: false, message: "测试连接 HTTP \(http.statusCode)")
return (false, GeminiError.httpStatus(http.statusCode, message).description)
}
} else {
return (false, "无 HTTP 响应")
}
} catch {
GeminiSettings.recordCallStatus(success: false, message: "测试连接网络失败")
return (false, "网络请求失败（\(error.localizedDescription)）")
}
// 模型存在，再真发一次最小生成——真实问账/识别走的就是这条路。
do {
let json = try await performRequest(
model: model,
body: testConnectionProbeBody(model: model),
timeout: testConnectionProbeTimeoutSeconds
)
_ = try extractText(from: json)
GeminiSettings.recordCallStatus(success: true, message: "测试连接成功（\(model)，已实际生成验证）")
return (true, "连接成功，模型 \(model) 可用（已实际生成验证）")
} catch let error as GeminiError {
GeminiSettings.recordCallStatus(success: false, message: "测试连接生成失败：\(error.description)")
return (false, "模型 \(model) 存在，但实际生成失败：\(error.description)")
} catch {
GeminiSettings.recordCallStatus(success: false, message: "测试连接生成失败：\(error.localizedDescription)")
return (false, "模型 \(model) 存在，但实际生成失败：\(error.localizedDescription)")
}
}

// MARK: 截图识别（结构化 JSON 输出）

public static func recognizeBill(imageData: Data, now: Date = Date()) async throws -> ParsedDraftBill {
let model = GeminiSettings.modelName
// 调用方通常已预处理；这里再兜底一次，避免 Intent/旧入口漏压缩。
let uploadData = GeminiImagePreprocessor.prepareForUpload(imageData)
let mimeType = uploadData.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"

let body: [String: Any] = [
"systemInstruction": ["parts": [["text": recognitionSystemPrompt(now: now)]]],
"contents": [[
"role": "user",
"parts": [
["inline_data": ["mime_type": mimeType, "data": uploadData.base64EncodedString()]],
["text": "请识别这张付款/收款/转账截图，按系统规则输出 JSON。"]
]
]],
"generationConfig": [
"temperature": 0.1,
"responseMimeType": "application/json",
"responseSchema": recognitionResponseSchema(),
"thinkingConfig": thinkingSuppressionConfig(forModel: model)
]
]

let json = try await performRequest(model: model, body: body, timeout: recognitionTimeoutSeconds)
let text = try extractText(from: json)
guard let data = text.data(using:.utf8) else {
throw GeminiError.decodingFailed("文本编码失败")
}
let dto: GeminiBillDTO
do {
dto = try JSONDecoder().decode(GeminiBillDTO.self, from: data)
} catch {
throw GeminiError.decodingFailed(error.localizedDescription)
}
return dto.toDraftBill(now: now)
}

public static func recognitionSystemPrompt(now: Date = Date()) -> String {
let cal = MimiNaturalLanguageDateParser.malaysiaCalendar()
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "zh_CN")
formatter.timeZone = MimiNaturalLanguageDateParser.malaysiaTimeZone
formatter.dateFormat = "yyyy-MM-dd HH:mm"
let todayText = formatter.string(from: now)

let timeFormatter = DateFormatter()
timeFormatter.locale = Locale(identifier: "en_US_POSIX")
timeFormatter.timeZone = MimiNaturalLanguageDateParser.malaysiaTimeZone
timeFormatter.dateFormat = "HH:mm"
let timeOnlyText = timeFormatter.string(from: now)
let currentYear = cal.component(.year, from: now)

let expenseGroups = DefaultCatalog.standardExpenseCategories()
let incomeGroups = DefaultCatalog.standardIncomeCategories()
let expenseLines = expenseGroups.map { group in
let subs = group.subCategories.map(\.name).joined(separator: "、")
return subs.isEmpty ? group.name : "\(group.name)：\(subs)"
}.joined(separator: "\n")
let incomeLines = incomeGroups.map { group in
let subs = group.subCategories.map(\.name).joined(separator: "、")
return subs.isEmpty ? group.name : "\(group.name)：\(subs)"
}.joined(separator: "\n")
let accountNames = DefaultCatalog.defaultAccounts().map(\.name).joined(separator: "、")

return """
你是「咪咪记账」的账单识别引擎，只输出符合 schema 的 JSON，不要输出任何其他文字。

现在时间是 \(todayText)（马来西亚时间 Asia/Kuala_Lumpur，当前年份 \(currentYear) 年）。

防误判铁律：
1. 先判断收支类型 type：
   - 付款 / 消费 / 扣款 / 扫码支付 / DuitNow QR 付款给商家 = expense。
   - DuitNow / 银行 / 电子钱包转给另一个人（个人姓名）= expense（并非 transfer），primaryCategory 选「资金往来」。
   - 收款 / 到账 / 工资 / 退款 / 返现 = income。
   - 只有当截图明确显示是「本人名下两个账户之间互转」或从本人银行账户充值到本人电子钱包（两边账户都属于下方账户列表：\(accountNames)）时才用 transfer，并在 targetAccount 填写转入账户；否则 targetAccount 必须填 null。
2. 金额 amount 只取「实际支付/收款/转账的最终 RM/MYR 主金额」（通常紧邻 Total / Grand Total / Net Total / Amount Paid / 实付金额 / RM 抬头，字号最大或位于结算区最末行）。
   - 若小票同时出现外币金额与括号换算后的 RM 金额（例如 $ 79 (RM38.99) 或 RMB 79 (RM38.99)），一律以 RM 实际扣款金额 38.99 为准。
   - 绝不能误取：Subtotal（折前小计）、Discount（折扣额）、Tax/SST（单独税额）、Cash/Tendered/Change（付现与找零）、账户余额（Balance/Available Balance）、积分（Points）、商品数量（Qty）、单价乘数，更绝不能取手机状态栏的时间或电量百分比数字。
3. 日期时间 occurredAt（最易出错，必须反复核对）输出严格 "yyyy-MM-dd HH:mm"：
   - 截图上的数字斜杠日期一律按马来西亚「日/月/年（DD/MM/YYYY）」理解：例如 08/11/2026 表示 2026 年 11 月 8 日，绝不能读成 8 月 11 日。
   - 英文月份（如 8 Nov 2026、08-Nov-26）准确转为对应公历年月日；若截图只有月日没有年份，默认使用当前年份 \(currentYear)。
   - AM/PM 与上午/下午/晚上 12 小时制必须准确换算成 24 小时制（例如 8:07 PM → 20:07，12:30 PM → 12:30，12:15 AM → 00:15）。
   - 只能读取交易详情或小票正文里的交易时间（Date / Time / Date & Time / Transaction Date / Created）。绝不能抄写手机屏幕最上方状态栏的时钟！
   - 若正文中只有日期没有具体时分，用正文日期 + 当前时分 \(timeOnlyText)；若正文中完全找不到交易日期时间，直接原样输出 \(todayText)，绝不瞎编或套用无关时间戳。
4. counterparty 照截图原文原样填写（英文大写就保持大写）：商家付款填店名/商家全名，个人转账填对方姓名。counterpartyKind：商家/公司填 merchant，个人填 person。
5. account 必须从账户列表中选最接近的一个：\(accountNames)。Touch 'n Go / TNG eWallet / DuitNow(TNG页) 选 TNGewallet；Public Bank / PB engage 选 PBBank；CIMB / Octo 选 CIMB；现金/纸质小票且看不出电子扣款渠道选 现金。
6. 分类必须按商家/消费内容本身判断，只能严格从下面的分类表里选配对好的一级 primaryCategory 与二级 subCategory（该一级无二级时 subCategory 必须填 null，绝不能把其他一级下的二级强行混搭）：
支出分类：
\(expenseLines)
收入分类：
\(incomeLines)
常见判断示例：餐厅/茶室/Mamak/Kopitiam/快餐 → 餐饮-餐厅；咖啡店（Starbucks、ZUS、Luckin）→ 餐饮-咖啡；奶茶/饮料店（Chagee、Tealive、Mixue）→ 餐饮-饮品；油站（Petronas、Shell、Caltex、BHP）加油 → 交通-加油充电；Grab 打车 → 交通-打车叫车（GrabFood 点餐 → 餐饮-外卖外带）；超市/便利店（Jaya Grocer、Village Grocer、AEON、99 Speedmart、Watsons）买日用品 → 购物-生活用品，纯买生鲜蔬菜水果食材 → 餐饮-做饭食材；话费/宽带（Maxis、CelcomDigi、U Mobile、Unifi）→ 住房-话费网费；水电（TNB、Air Selangor）→ 住房-物业水电；房租 → 住房-房租房贷；诊所/药房买药 → 医疗健康-看病买药；转钱给朋友/家人 → 资金往来-人情往来（还款选 资金往来-还款）；收到别人转账 → 收入分类「别人转账」（subCategory 填 null）。
7. 备注 note 按规则生成，简洁一句、不带杂讯：向商家付款 → 「{商家名} 消费」；把钱转给个人 → 「转账给{姓名}」；收到个人转账 → 「{姓名} 转账」；本人账户间转账 → 「账户转账」。名字照截图原文，必须是你真正在截图里读到的商家名/姓名，读不到就把 counterparty 留空字符串，不许用数字碎片、编号或页面边角的零散文字凑名。
8. 认真读细节：先把整个交易详情页从头到尾读完，再逐项填写，不要看到第一个数字就下结论。商家全名以页面上的商家/收款方字段为准（例如 Paid to、Merchant、Recipient、收款方、Payment - 后面的店名抬头），不要拿页面其他位置的零散文字或银行口号（如 Payment Successful）当商家名。
9. 忽略手机状态栏：截图最上方状态栏里的时间、电量百分比、信号、运营商等信息与交易无关，绝不能进入任何字段。
10. 参考号、交易号、Transaction No.、Wallet Ref、Invoice No.、订单号这类长串数字/字母编号，不是金额、不是商家、也不是备注，绝不能填进 amount、counterparty 或 note。
"""
}

public static func recognitionResponseSchema() -> [String: Any] {
let expenseNames = DefaultCatalog.standardExpenseCategories().map(\.name)
let incomeNames = DefaultCatalog.standardIncomeCategories().map(\.name)
let allPrimary = expenseNames + incomeNames
let allSubs = (DefaultCatalog.standardExpenseCategories() + DefaultCatalog.standardIncomeCategories())
.flatMap { $0.subCategories.map(\.name)}
let accountNames = DefaultCatalog.defaultAccounts().map(\.name)
return [
"type": "OBJECT",
"properties": [
"type": ["type": "STRING", "enum": ["expense", "income", "transfer"]],
"amount": ["type": "NUMBER"],
"counterparty": ["type": "STRING"],
"counterpartyKind": ["type": "STRING", "enum": ["merchant", "person"]],
"account": ["type": "STRING", "enum": accountNames],
"targetAccount": ["type": "STRING", "enum": accountNames, "nullable": true],
"primaryCategory": ["type": "STRING", "enum": allPrimary],
"subCategory": ["type": "STRING", "enum": allSubs, "nullable": true],
"occurredAt": ["type": "STRING"],
"note": ["type": "STRING"]
],
"required": ["type", "amount", "counterparty", "counterpartyKind", "account", "primaryCategory", "subCategory", "occurredAt", "note"]
]
}

// MARK: 问账（问题 + 本地账目上下文）

@MainActor
public static func answerQuestion(_ question: String, store: MimiStore, now: Date = Date()) async throws -> String {
let model = GeminiSettings.modelName
let context = LedgerContextBuilder.buildContext(store: store, question: question, now: now)
let system = LedgerContextBuilder.questionSystemPrompt()
let body: [String: Any] = [
"systemInstruction": ["parts": [["text": system]]],
"contents": [[
"role": "user",
"parts": [["text": "【账目数据】\n\(context)\n\n【我的问题】\n\(question)"]]
]],
"generationConfig": [
"temperature": 0.1,
"thinkingConfig": thinkingSuppressionConfig(forModel: model)
]
]
let json = try await performRequest(model: model, body: body, timeout: chatTimeoutSeconds)
return try extractText(from: json).trimmingCharacters(in:.whitespacesAndNewlines)
}
}
