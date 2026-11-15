import Foundation

/// Global shared Calendar singletons to eliminate repeated expensive `Calendar(identifier: .gregorian)` allocations.
public enum MimiCalendar {
    /// Shared Gregorian calendar instance for app-wide date/component calculations.
    public static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }()
}
