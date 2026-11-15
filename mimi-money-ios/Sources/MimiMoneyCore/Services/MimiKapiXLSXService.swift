import Foundation
import CoreXLSX
import ZIPFoundation

/// 咔皮记账同款 Excel：双 Sheet「收支账单」+「内部转账」。
public enum MimiKapiXLSXService {
    public static let billSheetName = "收支账单"
    public static let transferSheetName = "内部转账"

    public enum XLSXError: LocalizedError {
        case cannotOpen
        case noBillSheet
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .cannotOpen: return "无法打开 Excel 文件"
            case .noBillSheet: return "未找到「收支账单」工作表"
            case .writeFailed(let detail): return "导出 Excel 失败：\(detail)"
            }
        }
    }

    // MARK: - Import

    public static func parseXLSX(data: Data) throws -> [TransactionItem] {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimi-import-\(UUID().uuidString).xlsx")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let file = XLSXFile(filepath: tempURL.path) else {
            throw XLSXError.cannotOpen
        }

        let sharedStrings = try file.parseSharedStrings()
        var billRows: [[String]] = []
        var transferRows: [[String]] = []

        for workbook in try file.parseWorkbooks() {
            for (name, path) in try file.parseWorksheetPathsAndNames(workbook: workbook) {
                let worksheet = try file.parseWorksheet(at: path)
                let rows = sheetRows(worksheet: worksheet, sharedStrings: sharedStrings)
                let sheetName = name ?? ""
                if sheetName == billSheetName || sheetName.contains("收支") {
                    billRows = rows
                } else if sheetName == transferSheetName || sheetName.contains("转账") || sheetName.contains("互转") {
                    transferRows = rows
                } else if billRows.isEmpty {
                    billRows = rows
                } else if transferRows.isEmpty, rows.first?.contains(where: { $0.contains("转入账户") }) == true {
                    transferRows = rows
                }
            }
        }

        guard !billRows.isEmpty else { throw XLSXError.noBillSheet }

        var csvParts: [String] = [rowsToCSV(billRows)]
        if !transferRows.isEmpty {
            csvParts.append(rowsToCSV(transferRows))
        }
        return MimiCSVService.parseMimiCSV(csvParts.joined(separator: "\n"))
    }

    // MARK: - Export

    public static func exportXLSX(transactions: [TransactionItem]) throws -> Data {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        let billHeader = ["日期", "时间", "类型", "金额", "一级分类", "二级分类", "标签", "账户", "计入收支", "计入预算", "所属账本", "备注", "分摊明细"]
        let transferHeader = ["日期", "时间", "类型", "金额", "转入账户", "转出账户", "备注"]

        var billRows: [[String]] = [billHeader]
        var transferRows: [[String]] = [transferHeader]

        let nonTransfers = transactions.filter { $0.type != .transfer }.sorted { $0.date < $1.date }
        let transfers = transactions.filter { $0.type == .transfer }.sorted { $0.date < $1.date }

        for tx in nonTransfers {
            let parts = tx.categoryPath.components(separatedBy: "-")
            let pCat = parts.first ?? tx.categoryPath
            let sCat = parts.count > 1 ? parts.dropFirst().joined(separator: "-") : ""
            let tags = tx.tags.joined(separator: ";")
            let incStats = tx.includeInStats ? "是" : "否"
            let incBudget = tx.type == .expense ? (tx.includeInBudget ? "是" : "否") : ""
            billRows.append([
                dateFormatter.string(from: tx.date),
                timeFormatter.string(from: tx.date),
                tx.type.rawValue,
                formatNumber(tx.amount),
                pCat,
                sCat,
                tags,
                tx.accountName,
                incStats,
                incBudget,
                tx.ledgerName,
                tx.note,
                ""
            ])
        }

        for tx in transfers {
            let toAcc = DefaultCatalog.resolveAccountName(from: tx.targetAccountId)
            let fromAcc = DefaultCatalog.resolveAccountName(from: tx.accountId)
            transferRows.append([
                dateFormatter.string(from: tx.date),
                timeFormatter.string(from: tx.date),
                "账户互转",
                formatNumber(tx.amount),
                toAcc,
                fromAcc,
                tx.note
            ])
        }

        return try buildWorkbookData(billRows: billRows, transferRows: transferRows)
    }

    public static func suggestedExportFileName(start: Date?, end: Date?, now: Date = Date()) -> String {
        let day = DateFormatter()
        day.dateFormat = "yyyyMMdd"
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMddHHmmss"
        let startStr = day.string(from: start ?? now)
        let endStr = day.string(from: end ?? now)
        return "咪咪记账_\(startStr)_\(endStr)_\(stamp.string(from: now)).xlsx"
    }

    // MARK: - Read helpers

    private static func sheetRows(worksheet: Worksheet, sharedStrings: SharedStrings?) -> [[String]] {
        var result: [[String]] = []
        for row in worksheet.data?.rows ?? [] {
            let cells = row.cells
            guard !cells.isEmpty else { continue }
            let maxCol = cells.map { columnIndex(from: $0.reference) }.max() ?? 0
            var values = Array(repeating: "", count: maxCol + 1)
            for cell in cells {
                let col = columnIndex(from: cell.reference)
                guard col < values.count else { continue }
                values[col] = cellString(cell, sharedStrings: sharedStrings)
            }
            if values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                result.append(values)
            }
        }
        return result
    }

    private static func cellString(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        if cell.type == .sharedString {
            guard let shared = sharedStrings else { return "" }
            if let s = cell.stringValue(shared), !s.isEmpty {
                return s
            }
            if let index = cell.value.flatMap(Int.init),
               shared.items.indices.contains(index) {
                let item = shared.items[index]
                if let t = item.text, !t.isEmpty { return t }
                let rich = item.richText.compactMap(\.text).joined()
                if !rich.isEmpty { return rich }
            }
            // Shared string entry is legitimately empty (<si><t/></si>); never return cell.value (which is the SST index like "18").
            return ""
        }
        if let shared = sharedStrings, let s = cell.stringValue(shared), !s.isEmpty {
            return s
        }
        if let inline = cell.inlineString?.text {
            return inline
        }
        return cell.value ?? ""
    }

    /// CellReference column → 0-based index (A=0)
    private static func columnIndex(from reference: CellReference) -> Int {
        var idx = 0
        for ch in reference.column.value.uppercased() {
            guard let ascii = ch.asciiValue, ascii >= 65, ascii <= 90 else { continue }
            idx = idx * 26 + Int(ascii - 64)
        }
        return max(0, idx - 1)
    }

    private static func rowsToCSV(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { escapeCSV($0) }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\n") || value.contains("\"") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func formatNumber(_ val: Double) -> String {
        if abs(val.rounded() - val) < 0.0001 {
            return String(format: "%.0f", val)
        }
        let twoDec = String(format: "%.2f", val)
        return twoDec.hasSuffix("0") ? String(twoDec.dropLast()) : twoDec
    }

    // MARK: - Write OOXML

    private static func buildWorkbookData(billRows: [[String]], transferRows: [[String]]) throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mimi-xlsx-\(UUID().uuidString)", isDirectory: true)
        let xl = root.appendingPathComponent("xl", isDirectory: true)
        let worksheets = xl.appendingPathComponent("worksheets", isDirectory: true)
        let rels = root.appendingPathComponent("_rels", isDirectory: true)
        let xlRels = xl.appendingPathComponent("_rels", isDirectory: true)

        try FileManager.default.createDirectory(at: worksheets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rels, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlRels, withIntermediateDirectories: true)

        var shared: [String] = []
        var indexByString: [String: Int] = [:]
        func sid(_ text: String) -> Int {
            if let existing = indexByString[text] { return existing }
            let i = shared.count
            shared.append(text)
            indexByString[text] = i
            return i
        }

        // Pre-register all strings so sharedStrings is complete before writing sheets
        for row in billRows + transferRows {
            for cell in row { _ = sid(cell) }
        }

        try writeUTF8(contentTypesXML(), to: root.appendingPathComponent("[Content_Types].xml"))
        try writeUTF8(rootRelsXML(), to: rels.appendingPathComponent(".rels"))
        try writeUTF8(workbookXML(), to: xl.appendingPathComponent("workbook.xml"))
        try writeUTF8(workbookRelsXML(), to: xlRels.appendingPathComponent("workbook.xml.rels"))
        try writeUTF8(stylesXML(), to: xl.appendingPathComponent("styles.xml"))
        try writeUTF8(sharedStringsXML(shared), to: xl.appendingPathComponent("sharedStrings.xml"))
        try writeUTF8(worksheetXML(rows: billRows, stringIndex: indexByString), to: worksheets.appendingPathComponent("sheet1.xml"))
        try writeUTF8(worksheetXML(rows: transferRows, stringIndex: indexByString), to: worksheets.appendingPathComponent("sheet2.xml"))

        let zipURL = root.appendingPathExtension("zip")
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try FileManager.default.zipItem(at: root, to: zipURL, shouldKeepParent: false, compressionMethod: .deflate)
        let data = try Data(contentsOf: zipURL)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: zipURL)
        return data
    }

    private static func writeUTF8(_ string: String, to url: URL) throws {
        guard let data = string.data(using: .utf8) else {
            throw XLSXError.writeFailed("UTF-8 encode failed")
        }
        try data.write(to: url, options: .atomic)
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func columnName(_ index: Int) -> String {
        var n = index + 1
        var name = ""
        while n > 0 {
            let rem = (n - 1) % 26
            name = String(UnicodeScalar(65 + rem)!) + name
            n = (n - 1) / 26
        }
        return name
    }

    private static func worksheetXML(rows: [[String]], stringIndex: [String: Int]) -> String {
        var body = ""
        for (rIdx, row) in rows.enumerated() {
            let rowNum = rIdx + 1
            body += "<row r=\"\(rowNum)\">"
            for (cIdx, value) in row.enumerated() {
                let ref = "\(columnName(cIdx))\(rowNum)"
                if cIdx == 3, rowNum > 1, Double(value) != nil {
                    // Amount column as number
                    body += "<c r=\"\(ref)\"><v>\(value)</v></c>"
                } else {
                    let si = stringIndex[value] ?? 0
                    body += "<c r=\"\(ref)\" t=\"s\"><v>\(si)</v></c>"
                }
            }
            body += "</row>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(body)</sheetData>
        </worksheet>
        """
    }

    private static func sharedStringsXML(_ strings: [String]) -> String {
        let items = strings.map { "<si><t>\(xmlEscape($0))</t></si>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\(strings.count)" uniqueCount="\(strings.count)">\(items)</sst>
        """
    }

    private static func contentTypesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
    }

    private static func rootRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private static func workbookXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>
        <sheet name="\(billSheetName)" sheetId="1" r:id="rId1"/>
        <sheet name="\(transferSheetName)" sheetId="2" r:id="rId2"/>
        </sheets>
        </workbook>
        """
    }

    private static func workbookRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
        <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private static func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf/></cellStyleXfs>
        <cellXfs count="1"><xf/></cellXfs>
        </styleSheet>
        """
    }
}
