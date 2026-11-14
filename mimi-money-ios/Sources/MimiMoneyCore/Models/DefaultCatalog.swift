import Foundation

public enum DefaultCatalog {
    // Exact 13 standard + 2 custom expense primary categories and 51 subcategories from IMG_2247, IMG_2248, IMG_2267-2282
    public static func standardExpenseCategories() -> [CategoryGroup] {
        [
            CategoryGroup(
                id: "exp_food",
                name: "餐饮",
                type: .expense,
                iconName: "🍜",
                subCategories: [
                    SubCategory(id: "exp_food_ingredient", name: "做饭食材", iconName: "🎃", sortOrder: 0),
                    SubCategory(id: "exp_food_restaurant", name: "餐厅", iconName: "🍜", sortOrder: 1),
                    SubCategory(id: "exp_food_takeout", name: "外卖外带", iconName: "🛍️", sortOrder: 2),
                    SubCategory(id: "exp_food_coffee", name: "咖啡", iconName: "☕", sortOrder: 3),
                    SubCategory(id: "exp_food_drink", name: "饮品", iconName: "🥤", sortOrder: 4),
                    SubCategory(id: "exp_food_snack", name: "零食甜品", iconName: "🍟", sortOrder: 5),
                    SubCategory(id: "exp_food_bar", name: "酒吧酒水", iconName: "🍺", sortOrder: 6)
                ],
                sortOrder: 0
            ),
            CategoryGroup(
                id: "exp_shopping",
                name: "购物",
                type: .expense,
                iconName: "🧺",
                subCategories: [
                    SubCategory(id: "exp_shop_clothes", name: "服饰鞋包", iconName: "👕", sortOrder: 0),
                    SubCategory(id: "exp_shop_beauty", name: "美妆护肤", iconName: "🧴", sortOrder: 1),
                    SubCategory(id: "exp_shop_digital", name: "数码电器", iconName: "📷", sortOrder: 2),
                    SubCategory(id: "exp_shop_daily", name: "生活用品", iconName: "🧻", sortOrder: 3),
                    SubCategory(id: "exp_shop_care", name: "个护服务", iconName: "🧼", sortOrder: 4),
                    SubCategory(id: "exp_shop_shipping", name: "运费", iconName: "📦", sortOrder: 5),
                    SubCategory(id: "exp_shop_secondhand", name: "二手租借", iconName: "🎁", sortOrder: 6)
                ],
                sortOrder: 1
            ),
            CategoryGroup(
                id: "exp_transport",
                name: "交通",
                type: .expense,
                iconName: "🚗",
                subCategories: [
                    SubCategory(id: "exp_trans_public", name: "公共交通", iconName: "🚌", sortOrder: 0),
                    SubCategory(id: "exp_trans_taxi", name: "打车叫车", iconName: "🚕", sortOrder: 1),
                    SubCategory(id: "exp_trans_intercity", name: "城际出行", iconName: "🚄", sortOrder: 2),
                    SubCategory(id: "exp_trans_fuel", name: "加油充电", iconName: "⛽", sortOrder: 3),
                    SubCategory(id: "exp_trans_parking", name: "过路停车", iconName: "🅿️", sortOrder: 4),
                    SubCategory(id: "exp_trans_carcare", name: "养车", iconName: "🚙", sortOrder: 5),
                    SubCategory(id: "exp_trans_card", name: "交通卡充值", iconName: "🎫", sortOrder: 6)
                ],
                sortOrder: 2
            ),
            CategoryGroup(
                id: "exp_housing",
                name: "住房",
                type: .expense,
                iconName: "🏠",
                subCategories: [
                    SubCategory(id: "exp_house_rent", name: "房租房贷", iconName: "🏡", sortOrder: 0),
                    SubCategory(id: "exp_house_utility", name: "物业水电", iconName: "💧", sortOrder: 1),
                    SubCategory(id: "exp_house_telecom", name: "话费网费", iconName: "🖥️", sortOrder: 2),
                    SubCategory(id: "exp_house_mgmt", name: "物业管理费", iconName: "🏢", sortOrder: 3),
                    SubCategory(id: "exp_house_repair", name: "装修维修", iconName: "🖌️", sortOrder: 4),
                    SubCategory(id: "exp_house_clean", name: "家政服务", iconName: "🧹", sortOrder: 5)
                ],
                sortOrder: 3
            ),
            CategoryGroup(
                id: "exp_entertainment",
                name: "休闲娱乐",
                type: .expense,
                iconName: "🏀",
                subCategories: [
                    SubCategory(id: "exp_ent_sport", name: "运动健身", iconName: "🏸", sortOrder: 0),
                    SubCategory(id: "exp_ent_offline", name: "线下娱乐", iconName: "🎟️", sortOrder: 1),
                    SubCategory(id: "exp_ent_digital", name: "数字娱乐", iconName: "🎮", sortOrder: 2),
                    SubCategory(id: "exp_ent_travel", name: "旅游度假", iconName: "🚩", sortOrder: 3),
                    SubCategory(id: "exp_ent_hobby", name: "收藏爱好", iconName: "🎁", sortOrder: 4),
                    SubCategory(id: "exp_ent_sub", name: "订阅会员", iconName: "💳", sortOrder: 5)
                ],
                sortOrder: 4
            ),
            CategoryGroup(
                id: "exp_medical",
                name: "医疗健康",
                type: .expense,
                iconName: "🏥",
                subCategories: [
                    SubCategory(id: "exp_med_doctor", name: "看病买药", iconName: "💊", sortOrder: 0),
                    SubCategory(id: "exp_med_dental", name: "医美齿科", iconName: "🦷", sortOrder: 1),
                    SubCategory(id: "exp_med_health", name: "保健养生", iconName: "🫙", sortOrder: 2),
                    SubCategory(id: "exp_med_vaccine", name: "体检疫苗", iconName: "💉", sortOrder: 3),
                    SubCategory(id: "exp_med_care", name: "康复陪护", iconName: "🧑‍⚕️", sortOrder: 4)
                ],
                sortOrder: 5
            ),
            CategoryGroup(
                id: "exp_study",
                name: "学习办公",
                type: .expense,
                iconName: "📖",
                subCategories: [
                    SubCategory(id: "exp_study_tuition", name: "教育学费", iconName: "🎓", sortOrder: 0),
                    SubCategory(id: "exp_study_training", name: "职业培训", iconName: "💻", sortOrder: 1),
                    SubCategory(id: "exp_study_course", name: "兴趣课程", iconName: "🎹", sortOrder: 2),
                    SubCategory(id: "exp_study_stationery", name: "图书文具", iconName: "✏️", sortOrder: 3)
                ],
                sortOrder: 6
            ),
            CategoryGroup(
                id: "exp_pet",
                name: "宠物",
                type: .expense,
                iconName: "🐱",
                subCategories: [
                    SubCategory(id: "exp_pet_food", name: "宠物食品", iconName: "🦴", sortOrder: 0),
                    SubCategory(id: "exp_pet_supply", name: "宠物用品", iconName: "🐾", sortOrder: 1),
                    SubCategory(id: "exp_pet_medical", name: "宠物医疗", iconName: "🩺", sortOrder: 2),
                    SubCategory(id: "exp_pet_service", name: "宠物服务", iconName: "✂️", sortOrder: 3)
                ],
                sortOrder: 7
            ),
            CategoryGroup(
                id: "exp_baby",
                name: "母婴",
                type: .expense,
                iconName: "👶",
                subCategories: [
                    SubCategory(id: "exp_baby_food", name: "婴儿食品", iconName: "🍼", sortOrder: 0),
                    SubCategory(id: "exp_baby_supply", name: "母婴用品", iconName: "🛒", sortOrder: 1),
                    SubCategory(id: "exp_baby_service", name: "母婴服务", iconName: "🧷", sortOrder: 2)
                ],
                sortOrder: 8
            ),
            CategoryGroup(
                id: "exp_transfer_social",
                name: "资金往来",
                type: .expense,
                iconName: "💰",
                subCategories: [
                    SubCategory(id: "exp_social_repay", name: "还款", iconName: "🗓️", sortOrder: 0),
                    SubCategory(id: "exp_social_gift", name: "人情往来", iconName: "🧧", sortOrder: 1)
                ],
                sortOrder: 9
            ),
            CategoryGroup(id: "exp_insurance", name: "保险", type: .expense, iconName: "🛡️", subCategories: [], sortOrder: 10),
            CategoryGroup(id: "exp_invest", name: "投资理财", type: .expense, iconName: "📈", subCategories: [], sortOrder: 11),
            CategoryGroup(id: "exp_other", name: "其他支出", type: .expense, iconName: "📦", subCategories: [], sortOrder: 12),
            CategoryGroup(id: "exp_custom_home", name: "家用", type: .expense, iconName: "🎃", isCustom: true, subCategories: [], sortOrder: 13),
            CategoryGroup(id: "exp_custom_carloan", name: "车贷", type: .expense, iconName: "🚙", isCustom: true, subCategories: [], sortOrder: 14)
        ]
    }

    // Exact 8 standard + 1 custom income primary categories from IMG_2245 & IMG_2248
    public static func standardIncomeCategories() -> [CategoryGroup] {
        [
            CategoryGroup(
                id: "inc_salary",
                name: "职业收入",
                type: .income,
                iconName: "💳",
                subCategories: [
                    SubCategory(id: "inc_salary_bonus", name: "绩效奖金", iconName: "🏆", sortOrder: 0),
                    SubCategory(id: "inc_salary_allowance", name: "津贴补助", iconName: "💴", sortOrder: 1)
                ],
                sortOrder: 0
            ),
            CategoryGroup(id: "inc_business", name: "个体经营", type: .income, iconName: "🏪", subCategories: [], sortOrder: 1),
            CategoryGroup(id: "inc_sidejob", name: "副业兼职", type: .income, iconName: "💼", subCategories: [], sortOrder: 2),
            CategoryGroup(
                id: "inc_invest",
                name: "投资收入",
                type: .income,
                iconName: "📈",
                subCategories: [
                    SubCategory(id: "inc_invest_dividend", name: "股息分红", iconName: "📊", sortOrder: 0),
                    SubCategory(id: "inc_invest_interest", name: "利息", iconName: "🪙", sortOrder: 1)
                ],
                sortOrder: 3
            ),
            CategoryGroup(id: "inc_insurance", name: "保险理赔", type: .income, iconName: "🚙", subCategories: [], sortOrder: 4),
            CategoryGroup(
                id: "inc_refund",
                name: "退款返还",
                type: .income,
                iconName: "📑",
                subCategories: [
                    SubCategory(id: "inc_refund_cashback", name: "返现", iconName: "💸", sortOrder: 0),
                    SubCategory(id: "inc_refund_reimburse", name: "报销", iconName: "🧾", sortOrder: 1),
                    SubCategory(id: "inc_refund_repay", name: "他人还款", iconName: "🤝", sortOrder: 2),
                    SubCategory(id: "inc_refund_tax", name: "退税", iconName: "🏦", sortOrder: 3)
                ],
                sortOrder: 5
            ),
            CategoryGroup(
                id: "inc_gift",
                name: "礼金收入",
                type: .income,
                iconName: "💰",
                subCategories: [
                    SubCategory(id: "inc_gift_living", name: "生活费", iconName: "🧧", sortOrder: 0)
                ],
                sortOrder: 6
            ),
            CategoryGroup(
                id: "inc_other",
                name: "其他收入",
                type: .income,
                iconName: "📦",
                subCategories: [
                    SubCategory(id: "inc_other_secondhand", name: "二手买卖", iconName: "🏷️", sortOrder: 0),
                    SubCategory(id: "inc_other_lucky", name: "好运收入", iconName: "🍀", sortOrder: 1)
                ],
                sortOrder: 7
            ),
            CategoryGroup(id: "inc_custom_transfer", name: "别人转账", type: .income, iconName: "🧑‍⚕️", isCustom: true, subCategories: [], sortOrder: 8)
        ]
    }

    // Exact 4 accounts from IMG_2258 summing to RM368.42
    public static func defaultAccounts() -> [AccountItem] {
        [
            AccountItem(id: "acc_cash", name: "现金", subtitle: "现金余额", badgeText: nil, iconName: "💰", balance: 72.10, initialBalance: 72.10),
            AccountItem(id: "acc_cimb", name: "CIMB", subtitle: "其他银行储蓄卡余额", badgeText: "储蓄卡", iconName: "🏦", balance: 23.45, initialBalance: 23.45),
            AccountItem(id: "acc_tng", name: "TNGewallet", subtitle: "电子钱包 (TNGewallet)", badgeText: nil, iconName: "💬", balance: 68.62, initialBalance: 101.62),
            AccountItem(id: "acc_pbb", name: "PBBank", subtitle: "其他银行储蓄卡余额", badgeText: "储蓄卡", iconName: "🏦", balance: 204.25, initialBalance: 237.06)
        ]
    }

    // Exact Main Ledger and 6 category budgets from IMG_2240 & IMG_2263
    public static func defaultLedger() -> LedgerItem {
        LedgerItem(
            id: "ledger_main",
            name: "Main Ledger",
            currency: .myr,
            monthlyBudget: 3200.00,
            categoryBudgets: [
                CategoryBudgetItem(id: "cb_ent", categoryId: "exp_entertainment", categoryName: "休闲娱乐", iconName: "🏀", monthlyLimit: 50.00, sortOrder: 0),
                CategoryBudgetItem(id: "cb_shop", categoryId: "exp_shopping", categoryName: "购物", iconName: "🧺", monthlyLimit: 200.00, sortOrder: 1),
                CategoryBudgetItem(id: "cb_trans", categoryId: "exp_transport", categoryName: "交通", iconName: "🚗", monthlyLimit: 400.00, sortOrder: 2),
                CategoryBudgetItem(id: "cb_food", categoryId: "exp_food", categoryName: "餐饮", iconName: "🍜", monthlyLimit: 650.00, sortOrder: 3),
                CategoryBudgetItem(id: "cb_home", categoryId: "exp_custom_home", categoryName: "家用", iconName: "🎃", monthlyLimit: 1000.00, sortOrder: 4),
                CategoryBudgetItem(id: "cb_car", categoryId: "exp_custom_carloan", categoryName: "车贷", iconName: "🚙", monthlyLimit: 700.00, sortOrder: 5)
            ]
        )
    }

    // 100+ sticker icons from IMG_2283 - IMG_2292
    public static func stickerIconLibrary() -> [String] {
        [
            "🍜", "🎃", "🛍️", "☕", "🥤", "🍟", "🍺", "🧺", "👕", "🧴",
            "📷", "🧻", "🧼", "📦", "🎁", "🚗", "🚌", "🚕", "🚄", "⛽",
            "🅿️", "🚙", "🎫", "🏠", "🏡", "💧", "🖥️", "🏢", "🖌️", "🧹",
            "🏀", "🏸", "🎟️", "🎮", "🚩", "💳", "🏥", "💊", "🦷", "🫙",
            "💉", "🧑‍⚕️", "📖", "🎓", "💻", "🎹", "✏️", "🐱", "🦴", "🐾",
            "🩺", "✂️", "👶", "🍼", "🛒", "🧷", "💰", "🗓️", "🧧", "🛡️",
            "📈", "🏆", "💴", "🏪", "💼", "📊", "🪙", "📑", "💸", "🧾",
            "🤝", "🏦", "🏷️", "🍀", "🍔", "🍕", "🍣", "🥩", "串", "🧁",
            "🍇", "🍎", "🥟", "🍳", "🫖", "🍷", "🍹", "🎱", "🎪", "🏈",
            "♟️", "🔥", "💌", "📫", "👛", "💍", "💄", "🪞", "🔦", "🧽"
        ]
    }

    public static func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        let cal = Calendar(identifier: .gregorian)
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? Date()
    }

    /// Live account list synced from `MimiStore` so custom accounts resolve by name/id.
    private static let liveAccountsLock = NSLock()
    private static var liveAccountsCache: [AccountItem] = defaultAccounts()

    public static func syncLiveAccounts(_ accounts: [AccountItem]) {
        liveAccountsLock.lock()
        liveAccountsCache = accounts
        liveAccountsLock.unlock()
    }

    private static func liveAccountsSnapshot() -> [AccountItem] {
        liveAccountsLock.lock()
        let snap = liveAccountsCache
        liveAccountsLock.unlock()
        return snap
    }

    public static func resolveAccountId(from accountName: String) -> String? {
        resolveAccountId(from: accountName, among: liveAccountsSnapshot())
    }

    /// Resolve against live accounts first (custom accounts), then built-in aliases.
    public static func resolveAccountId(from accountName: String, among accounts: [AccountItem]) -> String? {
        let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "不选账户" || trimmed == "无账户" {
            return nil
        }
        if let exact = accounts.first(where: {
            $0.id == trimmed || $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return exact.id
        }
        let lower = trimmed.lowercased()
        if lower.contains("tng") || lower.contains("touch") || lower.contains("ewallet") {
            return accounts.first(where: { $0.id == "acc_tng" })?.id ?? "acc_tng"
        }
        if lower.contains("cimb") {
            return accounts.first(where: { $0.id == "acc_cimb" })?.id ?? "acc_cimb"
        }
        if lower.contains("pbb") || lower.contains("public") {
            return accounts.first(where: { $0.id == "acc_pbb" })?.id ?? "acc_pbb"
        }
        if lower.contains("cash") || lower.contains("现金") {
            return accounts.first(where: { $0.id == "acc_cash" })?.id ?? "acc_cash"
        }
        if lower.contains("maybank") || lower.contains("mbb") {
            return accounts.first(where: { $0.id == "acc_maybank" || $0.name.localizedCaseInsensitiveContains("maybank") })?.id
        }
        // Unknown name must not silently map to TNGewallet.
        return nil
    }

    public static func resolveAccountName(from accountId: String?) -> String {
        resolveAccountName(from: accountId, among: liveAccountsSnapshot())
    }

    public static func resolveAccountName(from accountId: String?, among accounts: [AccountItem]) -> String {
        guard let accountId, !accountId.isEmpty else { return "不选账户" }
        if let match = accounts.first(where: { $0.id == accountId || $0.name == accountId }) {
            return match.name
        }
        if accountId == "acc_tng" { return "TNGewallet" }
        if accountId == "acc_cimb" { return "CIMB" }
        if accountId == "acc_pbb" { return "PBBank" }
        if accountId == "acc_cash" { return "现金" }
        return accountId
    }

    public static func resolveCategoryIds(from categoryPath: String, type: TransactionType) -> (primaryId: String, subId: String?, iconName: String) {
        if type == .transfer {
            return ("transfer", nil, "⇄")
        }
        let parts = categoryPath.components(separatedBy: "-")
        let primaryName = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? categoryPath
        let rawSub = parts.count > 1 ? parts.dropFirst().joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let subName = (rawSub?.isEmpty == false) ? rawSub : nil
        let catalog = (type == .income ? standardIncomeCategories() : standardExpenseCategories())
        if let group = catalog.first(where: { $0.name == primaryName || $0.id == primaryName }) {
            if let sName = subName {
                if let sub = group.subCategories.first(where: { $0.name == sName || $0.id == sName }) {
                    return (group.id, sub.id, sub.displayBadgeToken)
                }
                if let (otherGroup, otherSub) = findSubCategory(named: sName, in: catalog) {
                    return (otherGroup.id, otherSub.id, otherSub.displayBadgeToken)
                }
            }
            return (group.id, nil, group.displayBadgeToken)
        }
        if let sName = subName, let (ownerGroup, matchedSub) = findSubCategory(named: sName, in: catalog) {
            return (ownerGroup.id, matchedSub.id, matchedSub.displayBadgeToken)
        }
        if let (ownerGroup, matchedSub) = findSubCategory(named: primaryName, in: catalog) {
            return (ownerGroup.id, matchedSub.id, matchedSub.displayBadgeToken)
        }
        if type == .income {
            return ("inc_other", nil, "📦")
        }
        return ("exp_food", "exp_food_restaurant", "🍜")
    }

    private static func findSubCategory(named name: String, in catalog: [CategoryGroup]) -> (CategoryGroup, SubCategory)? {
        for group in catalog {
            if let sub = group.subCategories.first(where: { $0.name == name || $0.id == name }) {
                return (group, sub)
            }
        }
        return nil
    }

    public static func resolveCategoryDisplay(primaryId: String, subId: String?, type: TransactionType) -> (categoryPath: String, iconName: String) {
        if type == .transfer {
            return ("转账", "⇄")
        }
        let allGroups = standardExpenseCategories() + standardIncomeCategories()
        if let group = allGroups.first(where: { $0.id == primaryId || $0.name == primaryId }) {
            if let subId,
               let sub = group.subCategories.first(where: { $0.id == subId || $0.name == subId }) {
                return ("\(group.name)-\(sub.name)", sub.displayBadgeToken)
            }
            return (group.name, group.displayBadgeToken)
        }
        if let subId, !subId.isEmpty {
            return ("\(primaryId)-\(subId)", "🍜")
        }
        return (primaryId, "🍜")
    }
}
