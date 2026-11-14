import XCTest
@testable import MimiMoneyCore

@MainActor
final class AIEngineTests: XCTestCase {
    // v1.2.1：本地 OCR 解析器已删除。以下用例把旧 OCR 时代的真实截图场景
    // 改用 Gemini 结构化结果（DTO）表达，验证同一条 DTO → 草稿换算路径。

    func testGeminiDraftForTNGSnackScreenshot() {
        let dto = GeminiBillDTO(
            type: "expense",
            amount: 5.90,
            counterparty: "示例商户",
            counterpartyKind: "merchant",
            account: "TNGewallet",
            primaryCategory: "餐饮",
            subCategory: "零食甜品",
            occurredAt: "2026-11-08 16:56",
            note: ""
        )
        let draft = dto.toDraftBill(now: Date())
        XCTAssertEqual(draft.amount, 5.90, accuracy: 0.001)
        XCTAssertTrue(draft.accountDisplayName.contains("TNG"))
        XCTAssertEqual(draft.categoryDisplayName, "餐饮-零食甜品")
        XCTAssertTrue(draft.merchantOrNote.contains("示例商户"))
    }

    func testGeminiDraftForSampleRestaurant() {
        let dto = GeminiBillDTO(
            type: "expense",
            amount: 38.99,
            counterparty: "示例餐厅",
            counterpartyKind: "merchant",
            account: "TNGewallet",
            primaryCategory: "餐饮",
            subCategory: "餐厅",
            occurredAt: "2026-11-10 20:07",
            note: ""
        )
        let draft = dto.toDraftBill(now: Date())
        XCTAssertEqual(draft.amount, 38.99, accuracy: 0.001)
        XCTAssertEqual(draft.type, .expense)
        XCTAssertEqual(draft.merchantOrNote, "示例餐厅 消费")
        XCTAssertEqual(draft.categoryDisplayName, "餐饮-餐厅")
        XCTAssertEqual(draft.accountDisplayName, "TNGewallet")

        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: draft.occurredAt)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 11)
        XCTAssertEqual(comps.day, 10)
        XCTAssertEqual(comps.hour, 20)
        XCTAssertEqual(comps.minute, 7)
    }

    func testGeminiDraftForDuitNowTransferToPerson() {
        let dto = GeminiBillDTO(
            type: "expense",
            amount: 150.0,
            counterparty: "示例联系人",
            counterpartyKind: "person",
            account: "PBBank",
            primaryCategory: "资金往来",
            subCategory: "人情往来",
            occurredAt: "2026-11-08 21:59",
            note: ""
        )
        let draft = dto.toDraftBill(now: Date())
        XCTAssertEqual(draft.amount, 150.0, accuracy: 0.001)
        XCTAssertEqual(draft.accountDisplayName, "PBBank")
        XCTAssertEqual(draft.merchantOrNote, "转账给示例联系人")

        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: draft.occurredAt)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 11)
        XCTAssertEqual(comps.day, 8)
        XCTAssertEqual(comps.hour, 21) // 9 PM -> 21
        XCTAssertEqual(comps.minute, 59)
    }

    func testRecognitionPromptDemandsDetailReading() {
        let prompt = GeminiClient.recognitionSystemPrompt(now: Date())
        XCTAssertTrue(prompt.contains("认真读细节"))
        XCTAssertTrue(prompt.contains("状态栏"))
        XCTAssertTrue(prompt.contains("收款方"))
        XCTAssertTrue(prompt.contains("参考号"))
        XCTAssertTrue(prompt.contains("不许用数字碎片"))
    }

    func testMultiBillNaturalLanguageSentenceSplitting() {
        let engine = MimiAIEngine()
        let bills = engine.parseNaturalLanguageBills("中午吃餐厅花了8.30，TNG娱乐花了28，PBBank加油38.78")
        XCTAssertEqual(bills.count, 3)
        XCTAssertEqual(bills[0].amount, 8.30, accuracy: 0.001)
        XCTAssertEqual(bills[1].amount, 28.00, accuracy: 0.001)
        XCTAssertEqual(bills[1].accountDisplayName, "TNGewallet")
        XCTAssertEqual(bills[2].accountDisplayName, "PBBank")
        XCTAssertEqual(bills[2].amount, 38.78, accuracy: 0.001)
    }

    func testCategoryQuestionReturnsStandardCategoryTable() async {
        let store = MimiStore(inMemory: true)
        let engine = MimiAIEngine()
        let blocks = await engine.handleUserMessage("可以增加或删除某个分类吗？", in: store)
        XCTAssertTrue(blocks.contains(where: {
            if case .categoryTable = $0 { return true }
            return false
        }))
    }

    func testNaturalLanguageDateParserRelativeAndAbsoluteDatesInMalaysiaTimeZone() throws {
        let tz = MimiNaturalLanguageDateParser.malaysiaTimeZone
        var cal = MimiNaturalLanguageDateParser.calendar(in: tz)
        cal.timeZone = tz
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 15, minute: 20)))

        func assertParsed(_ text: String, expectedExplicit: Bool = true, year: Int, month: Int, day: Int, hour: Int, minute: Int, file: StaticString = #filePath, line: UInt = #line) {
            let res = MimiNaturalLanguageDateParser.parse(in: text, now: now, timeZone: tz)
            XCTAssertEqual(res.hasExplicitDateOrTime, expectedExplicit, "explicit mismatch for \(text)", file: file, line: line)
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: res.date)
            XCTAssertEqual(c.year, year, "year mismatch for \(text)", file: file, line: line)
            XCTAssertEqual(c.month, month, "month mismatch for \(text)", file: file, line: line)
            XCTAssertEqual(c.day, day, "day mismatch for \(text)", file: file, line: line)
            XCTAssertEqual(c.hour, hour, "hour mismatch for \(text)", file: file, line: line)
            XCTAssertEqual(c.minute, minute, "minute mismatch for \(text)", file: file, line: line)
        }

        // Date-only phrases preserve now's time-of-day (15:20) instead of inventing 00:00 or random timestamps
        assertParsed("今天午饭 25", year: 2026, month: 11, day: 14, hour: 15, minute: 20)
        assertParsed("昨天吃面 15", year: 2026, month: 11, day: 13, hour: 15, minute: 20)
        assertParsed("前天买水 4", year: 2026, month: 11, day: 12, hour: 15, minute: 20)
        assertParsed("3天前打车 28", year: 2026, month: 11, day: 11, hour: 15, minute: 20)
        assertParsed("上周三聚餐 68", year: 2026, month: 11, day: 4, hour: 15, minute: 20)
        assertParsed("11月8日 晚饭 45", year: 2026, month: 11, day: 8, hour: 15, minute: 20)
        assertParsed("2026年11月8日 早上8点半 早餐 12", year: 2026, month: 11, day: 8, hour: 8, minute: 30)
        assertParsed("08/11/2026 20:07 便利店 19.90", year: 2026, month: 11, day: 8, hour: 20, minute: 7)
        assertParsed("8号 9:54 AM 咖啡 13.5", year: 2026, month: 11, day: 8, hour: 9, minute: 54)
        assertParsed("喝咖啡 12", expectedExplicit: false, year: 2026, month: 11, day: 14, hour: 15, minute: 20)
    }

    func testNaturalLanguageBillsDoNotMisreadDatesOrBrandNumbersAsAmounts() throws {
        let tz = MimiNaturalLanguageDateParser.malaysiaTimeZone
        var cal = MimiNaturalLanguageDateParser.calendar(in: tz)
        cal.timeZone = tz
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 15, minute: 20)))
        let engine = MimiAIEngine()

        let nov8 = engine.parseNaturalLanguageBills("11月8日 午饭 25", now: now, timeZone: tz)
        XCTAssertEqual(nov8.count, 1)
        XCTAssertEqual(nov8[0].amount, 25.0, accuracy: 0.001)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: nov8[0].occurredAt), DateComponents(year: 2026, month: 11, day: 8))

        let lastNight = engine.parseNaturalLanguageBills("昨天晚上8点 宵夜 30", now: now, timeZone: tz)
        XCTAssertEqual(lastNight.count, 1)
        XCTAssertEqual(lastNight[0].amount, 30.0, accuracy: 0.001)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute], from: lastNight[0].occurredAt), DateComponents(year: 2026, month: 11, day: 13, hour: 20, minute: 0))

        let multi = engine.parseNaturalLanguageBills("昨天 午饭 25，咖啡 12", now: now, timeZone: tz)
        XCTAssertEqual(multi.count, 2)
        XCTAssertEqual(multi[0].amount, 25.0, accuracy: 0.001)
        XCTAssertEqual(multi[1].amount, 12.0, accuracy: 0.001)
        XCTAssertEqual(cal.component(.day, from: multi[0].occurredAt), 13)
        XCTAssertEqual(cal.component(.day, from: multi[1].occurredAt), 13)

        let speedmart = engine.parseNaturalLanguageBills("99 Speedmart 18.90", now: now, timeZone: tz)
        XCTAssertEqual(speedmart.count, 1)
        XCTAssertEqual(speedmart[0].amount, 18.90, accuracy: 0.001)
        XCTAssertTrue(speedmart[0].merchantOrNote.contains("99 Speedmart"), "got note: \(speedmart[0].merchantOrNote)")
    }
}
