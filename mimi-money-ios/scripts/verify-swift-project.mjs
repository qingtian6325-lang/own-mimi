import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

function assertFileExists(relPath) {
  const full = path.join(rootDir, relPath);
  if (!fs.existsSync(full)) {
    throw new Error(`Missing required file: mimi-money-ios/${relPath}`);
  }
  return fs.readFileSync(full, 'utf8');
}

function assertContains(content, needle, contextLabel) {
  if (!content.includes(needle)) {
    throw new Error(`Expected [${contextLabel}] to contain: ${needle}`);
  }
}

function checkBalancedBraces(content, relPath) {
  let depth = 0;
  for (const ch of content) {
    if (ch === '{') depth++;
    if (ch === '}') depth--;
    if (depth < 0) {
      throw new Error(`Unbalanced closing brace in ${relPath}`);
    }
  }
  if (depth !== 0) {
    throw new Error(`Unbalanced braces (remaining depth ${depth}) in ${relPath}`);
  }
}

/** Walk Sources and flag APIs that break macOS host unit-test compilation. */
function verifyMacOSHostSafeAPIs() {
  const sourcesRoot = path.join(rootDir, 'Sources');
  const unsafeBare = [
    { re: /\.listStyle\(\.insetGrouped\)/, label: '.listStyle(.insetGrouped) (iOS-only)' },
    { re: /\.keyboardType\(/, label: '.keyboardType (iOS-only)' },
    { re: /\.fullScreenCover\(/, label: '.fullScreenCover (iOS-only)' },
    { re: /\.navigationBarTitleDisplayMode\(/, label: '.navigationBarTitleDisplayMode (iOS-only)' }
  ];
  const findings = [];

  function walk(dir) {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        walk(full);
        continue;
      }
      if (!ent.name.endsWith('.swift')) continue;
      const lines = fs.readFileSync(full, 'utf8').split(/\r?\n/);
      const rel = path.relative(rootDir, full);
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const window = lines.slice(Math.max(0, i - 5), i + 1).join('\n');
        const guarded =
          window.includes('#if os(iOS)') ||
          window.includes('#if canImport(UIKit)');
        for (const { re, label } of unsafeBare) {
          if (re.test(line) && !guarded) {
            findings.push(`${rel}:${i + 1}: unguarded ${label}`);
          }
        }
        // Package platforms macOS(.v14): iOS-17 fallback must use the older
        // confirmationActionName API, not actionName: which needs macOS 15+.
        if (/actionName:\s*\.log/.test(line)) {
          findings.push(
            `${rel}:${i + 1}: actionName: .log requires macOS 15+; use confirmationActionName: .log in the pre-macOS-15 fallback`
          );
        }
      }
    }
  }

  walk(sourcesRoot);
  if (findings.length) {
    throw new Error(`macOS host unsafe APIs:\n- ${findings.join('\n- ')}`);
  }
}

function verifyTask1() {
  const pkg = assertFileExists('Package.swift');
  assertContains(pkg, 'name: "MimiMoney"', 'Package.swift');
  assertContains(pkg, 'name: "MimiMoneyCore"', 'Package.swift');
  assertContains(pkg, 'name: "MimiMoneyApp"', 'Package.swift');
  assertContains(pkg, 'name: "MimiMoneyTests"', 'Package.swift');

  const xtool = assertFileExists('xtool.yml');
  assertContains(xtool, 'version: 1', 'xtool.yml');
  assertContains(xtool, 'bundleID: com.jinghao.mimimoney', 'xtool.yml');
  assertContains(xtool, 'product: MimiMoneyApp', 'xtool.yml');

  const theme = assertFileExists('Sources/MimiMoneyCore/Theme/MimiTheme.swift');
  checkBalancedBraces(theme, 'MimiTheme.swift');
  assertContains(theme, '0x2D5AF0', 'MimiTheme.swift');
  assertContains(theme, '0xE8832E', 'MimiTheme.swift');
  assertContains(theme, '0xF5F6FA', 'MimiTheme.swift');
  assertContains(theme, 'homeHorizontalPadding', 'MimiTheme.swift');
  assertContains(theme, 'cardCornerRadius', 'MimiTheme.swift');
  assertContains(theme, 'askBarHeight', 'MimiTheme.swift');
  assertContains(theme, 'homeCardShadow', 'MimiTheme.swift');
  assertContains(theme, 'drawerWidthFraction', 'MimiTheme.swift');
  assertContains(theme, 'drawerGridIconSize', 'MimiTheme.swift');
  assertContains(theme, 'proBadgeBlueHex', 'MimiTheme.swift');
  assertContains(theme, 'vipGoldHex', 'MimiTheme.swift');
  assertContains(theme, 'calendarDayCellHeight', 'MimiTheme.swift');
  assertContains(theme, 'calendarHorizontalPadding', 'MimiTheme.swift');

  const models = assertFileExists('Sources/MimiMoneyCore/Models/MimiModels.swift');
  checkBalancedBraces(models, 'MimiModels.swift');
  for (const sym of [
    'enum CurrencyCode',
    'enum TransactionType',
    'struct SubCategory',
    'struct CategoryGroup',
    'struct AccountItem',
    'enum AuditActionType',
    'struct AccountAuditLog',
    'struct TransactionItem',
    'struct CategoryBudgetItem',
    'struct LedgerItem',
    'var displayBadgeToken: String'
  ]) {
    assertContains(models, sym, 'MimiModels.swift');
  }

  const catalog = assertFileExists('Sources/MimiMoneyCore/Models/DefaultCatalog.swift');
  checkBalancedBraces(catalog, 'DefaultCatalog.swift');
  for (const catName of [
    '餐饮', '做饭食材', '餐厅', '外卖外带', '咖啡', '饮品', '零食甜品', '酒吧酒水',
    '购物', '服饰鞋包', '美妆护肤', '数码电器', '生活用品', '个护服务', '运费', '二手租借',
    '交通', '公共交通', '打车叫车', '城际出行', '加油充电', '过路停车', '养车', '交通卡充值',
    '住房', '房租房贷', '物业水电', '话费网费', '物业管理费', '装修维修', '家政服务',
    '休闲娱乐', '运动健身', '线下娱乐', '数字娱乐', '旅游度假', '收藏爱好', '订阅会员',
    '医疗健康', '看病买药', '医美齿科', '保健养生', '体检疫苗', '康复陪护',
    '学习办公', '教育学费', '职业培训', '兴趣课程', '图书文具',
    '宠物', '宠物食品', '宠物用品', '宠物医疗', '宠物服务',
    '母婴', '婴儿食品', '母婴用品', '母婴服务',
    '资金往来', '还款', '人情往来',
    '保险', '投资理财', '其他支出', '家用', '车贷',
    '职业收入', '绩效奖金', '津贴补助', '个体经营', '副业兼职', '投资收入', '股息分红', '利息',
    '保险理赔', '退款返还', '返现', '报销', '他人还款', '退税', '礼金收入', '生活费', '其他收入', '二手买卖', '好运收入', '别人转账',
    '现金', 'CIMB', 'TNGewallet', 'PBBank', 'Main Ledger'
  ]) {
    assertContains(catalog, catName, 'DefaultCatalog.swift');
  }

  console.log('Task 1 verified: Package.swift, xtool.yml, MimiTheme, MimiModels, DefaultCatalog all valid');
}

function verifyTask2() {
  const calc = assertFileExists('Sources/MimiMoneyCore/Services/KeypadCalculator.swift');
  checkBalancedBraces(calc, 'KeypadCalculator.swift');
  assertContains(calc, 'public enum KeypadCalculator', 'KeypadCalculator.swift');
  assertContains(calc, 'public static func evaluate(_ expression: String) -> Double', 'KeypadCalculator.swift');

  const budget = assertFileExists('Sources/MimiMoneyCore/Services/DynamicBudgetEngine.swift');
  checkBalancedBraces(budget, 'DynamicBudgetEngine.swift');
  assertContains(budget, 'public enum DynamicBudgetEngine', 'DynamicBudgetEngine.swift');
  assertContains(budget, 'calculateDailyBudget(monthlyBudget: Double, spentBeforeToday: Double, remainingDaysIncludingToday: Int) -> Double', 'DynamicBudgetEngine.swift');
  assertContains(budget, 'buildMonthDayCells', 'DynamicBudgetEngine.swift');

  const store = assertFileExists('Sources/MimiMoneyCore/Services/MimiStore.swift');
  checkBalancedBraces(store, 'MimiStore.swift');
  for (const sym of [
    'public final class MimiStore: ObservableObject',
    'public func addTransaction(',
    'public func updateTransaction(',
    'public func deleteTransaction(',
    'public func updateAccountBalance(',
    'public func monthlyExpenseTotal(',
    'public func resetToDemoData()',
    'public func clearAllDemoTransactions()',
    'public func resetToCleanEmpty()',
    'public func importMimiCSV(',
    'public func exportMimiCSV()',
    'monthStartDay',
    'hasCompletedOnboarding',
    'currentBillingPeriod',
    '.created',
    '.updated',
    '.deleted'
  ]) {
    assertContains(store, sym, 'MimiStore.swift');
  }

  const billing = assertFileExists('Sources/MimiMoneyCore/Services/BillingPeriod.swift');
  checkBalancedBraces(billing, 'BillingPeriod.swift');
  assertContains(billing, 'public enum BillingPeriodEngine', 'BillingPeriod.swift');
  assertContains(billing, 'period(containing', 'BillingPeriod.swift');

  const onboarding = assertFileExists('Sources/MimiMoneyCore/Views/OnboardingGuideView.swift');
  checkBalancedBraces(onboarding, 'OnboardingGuideView.swift');
  assertContains(onboarding, 'public struct OnboardingGuideView: View', 'OnboardingGuideView.swift');

  const csvService = assertFileExists('Sources/MimiMoneyCore/Services/MimiCSVService.swift');
  checkBalancedBraces(csvService, 'MimiCSVService.swift');
  for (const sym of [
    'public enum MimiCSVService',
    'public static func parseMimiCSV(',
    'public static func exportMimiCSV(',
    'public static let standardImportTemplate'
  ]) {
    assertContains(csvService, sym, 'MimiCSVService.swift');
  }
  if (csvService.includes('userExportedCSV') || csvService.includes('151 笔') || csvService.includes('Real Exported')) {
    throw new Error('MimiCSVService.swift must not ship personal backup sample CSV');
  }

  const xlsx = assertFileExists('Sources/MimiMoneyCore/Services/MimiKapiXLSXService.swift');
  checkBalancedBraces(xlsx, 'MimiKapiXLSXService.swift');
  for (const sym of [
    'public enum MimiKapiXLSXService',
    'public static func parseXLSX(',
    'public static func exportXLSX(',
    '收支账单',
    '内部转账'
  ]) {
    assertContains(xlsx, sym, 'MimiKapiXLSXService.swift');
  }

  const pkg = assertFileExists('Package.swift');
  assertContains(pkg, 'CoreXLSX', 'Package.swift');
  assertContains(pkg, 'ZIPFoundation', 'Package.swift');

  console.log('Task 2 verified: KeypadCalculator, DynamicBudgetEngine, MimiCSVService, and MimiStore audit & balance logic valid');
}

function verifyTask3() {
  // v1.2.1：识别改纯 AI，ReceiptOCRService 已删除。改为校验独立出来的
  // ParsedDraftBill 与纯 AI 门面，并断言 Sources 里再无 OCR 残留引用。
  const draftBill = assertFileExists('Sources/MimiMoneyCore/Services/ParsedDraftBill.swift');
  checkBalancedBraces(draftBill, 'ParsedDraftBill.swift');
  assertContains(draftBill, 'public struct ParsedDraftBill', 'ParsedDraftBill.swift');

  const recognizer = assertFileExists('Sources/MimiMoneyCore/Services/SmartReceiptRecognizer.swift');
  checkBalancedBraces(recognizer, 'SmartReceiptRecognizer.swift');
  for (const sym of [
    'public enum ReceiptRecognitionFailure',
    'public static func recognize(imageData:',
    'GroqClient.recognizeBill',
    'GeminiClient.recognizeBill',
    'AIEngineSettings.provider'
  ]) {
    assertContains(recognizer, sym, 'SmartReceiptRecognizer.swift');
  }

  const sourcesDir = path.join(rootDir, 'Sources');
  const stack = [sourcesDir];
  while (stack.length > 0) {
    const dir = stack.pop();
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.name.endsWith('.swift')) {
        const text = fs.readFileSync(full, 'utf8');
        if (text.includes('ReceiptOCRService') || text.includes('import Vision')) {
          throw new Error(`OCR remnant found in ${full} (v1.2.1 removed OCR entirely)`);
        }
      }
    }
  }

  const ai = assertFileExists('Sources/MimiMoneyCore/Services/MimiAIEngine.swift');
  checkBalancedBraces(ai, 'MimiAIEngine.swift');
  for (const sym of [
    'public enum AIChatResponseBlock',
    'public final class MimiAIEngine: ObservableObject',
    'public func parseNaturalLanguageBills(',
    'public func handleUserMessage(',
    'LocalBookkeepingAnswerer.blocks',
    'GeminiClient.answerQuestion',
    'preferredAccount(from:'
  ]) {
    assertContains(ai, sym, 'MimiAIEngine.swift');
  }

  const helpers = assertFileExists('Sources/MimiMoneyCore/Services/BookkeepingAIHelpers.swift');
  checkBalancedBraces(helpers, 'BookkeepingAIHelpers.swift');
  for (const sym of [
    'public enum LocalBookkeepingAnswerer',
    'MimiNaturalLanguageDateParser',
    'Asia/Kuala_Lumpur',
    '咪咪记账',
    '标准收入分类如下',
    '另外你还自建了「家用」「车贷」两个支出分类和「别人转账」这个收入分类',
    'public enum BillAmountSanity',
    'isSuspicious(draft:'
  ]) {
    assertContains(helpers, sym, 'BookkeepingAIHelpers.swift');
  }

  const gemini = assertFileExists('Sources/MimiMoneyCore/Services/GeminiClient.swift');
  checkBalancedBraces(gemini, 'GeminiClient.swift');
  for (const sym of [
    'public enum GeminiClient',
    'targetAccountId: resolvedTargetId',
    'GeminiImagePreprocessor.prepareForUpload'
  ]) {
    assertContains(gemini, sym, 'GeminiClient.swift');
  }

  const groq = assertFileExists('Sources/MimiMoneyCore/Services/GroqClient.swift');
  checkBalancedBraces(groq, 'GroqClient.swift');
  for (const sym of [
    'public enum GroqClient',
    'qwen/qwen3.8-27b',
    'image_url',
    'recognizeBill',
    'answerQuestion'
  ]) {
    assertContains(groq, sym, 'GroqClient.swift');
  }

  const provider = assertFileExists('Sources/MimiMoneyCore/Services/AIEngineProvider.swift');
  checkBalancedBraces(provider, 'AIEngineProvider.swift');
  assertContains(provider, 'case groq', 'AIEngineProvider.swift');

  assertContains(recognizer, 'GeminiImagePreprocessor', 'SmartReceiptRecognizer.swift');

  console.log('Task 3 verified: ParsedDraftBill, SmartReceiptRecognizer, Gemini/Groq clients, LocalBookkeepingAnswerer and MimiAIEngine valid');
}

function verifyTask4() {
  const shortcuts = assertFileExists('Sources/MimiMoneyCore/Intents/MimiShortcuts.swift');
  checkBalancedBraces(shortcuts, 'MimiShortcuts.swift');
  for (const sym of [
    'public struct ShortcutExecutionOutcome',
    'public enum ShortcutActionCoordinator',
    'public static func recordRecognizedDraft(',
    'public static func markForInAppModification(',
    'public static func handleIncomingURL(',
    'mimimoney://edit-bill?id=',
    'public struct ScanScreenshotIntent',
    'public struct OpenBillForEditIntent',
    'public struct ConfirmBillIntent',
    'public struct MimiAppShortcutsProvider',
    'public struct ScreenshotResultSnippetView',
    '已识别记录以上信息，打开「咪咪记账」查看更多',
    '修改 (View)',
    '确认 (Got it)'
  ]) {
    assertContains(shortcuts, sym, 'MimiShortcuts.swift');
  }

  const tests = assertFileExists('Tests/MimiMoneyTests/ShortcutIntentTests.swift');
  checkBalancedBraces(tests, 'ShortcutIntentTests.swift');
  assertContains(tests, 'testShortcutRecognizeAndConfirmSavesDirectly', 'ShortcutIntentTests.swift');
  assertContains(tests, 'testShortcutModifyButtonDeepLinksIntoAppBillEditor', 'ShortcutIntentTests.swift');

  console.log('Task 4 verified: ShortcutActionCoordinator, AppIntents, and DeepLink routing valid');
}

function verifyTask5() {
  const sticker = assertFileExists('Sources/MimiMoneyCore/Components/MimiStickerIconView.swift');
  checkBalancedBraces(sticker, 'MimiStickerIconView.swift');
  assertContains(sticker, 'public struct MimiStickerIconView: View', 'MimiStickerIconView.swift');

  const home = assertFileExists('Sources/MimiMoneyCore/Views/HomeRecordView.swift');
  checkBalancedBraces(home, 'HomeRecordView.swift');
  for (const label of [
    'public struct HomeRecordView: View',
    '月预算剩余',
    '今日可用',
    '分类预算',
    '净资产',
    '30天趋势',
    '记录明细',
    '任何事情都能问我',
    '删除成功',
    'ForEach(groups, id: \\.date)'
  ]) {
    assertContains(home, label, 'HomeRecordView.swift');
  }
  // Swipe-delete must animate removal with withAnimation (not delete-then-animate).
  assertContains(home, 'store.deleteTransaction(id: id)', 'HomeRecordView.swift');
  if (!home.includes('withAnimation(MimiMotion.quick') || !home.includes('store.deleteTransaction')) {
    throw new Error('HomeRecordView swipe-delete must withAnimation around deleteTransaction');
  }

  const motion = assertFileExists('Sources/MimiMoneyCore/Theme/MimiMotion.swift');
  checkBalancedBraces(motion, 'MimiMotion.swift');
  assertContains(motion, 'pageDuration: TimeInterval = 0.18', 'MimiMotion.swift');
  assertContains(motion, 'case .page: return 0.10', 'MimiMotion.swift');
  const motionTests = assertFileExists('Tests/MimiMoneyTests/MimiMotionTests.swift');
  assertContains(motionTests, 'testHandoffDelaysAreSnappyNotHalfBeatLate', 'MimiMotionTests.swift');
  assertContains(motionTests, 'testDeleteRemovesRowImmediatelyBeforePersist', 'MimiMotionTests.swift');

  const drawer = assertFileExists('Sources/MimiMoneyCore/Views/SideDrawerMenuView.swift');
  checkBalancedBraces(drawer, 'SideDrawerMenuView.swift');
  for (const label of [
    'public struct SideDrawerMenuView: View',
    '记录天数',
    '总记录',
    '连续天数',
    '更多功能',
    '快捷记账',
    '图表统计',
    '资产管理',
    '账本管理',
    '预算管理',
    '小组件',
    '分类管理',
    '标签管理',
    '导入导出',
    '自动记账',
    '定时记账',
    '设置',
    'gearshape',
    'Pro',
    'VIP',
    '今'
  ]) {
    assertContains(drawer, label, 'SideDrawerMenuView.swift');
  }

  const cal = assertFileExists('Sources/MimiMoneyCore/Views/AllRecordsCalendarView.swift');
  checkBalancedBraces(cal, 'AllRecordsCalendarView.swift');
  for (const label of [
    'public struct AllRecordsCalendarView: View',
    '全部记录',
    '回今天',
    '月支出',
    '月收入',
    '日均支出',
    '收支分析',
    '支出分析',
    '收入多',
    '支出多',
    '任何事都能问我'
  ]) {
    assertContains(cal, label, 'AllRecordsCalendarView.swift');
  }

  console.log('Task 5 verified: Home, SideDrawer, StickerIcon, and AllRecordsCalendar views complete');
}

function verifyTask6() {
  const recordSheet = assertFileExists('Sources/MimiMoneyCore/Views/RecordAndAISheetView.swift');
  checkBalancedBraces(recordSheet, 'RecordAndAISheetView.swift');
  for (const label of [
    'public struct RecordAndAISheetView: View',
    '手动记账',
    'AI 助手',
    '支出',
    '收入',
    '转账',
    '再记',
    '完成',
    '任何事情都能问我',
    '咪咪思考中',
    '内容由AI生成',
    'onSwitchToAIOverlay',
    'intendedInitialTab',
    'presentationID',
    'applyIntendedTab',
    'task(id: presentationID)',
    'suppressSheetDismiss',
    'presentationContentInteraction(.scrolls)',
    'BookkeepingSheetSwipePolicy',
    'tabViewStyle(.page',
    'presentationDetents([.large])',
    'chatBottomAnchorID'
  ]) {
    assertContains(recordSheet, label, 'RecordAndAISheetView.swift');
  }
  // v1.3.16: bookkeeping must open full-height, not half-sheet over 记录页.
  if (recordSheet.includes('presentationDetents([.medium, .large])')) {
    throw new Error(
      'RecordAndAISheetView.swift: do not use [.medium, .large] — opens as half-sheet; use [.large]'
    );
  }
  // v1.3.16 bill-detail category picker (标准分类 sheet).
  const billDetailCategory = assertFileExists('Sources/MimiMoneyCore/Views/BillDetailSheetView.swift');
  assertContains(billDetailCategory, 'showCategoryPicker', 'BillDetailSheetView.swift');
  assertContains(billDetailCategory, 'BillCategoryPickerSheet', 'BillDetailSheetView.swift');
  const categoryPicker = assertFileExists('Sources/MimiMoneyCore/Views/BillCategoryPickerSheet.swift');
  checkBalancedBraces(categoryPicker, 'BillCategoryPickerSheet.swift');
  for (const label of [
    '标准分类',
    '分类编辑',
    '确认',
    'BillCategorySelection',
    'LazyVGrid'
  ]) {
    assertContains(categoryPicker, label, 'BillCategoryPickerSheet.swift');
  }
  const categorySelection = assertFileExists('Sources/MimiMoneyCore/Services/BillCategorySelection.swift');
  assertContains(categorySelection, 'resolvedPath', 'BillCategorySelection.swift');
  const categorySelectionTests = assertFileExists('Tests/MimiMoneyTests/BillCategorySelectionTests.swift');
  assertContains(categorySelectionTests, 'testParsesPrimaryAndSecondaryPath', 'BillCategorySelectionTests.swift');
  // v1.3.17: leave-to-save (no explicit 保存修改); invalid amount keeps previousValidAmount.
  assertContains(billDetailCategory, 'autoSaveOnLeave', 'BillDetailSheetView.swift');
  assertContains(billDetailCategory, 'BillDetailEditCommit', 'BillDetailSheetView.swift');
  assertContains(billDetailCategory, 'previousValidAmount', 'BillDetailSheetView.swift');
  assertContains(billDetailCategory, '.onDisappear', 'BillDetailSheetView.swift');
  if (billDetailCategory.includes('保存修改')) {
    throw new Error(
      'BillDetailSheetView.swift: remove explicit 保存修改 — persist on leave via autoSaveOnLeave'
    );
  }
  const editCommit = assertFileExists('Sources/MimiMoneyCore/Services/BillDetailEditCommit.swift');
  assertContains(editCommit, 'resolvedAmount', 'BillDetailEditCommit.swift');
  assertContains(editCommit, 'previousValidAmount', 'BillDetailEditCommit.swift');
  const editCommitTests = assertFileExists('Tests/MimiMoneyTests/BillDetailEditCommitTests.swift');
  assertContains(editCommitTests, 'testEmptyAmountKeepsPreviousValid', 'BillDetailEditCommitTests.swift');
  assertContains(editCommitTests, 'testZeroAmountKeepsPreviousValid', 'BillDetailEditCommitTests.swift');
  // v1.3.18: calendar-style date/time sheet (日期 + 回今天 + 时间胶囊 + 确认).
  const datePickerSheet = assertFileExists('Sources/MimiMoneyCore/Components/MimiDatePickerSheet.swift');
  checkBalancedBraces(datePickerSheet, 'MimiDatePickerSheet.swift');
  for (const label of [
    'MimiDatePickerLogic',
    '回今天',
    '确认',
    '时间',
    'showTimeWheel',
    'datePickerStyle(.wheel)',
    'expenseBlue'
  ]) {
    assertContains(datePickerSheet, label, 'MimiDatePickerSheet.swift');
  }
  if (datePickerSheet.includes('timeStepper')) {
    throw new Error(
      'MimiDatePickerSheet.swift: remove +/- time steppers — use gray HH:mm capsule + wheel overlay'
    );
  }
  if (!/#if\s+os\(iOS\)[\s\S]{0,120}datePickerStyle\(\.wheel\)/.test(datePickerSheet)) {
    throw new Error(
      'MimiDatePickerSheet.swift: datePickerStyle(.wheel) must be guarded with #if os(iOS) so macOS swift test compiles'
    );
  }
  assertContains(billDetailCategory, 'MimiDateFieldButton', 'BillDetailSheetView.swift');
  assertContains(billDetailCategory, 'title: "日期"', 'BillDetailSheetView.swift');
  assertContains(recordSheet, 'MimiDatePickerSheet', 'RecordAndAISheetView.swift');
  assertContains(recordSheet, 'title: "日期"', 'RecordAndAISheetView.swift');
  const calendarView = assertFileExists('Sources/MimiMoneyCore/Views/AllRecordsCalendarView.swift');
  assertContains(calendarView, 'showMonthPickerSheet', 'AllRecordsCalendarView.swift');
  assertContains(calendarView, 'MimiDatePickerSheet', 'AllRecordsCalendarView.swift');
  const datePickerLogicTests = assertFileExists('Tests/MimiMoneyTests/MimiDatePickerLogicTests.swift');
  assertContains(datePickerLogicTests, 'testCombiningKeepsTimeFromSource', 'MimiDatePickerLogicTests.swift');
  assertContains(datePickerLogicTests, 'testDaysInMonthSundayFirstLeadingPads', 'MimiDatePickerLogicTests.swift');
  // Regression: PageTabViewStyle is unavailable on macOS host unit tests.
  if (!/#if\s+os\(iOS\)[\s\S]{0,240}tabViewStyle\(\.page/.test(recordSheet)) {
    throw new Error(
      'RecordAndAISheetView.swift: .tabViewStyle(.page) must be inside #if os(iOS) for macOS swift test'
    );
  }

  // v1.3.19: categorized budgets sorted by usage % high → low.
  const budgetUsageSort = assertFileExists('Sources/MimiMoneyCore/Services/CategoryBudgetUsageSort.swift');
  assertContains(budgetUsageSort, 'sortedByUsageDescending', 'CategoryBudgetUsageSort.swift');
  assertContains(budgetUsageSort, 'usageRatio', 'CategoryBudgetUsageSort.swift');
  const budgetUsageSortTests = assertFileExists('Tests/MimiMoneyTests/CategoryBudgetUsageSortTests.swift');
  assertContains(budgetUsageSortTests, 'testSortsHighestUsagePercentFirst', 'CategoryBudgetUsageSortTests.swift');
  const budgetMgmt = assertFileExists('Sources/MimiMoneyCore/Views/BudgetManagementView.swift');
  assertContains(budgetMgmt, 'sortedCategoryBudgetsByUsage', 'BudgetManagementView.swift');
  assertContains(budgetMgmt, 'CategoryBudgetUsageSort.sortedByUsageDescending', 'BudgetManagementView.swift');
  const homeRecord = assertFileExists('Sources/MimiMoneyCore/Views/HomeRecordView.swift');
  assertContains(homeRecord, 'sortedCategoryBudgetsByUsage', 'HomeRecordView.swift');
  assertContains(homeRecord, 'CategoryBudgetUsageSort.sortedByUsageDescending', 'HomeRecordView.swift');

  const aiOverlay = assertFileExists('Sources/MimiMoneyCore/Views/MimiAIAskOverlayView.swift');
  checkBalancedBraces(aiOverlay, 'MimiAIAskOverlayView.swift');
  for (const label of [
    'public struct MimiAIAskOverlayView: View',
    '记账查账，问问题',
    '来记笔账吧',
    '发消息或按住说话',
    '任何事情都能问我',
    '手动记账',
    '咪咪思考中',
    'exampleQuestions',
    'bottomAnchorID'
  ]) {
    assertContains(aiOverlay, label, 'MimiAIAskOverlayView.swift');
  }

  const root = assertFileExists('Sources/MimiMoneyCore/Views/MimiRootContainerView.swift');
  assertContains(root, 'showAIAskOverlay', 'MimiRootContainerView.swift');
  assertContains(root, 'MimiAIAskOverlayView', 'MimiRootContainerView.swift');

  const aiEngine = assertFileExists('Sources/MimiMoneyCore/Services/MimiAIEngine.swift');
  for (const label of [
    '查询本月单笔消费超过200块的账单',
    '查看我最近3天的消费记录',
    '我最近一次购物买了什么'
  ]) {
    assertContains(aiEngine, label, 'MimiAIEngine.swift');
  }

  const billDetail = assertFileExists('Sources/MimiMoneyCore/Views/BillDetailSheetView.swift');
  checkBalancedBraces(billDetail, 'BillDetailSheetView.swift');
  for (const label of [
    'public struct BillDetailSheetView: View',
    '账单详情',
    '实付金额',
    '分类',
    '备注',
    '账单时间',
    '付款账户',
    '所属账本',
    '添加优惠',
    '添加退款/返现',
    '交易方'
  ]) {
    assertContains(billDetail, label, 'BillDetailSheetView.swift');
  }

  console.log('Task 6 verified: RecordAndAISheetView and BillDetailSheetView complete');
}

function verifyTask7() {
  const stats = assertFileExists('Sources/MimiMoneyCore/Views/MimiStatsView.swift');
  checkBalancedBraces(stats, 'MimiStatsView.swift');
  for (const label of [
    'public struct MimiStatsView: View',
    '支出分类构成',
    '本月支出',
    '每日支出趋势',
    '单笔支出排行',
    '账单汇总',
    '总计',
    '日均',
    '本周结余'
  ]) {
    assertContains(stats, label, 'MimiStatsView.swift');
  }

  const assetsNav = assertFileExists('Sources/MimiMoneyCore/Services/AssetsAccountNavigation.swift');
  checkBalancedBraces(assetsNav, 'AssetsAccountNavigation.swift');
  for (const label of [
    'public struct AssetsAccountNavigationState',
    'case back',
    'dismissAssetsOverlay',
    'case openEntry',
    'case dismissEntry',
    'presentationID',
    'struct AccountEntryRoute',
    'AccountEntrySheetBootstrap',
    'tabAfterExpenseDismissThenTransfer',
    'tabAfterTransferDismissThenExpense'
  ]) {
    assertContains(assetsNav, label, 'AssetsAccountNavigation.swift');
  }

  const assetsDetail = assertFileExists('Sources/MimiMoneyCore/Views/AssetsAndAccountDetailView.swift');
  assertContains(assetsDetail, 'AccountEntrySheetBootstrap.intendedTab', 'AssetsAndAccountDetailView.swift');
  assertContains(assetsDetail, 'presentationID: route.presentationID', 'AssetsAndAccountDetailView.swift');
  assertContains(assetsDetail, '.id(route.presentationID)', 'AssetsAndAccountDetailView.swift');

  const appVersion = assertFileExists('Sources/MimiMoneyCore/Services/AppVersionInfo.swift');
  for (const label of [
    'CFBundleShortVersionString',
    'CFBundleVersion',
    'settingsFooterLine',
    '版本 '
  ]) {
    assertContains(appVersion, label, 'AppVersionInfo.swift');
  }

  const swipePolicy = assertFileExists('Sources/MimiMoneyCore/Services/BookkeepingSheetSwipePolicy.swift');
  checkBalancedBraces(swipePolicy, 'BookkeepingSheetSwipePolicy.swift');
  for (const label of [
    'BookkeepingSheetSwipePolicy',
    'isHorizontalDominant',
    'isVerticalDominant',
    'neighbor'
  ]) {
    assertContains(swipePolicy, label, 'BookkeepingSheetSwipePolicy.swift');
  }
  const swipePolicyTests = assertFileExists('Tests/MimiMoneyTests/BookkeepingSheetSwipePolicyTests.swift');
  checkBalancedBraces(swipePolicyTests, 'BookkeepingSheetSwipePolicyTests.swift');
  assertContains(swipePolicyTests, 'testHorizontalDominantBlocksDiagonalSheetDismissSteal', 'BookkeepingSheetSwipePolicyTests.swift');

  // v1.3.15 — system InfoPlist display name + in-app language preference / String Catalog
  const languagePref = assertFileExists('Sources/MimiMoneyCore/Services/AppLanguagePreference.swift');
  checkBalancedBraces(languagePref, 'AppLanguagePreference.swift');
  for (const label of [
    'AppLanguagePreference',
    'AppLanguageStore',
    'MimiL10n',
    'mimi_app_language_preference',
    'effectiveLocale',
    'mimiModule'
  ]) {
    assertContains(languagePref, label, 'AppLanguagePreference.swift');
  }
  assertContains(languagePref, 'AppleLanguages', 'AppLanguagePreference.swift'); // mentioned as NOT used
  // Launch-crash hotfix: never call generated Bundle.module from app UI paths.
  if (/\bbundle:\s*\.module\b/.test(languagePref) || /\bBundle\.module\b/.test(languagePref)) {
    throw new Error('AppLanguagePreference.swift must use Bundle.mimiModule, not Bundle.module');
  }
  const resourceBundle = assertFileExists('Sources/MimiMoneyCore/Services/MimiResourceBundle.swift');
  checkBalancedBraces(resourceBundle, 'MimiResourceBundle.swift');
  assertContains(resourceBundle, 'MimiMoney_MimiMoneyCore', 'MimiResourceBundle.swift');
  assertContains(resourceBundle, 'mimiModule', 'MimiResourceBundle.swift');
  const resourceBundleTests = assertFileExists('Tests/MimiMoneyTests/MimiResourceBundleTests.swift');
  checkBalancedBraces(resourceBundleTests, 'MimiResourceBundleTests.swift');
  assertContains(resourceBundleTests, 'testMimiModuleNeverFatals', 'MimiResourceBundleTests.swift');
  // Sources must not use fatal Bundle.module for localization (except comments in MimiResourceBundle).
  const sourcesRootForModule = path.join(rootDir, 'Sources');
  function walkSwift(dir, fn) {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) walkSwift(full, fn);
      else if (ent.name.endsWith('.swift')) fn(full);
    }
  }
  const moduleHits = [];
  walkSwift(sourcesRootForModule, (full) => {
    const rel = path.relative(rootDir, full);
    if (rel.endsWith('MimiResourceBundle.swift')) return;
    const text = fs.readFileSync(full, 'utf8');
    const lines = text.split(/\r?\n/);
    lines.forEach((line, i) => {
      if (line.trimStart().startsWith('//')) return;
      if (/\bbundle:\s*\.module\b/.test(line) || /(?<!mimi)Bundle\.module\b/.test(line)) {
        moduleHits.push(`${rel}:${i + 1}`);
      }
    });
  });
  if (moduleHits.length) {
    throw new Error(`Sources still reference Bundle.module (use .mimiModule):\n${moduleHits.join('\n')}`);
  }
  const xcstrings = assertFileExists('Sources/MimiMoneyCore/Resources/Localizable.xcstrings');
  assertContains(xcstrings, '"咪咪记账"', 'Localizable.xcstrings');
  assertContains(xcstrings, 'Mimi Money', 'Localizable.xcstrings');
  assertContains(xcstrings, '"语言"', 'Localizable.xcstrings');
  assertContains(xcstrings, 'Follow System', 'Localizable.xcstrings');
  assertFileExists('Resources/zh-Hans.lproj/InfoPlist.strings');
  assertFileExists('Resources/en.lproj/InfoPlist.strings');
  const infoZh = assertFileExists('Resources/zh-Hans.lproj/InfoPlist.strings');
  const infoEn = assertFileExists('Resources/en.lproj/InfoPlist.strings');
  assertContains(infoZh, '咪咪记账', 'zh-Hans InfoPlist.strings');
  assertContains(infoEn, 'Mimi Money', 'en InfoPlist.strings');
  const packageSwift = assertFileExists('Package.swift');
  assertContains(packageSwift, '.process("Resources")', 'Package.swift resources');
  const settingsView = assertFileExists('Sources/MimiMoneyCore/Views/SettingsAndShortcutsGuideView.swift');
  assertContains(settingsView, 'languageStore', 'SettingsAndShortcutsGuideView.swift');
  assertContains(settingsView, 'AppLanguagePreference', 'SettingsAndShortcutsGuideView.swift');
  const languageTests = assertFileExists('Tests/MimiMoneyTests/AppLanguagePreferenceTests.swift');
  checkBalancedBraces(languageTests, 'AppLanguagePreferenceTests.swift');
  assertContains(languageTests, 'testPersistsPreference', 'AppLanguagePreferenceTests.swift');
  // CI must search the correct SPM bundle name (Package_Target).
  const workflowPath = path.join(rootDir, '..', '.github', 'workflows', 'build-mimi-ios.yml');
  if (!fs.existsSync(workflowPath)) {
    throw new Error('Missing .github/workflows/build-mimi-ios.yml');
  }
  const workflow = fs.readFileSync(workflowPath, 'utf8');
  assertContains(workflow, 'MimiMoney_MimiMoneyCore.bundle', 'build-mimi-ios.yml');
  if (!workflow.includes('SPM resource bundle not found') && !workflow.includes('resource bundle not found')) {
    throw new Error('build-mimi-ios.yml must fail the build when the SPM resource bundle is missing');
  }

  const assets = assertFileExists('Sources/MimiMoneyCore/Views/AssetsAndAccountDetailView.swift');
  checkBalancedBraces(assets, 'AssetsAndAccountDetailView.swift');
  for (const label of [
    'public struct AssetsAndAccountDetailView: View',
    'AssetsAccountNavigationState',
    'dispatch(.back)',
    'entryRouteBinding',
    '净资产',
    '待报销',
    '账户详情',
    '记账',
    '转账',
    '明细',
    '账单',
    '余额:',
    '初始余额',
    'accountInitialBalanceFooter',
    'AccountInitialBalanceRowBuilder'
  ]) {
    assertContains(assets, label, 'AssetsAndAccountDetailView.swift');
  }

  const initialBalanceRow = assertFileExists('Sources/MimiMoneyCore/Services/AccountInitialBalanceRow.swift');
  checkBalancedBraces(initialBalanceRow, 'AccountInitialBalanceRow.swift');
  for (const label of [
    'AccountInitialBalanceRowBuilder',
    'initialBalance',
    'resolveStartDate',
    '初始余额'
  ]) {
    assertContains(initialBalanceRow, label, 'AccountInitialBalanceRow.swift');
  }
  const initialBalanceTests = assertFileExists('Tests/MimiMoneyTests/AccountInitialBalanceRowTests.swift');
  checkBalancedBraces(initialBalanceTests, 'AccountInitialBalanceRowTests.swift');
  assertContains(initialBalanceTests, 'testDisplayUsesLiveInitialBalanceNeverPlaceholderZero', 'AccountInitialBalanceRowTests.swift');
  assertContains(initialBalanceTests, 'testLiveAccountInitialBalanceUpdatesRowAmount', 'AccountInitialBalanceRowTests.swift');

  // Regression: 「设定期初资金」prefilled current balance instead of initialBalance (v1.3.16).
  const balanceEditPrefill = assertFileExists('Sources/MimiMoneyCore/Services/AccountBalanceEditPrefill.swift');
  checkBalancedBraces(balanceEditPrefill, 'AccountBalanceEditPrefill.swift');
  for (const label of [
    'AccountBalanceEditPrefill',
    'setOpening',
    'calibrateCurrent',
    'formattedInput',
    'parseNewAccountOpeningBalance'
  ]) {
    assertContains(balanceEditPrefill, label, 'AccountBalanceEditPrefill.swift');
  }
  const balanceEditPrefillTests = assertFileExists('Tests/MimiMoneyTests/AccountBalanceEditPrefillTests.swift');
  checkBalancedBraces(balanceEditPrefillTests, 'AccountBalanceEditPrefillTests.swift');
  assertContains(balanceEditPrefillTests, 'testOpeningModePrefillsInitialBalanceNotCurrentBalance', 'AccountBalanceEditPrefillTests.swift');
  assertContains(balanceEditPrefillTests, 'testCalibrateModePrefillsCurrentBalance', 'AccountBalanceEditPrefillTests.swift');
  assertContains(balanceEditPrefillTests, 'testSwitchingModesUpdatesPrefillIndependently', 'AccountBalanceEditPrefillTests.swift');
  assertContains(balanceEditPrefillTests, 'testNewAccountEmptyOpeningBalancePersistsZero', 'AccountBalanceEditPrefillTests.swift');
  assertContains(assets, 'AccountBalanceEditPrefill.formattedInput', 'AssetsAndAccountDetailView.swift');
  assertContains(assets, 'onChange(of: balanceEditMode)', 'AssetsAndAccountDetailView.swift');
  assertContains(assets, 'parseNewAccountOpeningBalance', 'AssetsAndAccountDetailView.swift');
  if (assets.includes('newBalanceInput = String(format: "%.2f", account.balance)')) {
    throw new Error('AssetsAndAccountDetailView.swift must not seed balance edit with account.balance only');
  }

  // Regression: Bool entry sheet + shared cancellationAction caused stuck-on-记账.
  if (assets.includes('showAccountEntrySheet')) {
    throw new Error('AssetsAndAccountDetailView.swift must not use showAccountEntrySheet Bool sheet (use entryRoute item sheet)');
  }
  // Regression: Bool + if-let edit sheet presented blank white full-screen (v1.3.11 phone).
  if (assets.includes('showEditAccountSheet') || assets.includes('editingAccountId')) {
    throw new Error('AssetsAndAccountDetailView.swift must use editAccountRoute sheet(item:) for 「…」编辑账户');
  }
  assertContains(assets, 'editAccountRoute', 'AssetsAndAccountDetailView.swift');
  assertContains(assets, 'EditAccountSheetRoute', 'AssetsAndAccountDetailView.swift');
  assertContains(assetsNav, 'struct EditAccountSheetRoute', 'AssetsAccountNavigation.swift');

  const assetsNavTests = assertFileExists('Tests/MimiMoneyTests/AssetsAccountNavigationTests.swift');
  checkBalancedBraces(assetsNavTests, 'AssetsAccountNavigationTests.swift');
  assertContains(assetsNavTests, 'testLeftRightLeftAccountDrillDoesNotDismissAssets', 'AssetsAccountNavigationTests.swift');
  assertContains(assetsNavTests, 'testExpenseTransferExpenseEntryRouteNeverClearsAccount', 'AssetsAccountNavigationTests.swift');
  assertContains(assetsNavTests, 'testEditAccountSheetRouteIdentityUsesAccountId', 'AssetsAccountNavigationTests.swift');
  assertContains(assetsNavTests, 'testTransferEntryRouteIntendedTabIsTransfer', 'AssetsAccountNavigationTests.swift');
  assertContains(assetsNavTests, 'testEachEntryOpenGetsUniquePresentationIdentity', 'AssetsAccountNavigationTests.swift');
  assertContains(assets, '.id(route.presentationID)', 'AssetsAndAccountDetailView.swift');

  const budget = assertFileExists('Sources/MimiMoneyCore/Views/BudgetManagementView.swift');
  checkBalancedBraces(budget, 'BudgetManagementView.swift');
  for (const label of [
    'public struct BudgetManagementView: View',
    '预算管理',
    '已分类预算',
    '动态日预算',
    '分类预算',
    '修改分类预算'
  ]) {
    assertContains(budget, label, 'BudgetManagementView.swift');
  }

  const catMgr = assertFileExists('Sources/MimiMoneyCore/Views/CategoryManagementView.swift');
  checkBalancedBraces(catMgr, 'CategoryManagementView.swift');
  for (const label of [
    'public struct CategoryManagementView: View',
    '分类方案管理',
    '添加1级支出分类',
    '首字作为图标'
  ]) {
    assertContains(catMgr, label, 'CategoryManagementView.swift');
  }

  const settings = assertFileExists('Sources/MimiMoneyCore/Views/SettingsAndShortcutsGuideView.swift');
  checkBalancedBraces(settings, 'SettingsAndShortcutsGuideView.swift');
  for (const label of [
    'public struct SettingsAndShortcutsGuideView: View',
    '自动记账',
    '截屏识别记账',
    '读取剪贴板截图',
    'AppVersionInfo.settingsFooterLine'
  ]) {
    assertContains(settings, label, 'SettingsAndShortcutsGuideView.swift');
  }

  const root = assertFileExists('Sources/MimiMoneyCore/Views/MimiRootContainerView.swift');
  checkBalancedBraces(root, 'MimiRootContainerView.swift');
  assertContains(root, 'public struct MimiRootContainerView: View', 'MimiRootContainerView.swift');
  assertContains(root, 'onOpenURL', 'MimiRootContainerView.swift');
  assertContains(root, 'ShortcutActionCoordinator.handleIncomingURL', 'MimiRootContainerView.swift');
  assertContains(root, 'mimiInteractiveSheet(detents: [.large])', 'MimiRootContainerView.swift');
  assertContains(root, 'mimiEdgeSwipeBack', 'MimiRootContainerView.swift');

  // v1.3.14 global gesture polish: sheet swipe-down + edge-pop / overlay edge-swipe.
  const gesturePolicy = assertFileExists('Sources/MimiMoneyCore/Services/MimiGesturePolicy.swift');
  checkBalancedBraces(gesturePolicy, 'MimiGesturePolicy.swift');
  for (const label of [
    'MimiGesturePolicy',
    'isHorizontalDominant',
    'isVerticalDominant',
    'shouldCommitEdgeBack',
    'rubberBandOffset'
  ]) {
    assertContains(gesturePolicy, label, 'MimiGesturePolicy.swift');
  }
  const gestureChrome = assertFileExists('Sources/MimiMoneyCore/Components/MimiGestureChrome.swift');
  checkBalancedBraces(gestureChrome, 'MimiGestureChrome.swift');
  assertContains(gestureChrome, 'mimiInteractiveSheet', 'MimiGestureChrome.swift');
  assertContains(gestureChrome, 'mimiEdgeSwipeBack', 'MimiGestureChrome.swift');
  assertContains(gestureChrome, 'presentationContentInteraction(.scrolls)', 'MimiGestureChrome.swift');
  const popGesture = assertFileExists('Sources/MimiMoneyCore/Components/MimiInteractivePopGesture.swift');
  checkBalancedBraces(popGesture, 'MimiInteractivePopGesture.swift');
  assertContains(popGesture, 'mimiInteractivePopGestureEnabled', 'MimiInteractivePopGesture.swift');
  assertContains(popGesture, 'interactivePopGestureRecognizer', 'MimiInteractivePopGesture.swift');
  assertContains(assets, 'mimiInteractivePopGestureEnabled()', 'AssetsAndAccountDetailView.swift');
  assertContains(assets, 'mimiEdgeSwipeBack', 'AssetsAndAccountDetailView.swift');
  assertContains(stats, 'mimiInteractivePopGestureEnabled()', 'MimiStatsView.swift');
  assertContains(stats, 'mimiEdgeSwipeBack', 'MimiStatsView.swift');
  assertContains(budget, 'mimiInteractivePopGestureEnabled()', 'BudgetManagementView.swift');
  assertContains(budget, 'mimiEdgeSwipeBack', 'BudgetManagementView.swift');
  const categoryBills = assertFileExists('Sources/MimiMoneyCore/Views/CategoryBillsListView.swift');
  assertContains(categoryBills, 'mimiInteractivePopGestureEnabled()', 'CategoryBillsListView.swift');
  const gesturePolicyTests = assertFileExists('Tests/MimiMoneyTests/MimiGesturePolicyTests.swift');
  checkBalancedBraces(gesturePolicyTests, 'MimiGesturePolicyTests.swift');
  assertContains(gesturePolicyTests, 'testEdgeBackCommitsOnDistanceOrVelocity', 'MimiGesturePolicyTests.swift');
  assertContains(gesturePolicyTests, 'testRubberBandTracksFingerThenDampsOverflow', 'MimiGesturePolicyTests.swift');

  const appMain = assertFileExists('Sources/MimiMoneyApp/MimiMoneyApp.swift');
  checkBalancedBraces(appMain, 'MimiMoneyApp.swift');
  assertContains(appMain, '@main', 'MimiMoneyApp.swift');
  assertContains(appMain, 'struct MimiMoneyApp: App', 'MimiMoneyApp.swift');

  const wslScript = assertFileExists('scripts/build-wsl-xtool.sh');
  assertContains(wslScript, 'xtool', 'scripts/build-wsl-xtool.sh');

  const ciFile = path.resolve(rootDir, '..', '.github', 'workflows', 'build-mimi-ios.yml');
  if (!fs.existsSync(ciFile)) {
    throw new Error('Missing required file: .github/workflows/build-mimi-ios.yml');
  }
  const ciContent = fs.readFileSync(ciFile, 'utf8');
  assertContains(ciContent, 'swift test', '.github/workflows/build-mimi-ios.yml');
  assertContains(ciContent, 'MimiMoney-iOS-v', '.github/workflows/build-mimi-ios.yml');
  assertContains(ciContent, 'NSCameraUsageDescription', '.github/workflows/build-mimi-ios.yml');

  // macOS host (`swift test`) must not see iOS-only / deployment-mismatched APIs unguarded.
  verifyMacOSHostSafeAPIs();

  // Cross-layer API contract verification (Models/Store/Services <-> Views/Intents)
  const theme = assertFileExists('Sources/MimiMoneyCore/Theme/MimiTheme.swift');
  for (const sym of ['public static func formatRM(', 'public static var dangerRed:', 'public static var divider:']) {
    assertContains(theme, sym, 'MimiTheme.swift cross-layer contract');
  }

  const models = assertFileExists('Sources/MimiMoneyCore/Models/MimiModels.swift');
  for (const sym of [
    'public var categoryPath: String',
    'public var accountName: String',
    'public var ledgerName: String',
    'public var receiptImageLabels: [String]',
    'public var refundOrCashback: Double?',
    'public var subcategories: [SubCategory]',
    'public var deltaAmount: Double'
  ]) {
    assertContains(models, sym, 'MimiModels.swift cross-layer contract');
  }

  const store = assertFileExists('Sources/MimiMoneyCore/Services/MimiStore.swift');
  for (const sym of [
    'public static let shared = MimiStore()',
    'pendingShortcutSnippetBill: TransactionItem?',
    'public var monthlyBudgetTotal: Double',
    'public func monthlyBudgetRemaining(',
    'public var currentLedgerName: String',
    'public var categoryBudgets: [CategoryBudgetItem]',
    'public func categorySpent(',
    'public var netWorth: Double',
    'public func groupedTransactionsByDay()',
    'public func auditLogs(for accountName: String)',
    'public func setCustomDailyBudget('
  ]) {
    assertContains(store, sym, 'MimiStore.swift cross-layer contract');
  }

  console.log('Task 7 verified: Stats, Assets, Budgets, Categories, Root App, WSL xtool script, and GitHub Actions workflow complete');
  console.log('All 7 tasks and 100% of Mimi Money spec requirements verified');
}

const args = process.argv.slice(2);
const taskIdx = args.indexOf('--task');
const taskNum = taskIdx !== -1 ? Number(args[taskIdx + 1]) : null;
const runAll = args.includes('--all');

try {
  if (taskNum === 1) {
    verifyTask1();
  } else if (taskNum === 2) {
    verifyTask1();
    verifyTask2();
  } else if (taskNum === 3) {
    verifyTask1();
    verifyTask2();
    verifyTask3();
  } else if (taskNum === 4) {
    verifyTask1();
    verifyTask2();
    verifyTask3();
    verifyTask4();
  } else if (taskNum === 5) {
    verifyTask1();
    verifyTask2();
    verifyTask3();
    verifyTask4();
    verifyTask5();
  } else if (taskNum === 6) {
    verifyTask1();
    verifyTask2();
    verifyTask3();
    verifyTask4();
    verifyTask5();
    verifyTask6();
  } else if (taskNum === 7 || runAll) {
    verifyTask1();
    verifyTask2();
    verifyTask3();
    verifyTask4();
    verifyTask5();
    verifyTask6();
    verifyTask7();
  } else {
    throw new Error(`Unsupported or unimplemented task argument: ${args.join(' ')}`);
  }
} catch (err) {
  console.error(`FAIL: ${err.message}`);
  process.exit(1);
}
