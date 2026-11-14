import Foundation

// MARK: - 备注格式（本地兜底层）
//
// 规则（用户定）：向商家付款 → 「{商家名} 消费」；转账给个人 → 「转账给{姓名}」；
// 收到个人转账 → 「{姓名} 转账」。名字照截图原文原样。Gemini 给的备注干净时优先用它，
// 否则本地按规则生成，绝不把 OCR/Gemini 的杂讯带进账本。

public enum BillNoteFormatter {
public static func makeNote(
type: TransactionType,
counterparty: String,
counterpartyKind: String,
modelNote: String?
) -> String {
let name = counterparty.trimmingCharacters(in:.whitespacesAndNewlines)
if let modelNote, isCleanNote(modelNote) {
return modelNote.trimmingCharacters(in:.whitespacesAndNewlines)
}
if type == .transfer { return "账户转账" }
guard !name.isEmpty else { return ""}
let isPerson = counterpartyKind.lowercased() == "person"
switch type {
case .expense:
return isPerson ? "转账给\(name)" : "\(name) 消费"
case .income:
return isPerson ? "\(name) 转账" : "\(name) 收入"
case .transfer:
return "账户转账"
}
}

/// 干净备注：一句话、无换行、无链接/百分比杂讯、长度合理。
public static func isCleanNote(_ note: String) -> Bool {
let trimmed = note.trimmingCharacters(in:.whitespacesAndNewlines)
guard !trimmed.isEmpty, trimmed.count <= 30 else { return false}
if trimmed.contains("\n") || trimmed.contains("http") || trimmed.contains("%") {
return false
}
return true
}
}

// MARK: - 金额合理性拦截
//
// 明显误读的金额只进未确认/待确认口径，不走正常入账呈现：
// - 金额 <= 0
// - 金额大得离谱（> RM100,000：本 App 是个人日常记账，单笔付款截图超过十万必是误读）
// - 金额与状态栏电量百分比同值（如把状态栏 "79%" / "$ 79" 当成金额）

public enum BillAmountSanity {
public static let maximumPlausibleAmount: Double = 100_000

public static func isSuspicious(
amount: Double,
sourceText: String? = nil,
draftNote: String? = nil
) -> Bool {
guard amount > 0 else { return true}
if amount > maximumPlausibleAmount { return true}
let intCandidate = amount == amount.rounded() && amount >= 1 && amount <= 100
guard intCandidate else { return false}
let intText = String(Int(amount))
if let sourceText {
if sourceText.contains(intText + "%") {
return true
}
// 状态栏被 OCR 读成 "$ 79" 这类样式、且正文没有真正的 RM 金额与之对应时，视为电量误读。
if sourceText.contains("$ " + intText) && !sourceText.contains("RM" + intText) {
return true
}
}
// 仅当调用方显式传入 draftNote（Gemini 草稿路径）时：
// 电量区间整数 + 空/纯数字备注 → 高度可疑。未传 draftNote 时不启用，避免误伤旧口径。
if let draftNote {
let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
if note.isEmpty { return true}
if note.allSatisfy({ $0.isNumber || $0.isWhitespace }) { return true}
}
return false
}

public static func isSuspicious(draft: ParsedDraftBill) -> Bool {
isSuspicious(amount: draft.amount, sourceText: draft.merchantOrNote, draftNote: draft.merchantOrNote)
}
}

// MARK: - 本地可离线回答的问账（分类表 / VIP / 整月泛问汇总）
//
// 细分类问题（如「餐饮花了多少」）故意返回 nil，交给 Gemini 带账目上下文回答，
// 避免本地整月汇总「抢答」把分类问句答成整月。

public enum LocalBookkeepingAnswerer {
@MainActor
public static func blocks(for trimmed: String, in store: MimiStore) -> [AIChatResponseBlock]? {
if trimmed.contains("分类") && (trimmed.contains("增加") || trimmed.contains("删除") || trimmed.contains("标准") || trimmed.contains("哪些")) {
let expenseRows: [(String, String)] = DefaultCatalog.standardExpenseCategories().map { group in
let subs = group.subCategories.map(\.name).joined(separator: "、")
return (group.name, subs.isEmpty ? "（无二级）" : subs)
}
let incomeRows: [(String, String)] = DefaultCatalog.standardIncomeCategories().map { group in
let subs = group.subCategories.map(\.name).joined(separator: "、")
return (group.name, subs.isEmpty ? "（无二级）" : subs)
}
let customNote = "标准收入分类如下：\n另外你还自建了「家用」「车贷」两个支出分类和「别人转账」这个收入分类 😊\n你可以在左侧菜单 →「分类管理」中随时新增、编辑分类；点右上角 ⋯ 进入排序模式用上下箭头调整顺序。"
return [
.text("小金主，咪咪记账的标准支出分类如下："),
.categoryTable(expenseRows: expenseRows, incomeRows: incomeRows, customNote: customNote)
]
}

if trimmed.contains("退款") {
return [.text("小金主，记退款有两种方式：\n1. 点击原支出账单进入「账单详情」→ 在「添加退款/返现」中填入退款金额，系统会自动抵扣原支出；\n2. 直接记一笔「收入 → 退款返还」分类账单。")]
}
if trimmed.contains("报销") {
return [.text("小金主，你可以在记账时打上「报销」标签，并在「资产管理 → 待报销」卡片中统一查看待报销总额。收到报销款后记入「收入 → 退款返还-报销」即可。")]
}
if trimmed.contains("VIP") || trimmed.contains("会员") {
return [.text("小金主，当前版本已为你永久解锁 Pro / VIP 全部高级权益（无限多账本、AI 智能助手、快捷指令自动截屏记账、分类预算与资产全维图表）🎉")]
}
if trimmed.contains("共享账本") || trimmed.contains("账本") {
return [.text("你可以在首页左上角点击「☰」打开侧边菜单 → 选择「账本管理」创建新账本，或通过「导入导出」一键分享账本数据给家人伴侣。")]
}

if trimmed.contains("多少") || trimmed.contains("统计") || trimmed.contains("分析") || trimmed.contains("复盘") {
// 问句里点名了具体分类 → 交给 Gemini，不返回整月汇总
let categoryNames = (DefaultCatalog.standardExpenseCategories() + DefaultCatalog.standardIncomeCategories()).map(\.name)
if categoryNames.contains(where: { trimmed.contains($0) }) {
return nil
}
let now = Date()
let cal = Calendar(identifier: .gregorian)
let year = cal.component(.year, from: now)
let month = cal.component(.month, from: now)
let monthSpent = store.monthlyExpenseTotal(year: year, month: month)
let monthIncome = store.monthlyIncomeTotal(year: year, month: month)
let count = store.transactions.filter {
$0.type == .expense && $0.includeInStats
&& cal.component(.year, from: $0.date) == year
&& cal.component(.month, from: $0.date) == month
}.count
return [
.spendingSummary(
title: "\(year)年\(month)月 收支复盘",
amount: monthSpent,
count: count,
details: "本月共支出 RM\(String(format: "%.2f", monthSpent))（\(count)笔），总收入 RM\(String(format: "%.2f", monthIncome))，月预算剩余 RM\(String(format: "%.2f", max(0, store.currentLedger.monthlyBudget - monthSpent)))。"
)
]
}

return nil
}
}

// MARK: - 自然语言日期时间解析（Asia/Kuala_Lumpur）
//
// 统一供 AI 记账文本解析、快捷指令与账目日期兜底使用：
// - 支持相对日期：今天/今日/今晚/刚才、昨天/昨日/昨晚、前天/前日、大前天、明天/明日、后天、N天前
// - 支持星期：上周三 / 上礼拜五 / 本周一 / 这周二 / 周三 / 星期四
// - 支持绝对日期：2026年11月8日、2026-11-08、08/11/2026（马来西亚 DD/MM/YYYY）、11月8日、11月8号、8日、8号
// - 支持时间点：早上8点半、晚上8:15、下午3点、20:07、9:54 AM
// - 未提及具体时刻时保留 fallback/now 的时分，不编造无关时间戳

public enum MimiNaturalLanguageDateParser {
public static let malaysiaTimeZone = TimeZone(identifier: "Asia/Kuala_Lumpur") ?? .current

public static func malaysiaCalendar() -> Calendar {
calendar(in: malaysiaTimeZone)
}

public static func calendar(in timeZone: TimeZone = .current) -> Calendar {
var cal = Calendar(identifier: .gregorian)
cal.timeZone = timeZone
cal.locale = Locale(identifier: "zh_CN")
cal.firstWeekday = 2
return cal
}

public struct ParseResult: Equatable, Sendable {
public let date: Date
public let hasExplicitDateOrTime: Bool
public let strippedText: String

public init(date: Date, hasExplicitDateOrTime: Bool, strippedText: String) {
self.date = date
self.hasExplicitDateOrTime = hasExplicitDateOrTime
self.strippedText = strippedText
}
}

public static func parse(
in text: String,
now: Date = Date(),
fallbackDate: Date? = nil,
timeZone: TimeZone = .current
) -> ParseResult {
let cal = calendar(in: timeZone)
let baseline = fallbackDate ?? now
var targetDayStart = cal.startOfDay(for: baseline)
let fallbackComps = cal.dateComponents([.hour, .minute], from: baseline)
var targetHour = fallbackComps.hour ?? 12
var targetMinute = fallbackComps.minute ?? 0

var hasDate = false
var hasTime = false

let normalized = normalizeChineseDateTimeNumerals(text)
let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
var rangesToRemove: [NSRange] = []

// 1. 先解析具体时刻（在剥离「昨晚/今晚」之前保留时段上下文）
if let timeMatch = firstTimeMatch(in: normalized, range: nsRange) {
targetHour = timeMatch.hour
targetMinute = timeMatch.minute
hasTime = true
rangesToRemove.append(timeMatch.range)
}

// 2. 解析绝对日期
if let absMatch = firstAbsoluteDateMatch(in: normalized, range: nsRange, now: now, calendar: cal) {
targetDayStart = absMatch.dayStart
hasDate = true
rangesToRemove.append(absMatch.range)
} else if let weekMatch = firstWeekdayMatch(in: normalized, range: nsRange, now: now, calendar: cal) {
targetDayStart = weekMatch.dayStart
hasDate = true
rangesToRemove.append(weekMatch.range)
} else if let relMatch = firstRelativeDayMatch(in: normalized, range: nsRange, now: now, calendar: cal) {
targetDayStart = relMatch.dayStart
hasDate = true
rangesToRemove.append(relMatch.range)
}

var comps = cal.dateComponents([.year, .month, .day], from: targetDayStart)
comps.hour = targetHour
comps.minute = targetMinute
comps.second = 0
let resolvedDate = cal.date(from: comps) ?? baseline

let stripped = removeRanges(rangesToRemove, from: normalized)
return ParseResult(
date: resolvedDate,
hasExplicitDateOrTime: hasDate || hasTime,
strippedText: stripped
)
}

private static func normalizeChineseDateTimeNumerals(_ text: String) -> String {
var result = text
// 中文月日：如「十一月八日」「十月十二号」
let monthDayPattern = #"(十二|十一|十|九|八|七|六|五|四|三|二|一)月(三十一|三十|二十[一二三四五六七八九]?|十[一二三四五六七八九]?|[一二三四五六七八九])([日号])"#
if let regex = try? NSRegularExpression(pattern: monthDayPattern) {
let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
for match in matches.reversed() {
guard let mRange = Range(match.range(at: 1), in: result),
let dRange = Range(match.range(at: 2), in: result),
let uRange = Range(match.range(at: 3), in: result),
let fullRange = Range(match.range, in: result),
let mVal = parseChineseSmallInt(String(result[mRange])),
let dVal = parseChineseSmallInt(String(result[dRange])) else { continue }
result.replaceSubrange(fullRange, with: "\(mVal)月\(dVal)\(result[uRange])")
}
}

// 中文 N天前：如「两天前」「三天前」
let daysAgoPattern = #"(三十[一]?|二十[一二三四五六七八九]?|十[一二三四五六七八九]?|[一二两三四五六七八九])天前"#
if let regex = try? NSRegularExpression(pattern: daysAgoPattern) {
let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
for match in matches.reversed() {
guard let nRange = Range(match.range(at: 1), in: result),
let fullRange = Range(match.range, in: result),
let nVal = parseChineseSmallInt(String(result[nRange])) else { continue }
result.replaceSubrange(fullRange, with: "\(nVal)天前")
}
}

// 中文时间：如「晚上八点半」「十点二十分」「下午两点」；单字「一」仅在带有半/分/整或时段前缀时转换，避免误伤「买了一点零食」
let timePattern = #"(凌晨|早上|上午|清晨|中午|午间|下午|傍晚|晚上|夜里|昨晚|今晚)?\s*(二十[一二三]?|十[一二三四五六七八九]?|两|[一二三四五六七八九])([点时])(半|整|(?:[一二三四五]?十[一二三四五六七八九]?|[一二三四五六七八九])分?)?"#
if let regex = try? NSRegularExpression(pattern: timePattern) {
let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
for match in matches.reversed() {
guard let hRange = Range(match.range(at: 2), in: result),
let uRange = Range(match.range(at: 3), in: result),
let fullRange = Range(match.range, in: result) else { continue }
let prefix = Range(match.range(at: 1), in: result).map { String(result[$0]) } ?? ""
let hWord = String(result[hRange])
let suffix = Range(match.range(at: 4), in: result).map { String(result[$0]) } ?? ""
if hWord == "一" && prefix.isEmpty && suffix.isEmpty {
continue
}
guard let hVal = parseChineseSmallInt(hWord) else { continue }
var suffixOut = suffix
if !suffix.isEmpty && suffix != "半" && suffix != "整" {
let hasFen = suffix.hasSuffix("分")
let rawMin = hasFen ? String(suffix.dropLast()) : suffix
if let mVal = parseChineseSmallInt(rawMin) {
suffixOut = "\(mVal)" + (hasFen ? "分" : "")
}
}
result.replaceSubrange(fullRange, with: "\(prefix)\(hVal)\(result[uRange])\(suffixOut)")
}
}
return result
}

private static func parseChineseSmallInt(_ text: String) -> Int? {
let t = text.trimmingCharacters(in: .whitespaces)
if t == "两" { return 2 }
if t == "零" || t == "〇" { return 0 }
let digits: [Character: Int] = [
"一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
"六": 6, "七": 7, "八": 8, "九": 9
]
if let single = digits[t.first ?? " "], t.count == 1 {
return single
}
if t == "十" { return 10 }
if t.hasPrefix("十"), t.count == 2, let ones = digits[t.last ?? " "] {
return 10 + ones
}
if t.contains("十") {
let parts = t.components(separatedBy: "十")
guard parts.count == 2, let tens = digits[parts[0].first ?? " "] else { return nil }
let ones = parts[1].isEmpty ? 0 : (digits[parts[1].first ?? " "] ?? -1)
guard ones >= 0 else { return nil }
return tens * 10 + ones
}
return nil
}

private static func firstTimeMatch(in text: String, range: NSRange) -> (hour: Int, minute: Int, range: NSRange)? {
// 点/时 格式：晚上8点半、下午3点15分、9点、今晚10时
let chineseTimePattern = #"(?:(凌晨|早上|上午|清晨|中午|午间|下午|傍晚|晚上|夜里|昨晚|今晚)\s*)?(\d{1,2})\s*(?:点|时)\s*(半|整|(\d{1,2})\s*分?)?"#
if let regex = try? NSRegularExpression(pattern: chineseTimePattern),
let match = regex.firstMatch(in: text, range: range),
let hRange = Range(match.range(at: 2), in: text),
let rawHour = Int(text[hRange]), (0...23).contains(rawHour) {
let period = Range(match.range(at: 1), in: text).map { String(text[$0]) }
let tail = Range(match.range(at: 3), in: text).map { String(text[$0]) } ?? ""
var minute = 0
if tail == "半" {
minute = 30
} else if let mRange = Range(match.range(at: 4), in: text), let parsedMin = Int(text[mRange]), (0...59).contains(parsedMin) {
minute = parsedMin
}
let hour = adjustHourForPeriod(rawHour, period: period, ampm: nil)
return (hour, minute, match.range)
}

// 冒号时间：20:07、9:54 AM、晚上 8:30
let colonPattern = #"(?:(凌晨|早上|上午|清晨|中午|午间|下午|傍晚|晚上|夜里|昨晚|今晚)\s*)?(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*(AM|PM|am|pm))?"#
if let regex = try? NSRegularExpression(pattern: colonPattern),
let match = regex.firstMatch(in: text, range: range),
let hRange = Range(match.range(at: 2), in: text),
let mRange = Range(match.range(at: 3), in: text),
let rawHour = Int(text[hRange]), (0...23).contains(rawHour),
let minute = Int(text[mRange]), (0...59).contains(minute) {
let period = Range(match.range(at: 1), in: text).map { String(text[$0]) }
let ampm = Range(match.range(at: 4), in: text).map { String(text[$0]).uppercased() }
let hour = adjustHourForPeriod(rawHour, period: period, ampm: ampm)
return (hour, minute, match.range)
}

return nil
}

private static func adjustHourForPeriod(_ rawHour: Int, period: String?, ampm: String?) -> Int {
var hour = rawHour
if let ampm {
if ampm == "PM", (1...11).contains(hour) { hour += 12 }
if ampm == "AM", hour == 12 { hour = 0 }
return hour
}
if let period {
if ["下午", "傍晚", "晚上", "夜里", "昨晚", "今晚"].contains(period), (1...11).contains(hour) {
hour += 12
} else if ["中午", "午间"].contains(period), (1...5).contains(hour) {
hour += 12
} else if period == "凌晨", hour == 12 {
hour = 0
}
}
return hour
}

private static func firstAbsoluteDateMatch(
in text: String,
range: NSRange,
now: Date,
calendar: Calendar
) -> (dayStart: Date, range: NSRange)? {
let nowComps = calendar.dateComponents([.year, .month, .day], from: now)
let currentYear = nowComps.year ?? 2026
let currentMonth = nowComps.month ?? 11

// yyyy年M月d日/号
let ymdZh = #"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#
if let regex = try? NSRegularExpression(pattern: ymdZh),
let match = regex.firstMatch(in: text, range: range),
let y = intGroup(match, 1, in: text),
let m = intGroup(match, 2, in: text),
let d = intGroup(match, 3, in: text),
let date = makeValidDay(year: y, month: m, day: d, calendar: calendar) {
return (date, match.range)
}

// yyyy-MM-dd 或 yyyy/MM/dd
let ymdSlash = #"(\d{4})[-/](\d{1,2})[-/](\d{1,2})"#
if let regex = try? NSRegularExpression(pattern: ymdSlash),
let match = regex.firstMatch(in: text, range: range),
let y = intGroup(match, 1, in: text),
let m = intGroup(match, 2, in: text),
let d = intGroup(match, 3, in: text),
let date = makeValidDay(year: y, month: m, day: d, calendar: calendar) {
return (date, match.range)
}

// 马来西亚 DD/MM/YYYY 或 DD-MM-YYYY
let dmySlash = #"(?<!\d)(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?!\d)"#
if let regex = try? NSRegularExpression(pattern: dmySlash),
let match = regex.firstMatch(in: text, range: range),
let first = intGroup(match, 1, in: text),
let second = intGroup(match, 2, in: text),
let y = intGroup(match, 3, in: text) {
// 一律按马来西亚 日/月/年 优先；仅当 second > 12 时回退 月/日/年
let day = second <= 12 ? first : second
let month = second <= 12 ? second : first
if let date = makeValidDay(year: y, month: month, day: day, calendar: calendar) {
return (date, match.range)
}
}

// M月d日 / M月d号（默认当前年份）
let mdZh = #"(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#
if let regex = try? NSRegularExpression(pattern: mdZh),
let match = regex.firstMatch(in: text, range: range),
let m = intGroup(match, 1, in: text),
let d = intGroup(match, 2, in: text),
let date = makeValidDay(year: currentYear, month: m, day: d, calendar: calendar) {
return (date, match.range)
}

// 本月具体某天：8号 / 15日
let dayOnlyZh = #"(?:^|(?<=[^\d.]))(\d{1,2})\s*[日号](?!\d)"#
if let regex = try? NSRegularExpression(pattern: dayOnlyZh),
let match = regex.firstMatch(in: text, range: range),
let d = intGroup(match, 1, in: text),
let date = makeValidDay(year: currentYear, month: currentMonth, day: d, calendar: calendar) {
return (date, match.range)
}

return nil
}

private static func firstWeekdayMatch(
in text: String,
range: NSRange,
now: Date,
calendar: Calendar
) -> (dayStart: Date, range: NSRange)? {
let pattern = #"(上周|上星期|上礼拜|这周|本周|周|星期|礼拜)([一二三四五六日天1-7])"#
guard let regex = try? NSRegularExpression(pattern: pattern),
let match = regex.firstMatch(in: text, range: range),
let pRange = Range(match.range(at: 1), in: text),
let wRange = Range(match.range(at: 2), in: text) else {
return nil
}
let prefix = String(text[pRange])
let weekdayToken = String(text[wRange])
let targetOffsetFromMonday: Int
switch weekdayToken {
case "一", "1": targetOffsetFromMonday = 0
case "二", "2": targetOffsetFromMonday = 1
case "三", "3": targetOffsetFromMonday = 2
case "四", "4": targetOffsetFromMonday = 3
case "五", "5": targetOffsetFromMonday = 4
case "六", "6": targetOffsetFromMonday = 5
case "日", "天", "7": targetOffsetFromMonday = 6
default: return nil
}

let todayStart = calendar.startOfDay(for: now)
let systemWeekday = calendar.component(.weekday, from: todayStart) // Sun=1, Mon=2 ... Sat=7
let todayOffsetFromMonday = (systemWeekday + 5) % 7
guard let thisMonday = calendar.date(byAdding: .day, value: -todayOffsetFromMonday, to: todayStart),
let thisWeekTarget = calendar.date(byAdding: .day, value: targetOffsetFromMonday, to: thisMonday) else {
return nil
}

let resolved: Date?
if prefix.hasPrefix("上") {
resolved = calendar.date(byAdding: .day, value: -7, to: thisWeekTarget)
} else if prefix == "这周" || prefix == "本周" {
resolved = thisWeekTarget
} else {
// 裸说「周三/星期三」：若本周该天已过或就是今天，取本周；若尚未到来，默认指最近刚过去的上一周该天
resolved = thisWeekTarget > todayStart
? calendar.date(byAdding: .day, value: -7, to: thisWeekTarget)
: thisWeekTarget
}
guard let resolved else { return nil }
return (resolved, match.range)
}

private static func firstRelativeDayMatch(
in text: String,
range: NSRange,
now: Date,
calendar: Calendar
) -> (dayStart: Date, range: NSRange)? {
let daysAgoPattern = #"(\d{1,3})\s*天前"#
if let regex = try? NSRegularExpression(pattern: daysAgoPattern),
let match = regex.firstMatch(in: text, range: range),
let n = intGroup(match, 1, in: text),
let day = calendar.date(byAdding: .day, value: -n, to: calendar.startOfDay(for: now)) {
return (day, match.range)
}

let tokens: [(String, Int)] = [
("大前天", -3),
("前天", -2), ("前日", -2),
("昨天", -1), ("昨日", -1), ("昨晚", -1), ("昨夜", -1),
("今天", 0), ("今日", 0), ("今晚", 0), ("刚才", 0), ("刚刚", 0),
("后天", 2),
("明天", 1), ("明日", 1)
]
let todayStart = calendar.startOfDay(for: now)
for (token, offset) in tokens {
if let swiftRange = text.range(of: token),
let day = calendar.date(byAdding: .day, value: offset, to: todayStart) {
return (day, NSRange(swiftRange, in: text))
}
}
return nil
}

private static func intGroup(_ match: NSTextCheckingResult, _ idx: Int, in text: String) -> Int? {
guard let r = Range(match.range(at: idx), in: text) else { return nil }
return Int(text[r])
}

private static func makeValidDay(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
guard (2000...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else {
return nil
}
var comps = DateComponents()
comps.year = year
comps.month = month
comps.day = day
comps.hour = 0
comps.minute = 0
comps.second = 0
guard let date = calendar.date(from: comps) else { return nil }
// 校验月份与日期未溢出（防止 2 月 30 日滚到 3 月）
let checked = calendar.dateComponents([.year, .month, .day], from: date)
guard checked.year == year, checked.month == month, checked.day == day else {
return nil
}
return date
}

private static func removeRanges(_ ranges: [NSRange], from text: String) -> String {
let valid = ranges.filter { $0.location != NSNotFound && $0.length > 0 }
.sorted { $0.location < $1.location }
guard !valid.isEmpty else {
return text.trimmingCharacters(in: .whitespacesAndNewlines)
}
var merged: [NSRange] = []
for r in valid {
if let last = merged.last, r.location <= last.location + last.length {
let end = max(last.location + last.length, r.location + r.length)
merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
} else {
merged.append(r)
}
}
let mutable = NSMutableString(string: text)
for r in merged.reversed() {
mutable.replaceCharacters(in: r, with: " ")
}
return (mutable as String)
.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
.trimmingCharacters(in: .whitespacesAndNewlines)
}
}

// MARK: - 记账句 / 问账句判别（纯函数）
//
// 拿不准一律按问账处理；只有「无任何疑问标记 + 能解析出至少一笔带金额的草稿」才判为记账句。

public enum BillMessageKind: Equatable, Sendable {
case billDraft
case question
}

public enum BillMessageClassifier {
public static let questionMarkers: [String] = [
"?", "？", "吗", "什么", "多少", "哪", "怎么", "如何",
"查询", "查找", "查看", "查一下", "查查", "帮我查", "看看", "给我看",
"列出", "几笔", "有哪", "超过", "最高", "最低", "最近",
"统计", "分析", "汇总", "总结", "复盘", "对比",
"消费记录", "账单记录", "账单明细",
"为什么", "能不能", "可不可以", "剩多少", "花了多少"
]

public static func classify(_ message: String, draftCount: Int) -> BillMessageKind {
let trimmed = message.trimmingCharacters(in:.whitespacesAndNewlines)
guard !trimmed.isEmpty else { return .question }
if questionMarkers.contains(where: { trimmed.contains($0)}) {
return .question
}
return draftCount > 0 ? .billDraft : .question
}
}

// MARK: - 账目上下文构建（问账用，本地生成，带上限）

public enum LedgerContextBuilder {
/// 相关记录明细上限：最多 30 条。
public static let maxRecentRecords = 30
/// 上下文总字符上限：约 6000 字，超出截断明细部分。
public static let maxCharacters = 6000

public static func questionSystemPrompt() -> String {
"""
你是「咪咪记账」的问账助手，只回答与用户记账数据相关的问题（收支、分类、预算、账户余额、账单查询）。
防误判与防编造规则：
1. 所有数字、日期、笔数与商户备注必须严格来自下方【账目数据】，不许编造、推算或脑补不存在的账单。
2. 必须严格对照【账目数据】第一行给出的「现在时间」来换算相对日期（如今天、昨天、前天、本周、上周、最近3天）和绝对日期（如 11月8日）；每条明细行开头均为 yyyy-MM-dd HH:mm。
3. 【相关账单明细】最多展示最近 \(maxRecentRecords) 笔相关记录；月度总览与本月分类汇总包含全量统计，但若用户询问的某天或某条件需要更早明细且【账目数据】中无法确定完整范围，必须明确说明「现有账目明细仅展示最近 \(maxRecentRecords) 笔，数据不足以完整回答这个问题」，绝不能把不完整的列表当作全量答案。
4. 金额一律用 RM 格式（如 RM38.99），日期写清年月日；收入用 +RM，支出用 -RM，内部转账（⇄）不计入收支。
5. 与记账无关的问题，礼貌说明只能帮忙查账，并提示可以问的问题类型。
6. 回答简洁、准确、条理清晰，用中文。
"""
}

@MainActor
public static func buildContext(
store: MimiStore,
question: String,
now: Date = Date(),
timeZone: TimeZone = .current
) -> String {
let cal = MimiNaturalLanguageDateParser.calendar(in: timeZone)
let year = cal.component(.year, from: now)
let month = cal.component(.month, from: now)
let transactions = store.transactions

var lines: [String] = []
let dateFormatter = DateFormatter()
dateFormatter.locale = Locale(identifier: "zh_CN")
dateFormatter.timeZone = timeZone
dateFormatter.dateFormat = "yyyy年M月d日 EEEE HH:mm"
lines.append("现在时间（\(timeZone.identifier)，马来西亚参考时区 Asia/Kuala_Lumpur）：\(dateFormatter.string(from: now))。")

// 近 6 个月月度汇总
lines.append("【月度收支汇总（近6个月）】")
for line in monthlySummaryLines(transactions: transactions, monthsBack: 6, now: now, timeZone: timeZone) {
lines.append(line)
}

// 本月分类支出汇总
let monthExpenses = transactions.filter {
$0.type == .expense && $0.includeInStats
&& cal.component(.year, from: $0.date) == year
&& cal.component(.month, from: $0.date) == month
}
if !monthExpenses.isEmpty {
var byCategory: [String: Double] = [:]
for tx in monthExpenses {
let primary = tx.categoryPath.components(separatedBy: "-").first ?? tx.categoryPath
byCategory[primary, default: 0] += tx.amount
}
let sorted = byCategory.sorted { $0.value > $1.value}
lines.append("【本月分类支出】")
for (name, total) in sorted {
lines.append("\(name)：\(formatRM(total))")
}
}

// 预算
let budgetTotal = store.monthlyBudgetTotal
let spent = store.monthlyExpenseTotal(year: year, month: month)
lines.append("【预算】本月总预算 \(formatRM(budgetTotal))，已支出 \(formatRM(spent))，剩余 \(formatRM(max(0, budgetTotal - spent)))。")
if !store.categoryBudgets.isEmpty {
let parts = store.categoryBudgets.map { item in
let used = store.categorySpent(for: item.categoryName, year: year, month: month)
return "\(item.categoryName) 剩 \(formatRM(max(0, item.monthlyLimit - used)))/\(formatRM(item.monthlyLimit))"
}
lines.append("分类预算剩余：" + parts.joined(separator: "；"))
}

// 账户余额
if !store.accounts.isEmpty {
let parts = store.accounts.map { "\($0.name) \(formatRM($0.balance))"}
lines.append("【账户余额】" + parts.joined(separator: "；") + "；净资产 \(formatRM(store.netWorth))。")
}

// 相关记录明细（带上限）
let relevant = relevantTransactions(from: transactions, question: question, now: now)
if !relevant.isEmpty {
lines.append("【相关账单明细（最近\(relevant.count)笔）】")
let itemFormatter = DateFormatter()
itemFormatter.locale = Locale(identifier: "en_US_POSIX")
itemFormatter.timeZone = timeZone
itemFormatter.dateFormat = "yyyy-MM-dd HH:mm"
for tx in relevant {
let sign = tx.type == .income ? "+" : (tx.type == .transfer ? "⇄" : "-")
lines.append("\(itemFormatter.string(from: tx.date)) \(tx.categoryPath) \(sign)\(formatRM(tx.amount)) 账户:\(tx.accountName) 备注:\(tx.note)")
}
}

var context = lines.joined(separator: "\n")
if context.count > maxCharacters {
context = String(context.prefix(maxCharacters)) + "\n（数据已按上限截断）"
}
return context
}

/// 纯函数：按月汇总收支，供上下文与单测共用。
public static func monthlySummaryLines(
transactions: [TransactionItem],
monthsBack: Int,
now: Date,
timeZone: TimeZone = .current
) -> [String] {
let cal = MimiNaturalLanguageDateParser.calendar(in: timeZone)
var lines: [String] = []
for offset in 0..<monthsBack {
guard let monthDate = cal.date(byAdding:.month, value: -offset, to: now) else { continue}
let y = cal.component(.year, from: monthDate)
let m = cal.component(.month, from: monthDate)
let inMonth = transactions.filter {
cal.component(.year, from: $0.date) == y && cal.component(.month, from: $0.date) == m
}
guard !inMonth.isEmpty else { continue}
let expense = inMonth.filter { $0.type == .expense && $0.includeInStats}.reduce(0) { $0 + $1.amount}
let income = inMonth.filter { $0.type == .income && $0.includeInStats}.reduce(0) { $0 + $1.amount}
let count = inMonth.filter { $0.includeInStats}.count
lines.append("\(y)年\(m)月：支出 \(formatRM(expense))，收入 \(formatRM(income))，共 \(count) 笔")
}
return lines
}

/// 挑选与问题相关的记录：问题里有分类/二级分类/账户/商家关键词就优先匹配，其次按时间倒序补足，上限 maxRecentRecords。
public static func relevantTransactions(from transactions: [TransactionItem], question: String, now: Date) -> [TransactionItem] {
let sorted = transactions
.filter { $0.includeInStats}
.sorted { $0.date > $1.date}
let allGroups = DefaultCatalog.standardExpenseCategories() + DefaultCatalog.standardIncomeCategories()
let keywords = allGroups.map(\.name)
+ allGroups.flatMap { $0.subCategories.map(\.name) }
+ ["TNG", "TNGewallet", "PBB", "PBBank", "CIMB", "现金"]
let lowerQ = question.lowercased()
let matchedKeywords = keywords.filter { lowerQ.contains($0.lowercased()) }
var picked: [TransactionItem] = []
if !matchedKeywords.isEmpty {
picked = sorted.filter { tx in
let hay = (tx.categoryPath + " " + tx.note + " " + tx.accountName).lowercased()
return matchedKeywords.contains(where: { hay.contains($0.lowercased()) })
}
}
if picked.count < maxRecentRecords {
for tx in sorted where !picked.contains(where: { $0.id == tx.id}) {
picked.append(tx)
if picked.count >= maxRecentRecords { break}
}
}
return Array(picked.prefix(maxRecentRecords))
}

private static func formatRM(_ value: Double) -> String {
"RM" + String(format: "%.2f", value)
}
}
