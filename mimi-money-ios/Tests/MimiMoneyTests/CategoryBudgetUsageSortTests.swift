import XCTest
@testable import MimiMoneyCore

final class CategoryBudgetUsageSortTests: XCTestCase {
    private func item(
        name: String,
        limit: Double,
        sortOrder: Int
    ) -> CategoryBudgetItem {
        CategoryBudgetItem(
            id: "cb_\(name)",
            categoryId: "cat_\(name)",
            categoryName: name,
            iconName: "tag",
            monthlyLimit: limit,
            sortOrder: sortOrder
        )
    }

    func testSortsHighestUsagePercentFirst() {
        let food = item(name: "餐饮", limit: 100, sortOrder: 0)
        let transport = item(name: "交通", limit: 200, sortOrder: 1)
        let shop = item(name: "购物", limit: 100, sortOrder: 2)
        // 餐饮 90%, 交通 50%, 购物 10%
        let spent: [String: Double] = ["餐饮": 90, "交通": 100, "购物": 10]

        let sorted = CategoryBudgetUsageSort.sortedByUsageDescending([food, transport, shop]) {
            spent[$0.categoryName] ?? 0
        }

        XCTAssertEqual(sorted.map(\.categoryName), ["餐饮", "交通", "购物"])
    }

    func testOverspentRanksAboveFullyUsed() {
        let a = item(name: "超支", limit: 100, sortOrder: 0)
        let b = item(name: "满额", limit: 100, sortOrder: 1)
        let spent: [String: Double] = ["超支": 150, "满额": 100]

        let sorted = CategoryBudgetUsageSort.sortedByUsageDescending([b, a]) {
            spent[$0.categoryName] ?? 0
        }

        XCTAssertEqual(sorted.map(\.categoryName), ["超支", "满额"])
    }

    func testZeroLimitWithSpendRanksFirst() {
        let zero = item(name: "零额", limit: 0, sortOrder: 0)
        let low = item(name: "低用", limit: 100, sortOrder: 1)
        let spent: [String: Double] = ["零额": 20, "低用": 10]

        let sorted = CategoryBudgetUsageSort.sortedByUsageDescending([low, zero]) {
            spent[$0.categoryName] ?? 0
        }

        XCTAssertEqual(sorted.first?.categoryName, "零额")
    }

    func testZeroLimitZeroSpendRanksLast() {
        let unusedZero = item(name: "空零", limit: 0, sortOrder: 0)
        let used = item(name: "已用", limit: 100, sortOrder: 1)
        let spent: [String: Double] = ["空零": 0, "已用": 5]

        let sorted = CategoryBudgetUsageSort.sortedByUsageDescending([unusedZero, used]) {
            spent[$0.categoryName] ?? 0
        }

        XCTAssertEqual(sorted.map(\.categoryName), ["已用", "空零"])
    }

    func testEqualRatioFallsBackToSortOrder() {
        let first = item(name: "甲", limit: 100, sortOrder: 0)
        let second = item(name: "乙", limit: 200, sortOrder: 1)
        // both 50%
        let spent: [String: Double] = ["甲": 50, "乙": 100]

        let sorted = CategoryBudgetUsageSort.sortedByUsageDescending([second, first]) {
            spent[$0.categoryName] ?? 0
        }

        XCTAssertEqual(sorted.map(\.categoryName), ["甲", "乙"])
    }

    func testUsageRatioSafeForZeroLimit() {
        XCTAssertEqual(CategoryBudgetUsageSort.usageRatio(spent: 0, limit: 100), 0, accuracy: 0.0001)
        XCTAssertEqual(CategoryBudgetUsageSort.usageRatio(spent: 50, limit: 100), 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(CategoryBudgetUsageSort.usageRatio(spent: 10, limit: 0), 1)
        XCTAssertLessThan(CategoryBudgetUsageSort.usageRatio(spent: 0, limit: 0), 0)
    }
}
