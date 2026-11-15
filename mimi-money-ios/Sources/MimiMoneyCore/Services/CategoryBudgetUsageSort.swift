import Foundation

/// Sorts categorized budgets by usage percentage (spent / limit), highest first.
public enum CategoryBudgetUsageSort {
    /// Raw usage ratio for ordering. Overspent can exceed 1.0.
    /// Zero limit: any spend ranks above finite ratios; zero spend ranks at the bottom.
    public static func usageRatio(spent: Double, limit: Double) -> Double {
        if limit > 0 {
            return spent / limit
        }
        return spent > 0 ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude
    }

    /// Highest usage % first; ties keep `sortOrder` then category name.
    public static func sortedByUsageDescending(
        _ items: [CategoryBudgetItem],
        spentFor: (CategoryBudgetItem) -> Double
    ) -> [CategoryBudgetItem] {
        items.sorted { a, b in
            let ra = usageRatio(spent: spentFor(a), limit: a.monthlyLimit)
            let rb = usageRatio(spent: spentFor(b), limit: b.monthlyLimit)
            if ra != rb {
                return ra > rb
            }
            if a.sortOrder != b.sortOrder {
                return a.sortOrder < b.sortOrder
            }
            return a.categoryName.localizedStandardCompare(b.categoryName) == .orderedAscending
        }
    }
}
