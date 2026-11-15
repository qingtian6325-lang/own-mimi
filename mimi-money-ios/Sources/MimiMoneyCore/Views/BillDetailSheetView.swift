import SwiftUI

public struct BillDetailSheetView: View {
    @ObservedObject public var store: MimiStore
    @State private var editableBill: TransactionItem
    public var onDismiss: () -> Void

    /// Amount when the screen opened — used if leave-to-save sees empty/zero/invalid input.
    private let previousValidAmount: Double

    @State private var amountString: String
    @State private var discountString: String
    @State private var refundString: String

    @State private var showAmountKeypad: Bool = false
    @State private var amountExpression: String = ""
    @State private var showingActionSheet = false
    @State private var showingImagePicker = false
    @State private var showDeleteConfirm = false
    @State private var showCategoryPicker = false
    @State private var showCategoryEditor = false
    /// Skip leave-to-save after an explicit delete (transaction already removed).
    @State private var skipAutoSave = false
    #if canImport(UIKit)
    @State private var pickerSourceType: UIKitImagePicker.SourceType = .photoLibrary
    #endif
    @State private var activeViewerItem: ReceiptViewerItem? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        store: MimiStore,
        transaction: TransactionItem,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self._editableBill = State(initialValue: transaction)
        self.onDismiss = onDismiss
        self.previousValidAmount = transaction.amount
        self._amountString = State(initialValue: String(format: "%.2f", transaction.amount))
        self._discountString = State(
            initialValue: transaction.discountAmount > 0 ? String(format: "%.2f", transaction.discountAmount) : ""
        )
        self._refundString = State(
            initialValue: transaction.refundOrCashback.map { String(format: "%.2f", $0) } ?? ""
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    // Main Amount & Category Card (IMG_2242)
                    VStack(spacing: 0) {
                        detailRow(label: "类型") {
                            Menu {
                                ForEach(TransactionType.allCases, id: \.self) { type in
                                    Button(type.localizedTitle) {
                                        editableBill.type = type
                                        if type == .transfer {
                                            editableBill.categoryPath = "转账"
                                            editableBill.iconName = "⇄"
                                            editableBill.includeInStats = false
                                            editableBill.includeInBudget = false
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(LocalizedStringKey(editableBill.type.title), bundle: .mimiModule)
                                        .mimiFont(14, weight: .semibold)
                                        .foregroundColor(MimiTheme.textPrimary)
                                    Image(systemName: "chevron.right")
                                        .mimiFont(11)
                                        .foregroundColor(MimiTheme.textMuted)
                                }
                            }
                        }

                        Divider().padding(.leading, 16)

                        Button {
                            amountExpression = amountString
                            showAmountKeypad = true
                        } label: {
                            detailRow(label: editableBill.type == .income ? "实收金额" : "实付金额") {
                                HStack(spacing: 4) {
                                    Text(editableBill.type == .income ? "+RM" : "-RM")
                                        .mimiFont(18, weight: .bold, design: .rounded)
                                        .foregroundColor(editableBill.type == .income ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)
                                    Text(amountString.isEmpty ? "0.00" : amountString)
                                        .mimiFont(18, weight: .bold, design: .rounded)
                                        .foregroundColor(editableBill.type == .income ? MimiTheme.incomeOrange : MimiTheme.expenseBlue)
                                    Image(systemName: "chevron.right")
                                        .mimiFont(11, weight: .semibold)
                                        .foregroundColor(MimiTheme.textMuted)
                                }
                            }
                        }
                        .mimiPressable()

                        Divider().padding(.leading, 16)

                        detailRow(label: "分类") {
                            if editableBill.type == .transfer {
                                HStack(spacing: 8) {
                                    MimiStickerIconView(
                                        iconName: "⇄",
                                        categoryName: "转账",
                                        transactionType: .transfer,
                                        size: 26
                                    )
                                    Text("转账", bundle: .mimiModule)
                                        .mimiFont(14, weight: .semibold)
                                        .foregroundColor(MimiTheme.textPrimary)
                                }
                            } else {
                                Button {
                                    showCategoryPicker = true
                                } label: {
                                    HStack(spacing: 8) {
                                        MimiStickerIconView(
                                            iconName: editableBill.iconName,
                                            categoryName: editableBill.categoryPath,
                                            transactionType: editableBill.type,
                                            size: 26
                                        )
                                        Text(editableBill.categoryPath)
                                            .mimiFont(14, weight: .semibold)
                                            .foregroundColor(MimiTheme.textPrimary)
                                        Image(systemName: "chevron.right")
                                            .mimiFont(11)
                                            .foregroundColor(MimiTheme.textMuted)
                                    }
                                }
                                .mimiPressable()
                                .accessibilityLabel(MimiL10n.string("分类"))
                                .accessibilityHint(MimiL10n.string("选择标准分类"))
                            }
                        }

                        Divider().padding(.leading, 16)

                        // Note + Receipt Photo Attachments (IMG_2242 & IMG_2243)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("备注", bundle: .mimiModule)
                                    .mimiFont(14, weight: .medium)
                                    .foregroundColor(MimiTheme.textSecondary)
                                Spacer()
                                TextField("添加备注...", text: $editableBill.note)
                                    .mimiFont(14)
                                    .multilineTextAlignment(.trailing)
                            }

                            // Real Image Thumbnails + Add Photo Button
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(editableBill.receiptImageLabels.enumerated()), id: \.offset) { idx, path in
                                        let imageData = store.loadReceiptImageData(filename: path)
                                        ZStack(alignment: .topTrailing) {
                                            Group {
                                                #if canImport(UIKit)
                                                if let data = imageData, let uiImage = UIImage(data: data) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 58, height: 58)
                                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                                } else {
                                                    fallbackDocIcon(label: path)
                                                }
                                                #else
                                                fallbackDocIcon(label: path)
                                                #endif
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                if let data = imageData ?? store.loadReceiptImageData(filename: path) {
                                                    activeViewerItem = ReceiptViewerItem(imageData: data)
                                                }
                                            }

                                            // Delete receipt button
                                            Button {
                                                if idx < editableBill.receiptImageLabels.count {
                                                    let removed = editableBill.receiptImageLabels.remove(at: idx)
                                                    store.deleteReceiptImage(filename: removed)
                                                }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .mimiFont(16)
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(Color.black.opacity(0.65)))
                                            }
                                            .offset(x: 4, y: -4)
                                        }
                                    }

                                    Button {
                                        showingActionSheet = true
                                    } label: {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                            .foregroundColor(MimiTheme.textMuted)
                                            .frame(width: 58, height: 58)
                                            .overlay(
                                                Image(systemName: "plus")
                                                    .mimiFont(20, weight: .medium)
                                                    .foregroundColor(MimiTheme.textMuted)
                                            )
                                    }
                                    .mimiPressable()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(16)
                    }
                    .background(RoundedRectangle(cornerRadius: 18).fill(MimiTheme.cardBackground))

                    // Time, Account & Ledger Card
                    VStack(spacing: 0) {
                        detailRow(label: "账单时间") {
                            MimiDateFieldButton(
                                date: $editableBill.date,
                                mode: .dateAndTime,
                                title: "日期"
                            )
                        }

                        Divider().padding(.leading, 16)

                        detailRow(label: editableBill.type == .transfer ? "转出账户" : "付款账户") {
                            Menu {
                                Button(MimiL10n.string("不选账户")) { editableBill.accountName = "不选账户" }
                                ForEach(store.accounts) { acc in
                                    Button(acc.name) { editableBill.accountName = acc.name }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(editableBill.accountName)
                                        .mimiFont(14, weight: .semibold)
                                        .foregroundColor(MimiTheme.textPrimary)
                                    Image(systemName: "chevron.right")
                                        .mimiFont(11)
                                        .foregroundColor(MimiTheme.textMuted)
                                }
                            }
                        }

                        if editableBill.type == .transfer {
                            Divider().padding(.leading, 16)
                            detailRow(label: "转入账户") {
                                Menu {
                                    ForEach(store.accounts) { acc in
                                        Button(acc.name) { editableBill.targetAccountName = acc.name }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(editableBill.targetAccountName ?? "选择转入账户")
                                            .mimiFont(14, weight: .semibold)
                                            .foregroundColor(MimiTheme.textPrimary)
                                        Image(systemName: "chevron.right")
                                            .mimiFont(11)
                                            .foregroundColor(MimiTheme.textMuted)
                                    }
                                }
                            }
                        }

                        Divider().padding(.leading, 16)

                        detailRow(label: "所属账本") {
                            Menu {
                                ForEach(store.ledgers) { ledger in
                                    Button(ledger.name) {
                                        editableBill.ledgerName = ledger.name
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "book.closed.fill")
                                        .mimiFont(14)
                                        .foregroundColor(MimiTheme.vipGold)
                                    Text(editableBill.ledgerName)
                                        .mimiFont(14, weight: .medium)
                                        .foregroundColor(MimiTheme.textPrimary)
                                    Image(systemName: "chevron.right")
                                        .mimiFont(11)
                                        .foregroundColor(MimiTheme.textMuted)
                                }
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 18).fill(MimiTheme.cardBackground))

                    // Discount, Refund/Cashback & Counterparty Card (IMG_2242 & IMG_2243)
                    VStack(spacing: 0) {
                        detailRow(label: "添加优惠") {
                            TextField("RM0.00", text: $discountString)
                                .mimiFont(14)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }

                        Divider().padding(.leading, 16)

                        detailRow(label: "添加退款/返现") {
                            TextField("RM0.00", text: $refundString)
                                .mimiFont(14)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }

                        Divider().padding(.leading, 16)

                        detailRow(label: "交易方") {
                            TextField("如：咖啡店 / 超市", text: $editableBill.counterparty)
                                .mimiFont(14)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 18).fill(MimiTheme.cardBackground))

                    if editableBill.type != .transfer {
                        VStack(spacing: 0) {
                            Toggle(isOn: $editableBill.includeInStats) {
                                Text("计入收支统计", bundle: .mimiModule)
                                    .mimiFont(14, weight: .medium)
                                    .foregroundColor(MimiTheme.textPrimary)
                            }
                            .tint(MimiTheme.expenseBlue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().padding(.leading, 16)

                            Toggle(isOn: $editableBill.includeInBudget) {
                                Text("计入预算", bundle: .mimiModule)
                                    .mimiFont(14, weight: .medium)
                                    .foregroundColor(MimiTheme.textPrimary)
                            }
                            .tint(MimiTheme.expenseBlue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().padding(.leading, 16)

                            Toggle(isOn: Binding(
                                get: {
                                    editableBill.tags.contains(where: {
                                        let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                        return t == "待报销" || t == "报销"
                                    })
                                },
                                set: { on in
                                    editableBill.tags.removeAll {
                                        let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                        return t == "待报销" || t == "报销"
                                    }
                                    if on { editableBill.tags.append("待报销") }
                                }
                            )) {
                                Text("待报销", bundle: .mimiModule)
                                    .mimiFont(14, weight: .medium)
                                    .foregroundColor(MimiTheme.textPrimary)
                            }
                            .tint(MimiTheme.expenseBlue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider().padding(.leading, 16)

                            detailRow(label: "标签") {
                                let availableTags: [String] = {
                                    var result = store.tags
                                    for t in editableBill.tags where !result.contains(t) && t != "待报销" {
                                        result.append(t)
                                    }
                                    return result
                                }()
                                Menu {
                                    ForEach(availableTags, id: \.self) { tag in
                                        Button {
                                            if editableBill.tags.contains(tag) {
                                                editableBill.tags.removeAll { $0 == tag }
                                            } else {
                                                editableBill.tags.append(tag)
                                            }
                                        } label: {
                                            if editableBill.tags.contains(tag) {
                                                Label(tag, systemImage: "checkmark")
                                            } else {
                                                Text(tag)
                                            }
                                        }
                                    }
                                    if !editableBill.tags.isEmpty {
                                        Divider()
                                        Button(role: .destructive) {
                                            editableBill.tags.removeAll()
                                        } label: {
                                            Label(MimiL10n.string("清空标签"), systemImage: "trash")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(editableBill.tags.isEmpty
                                             ? "选择标签"
                                             : editableBill.tags.joined(separator: "、"))
                                            .mimiFont(14, weight: .semibold)
                                            .foregroundColor(MimiTheme.textPrimary)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.right")
                                            .mimiFont(11)
                                            .foregroundColor(MimiTheme.textMuted)
                                    }
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 18).fill(MimiTheme.cardBackground))
                    }
                }
                .padding(16)
            }
            .background(MimiTheme.background.ignoresSafeArea())
            .navigationTitle(MimiL10n.string("账单详情"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.down")
                            .mimiFont(14, weight: .bold)
                            .foregroundColor(MimiTheme.textSecondary)
                            .mimiMinTouchTarget()
                    }
                    .accessibilityLabel(MimiL10n.string("关闭账单详情"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .mimiFont(14, weight: .semibold)
                            .foregroundColor(MimiTheme.dangerRed)
                            .mimiMinTouchTarget()
                    }
                    .accessibilityLabel(MimiL10n.string("删除账单"))
                }
            }
            .confirmationDialog(MimiL10n.string("删除这笔账单？"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(MimiL10n.string("删除"), role: .destructive) {
                    skipAutoSave = true
                    store.deleteTransaction(id: editableBill.id)
                    onDismiss()
                }
                Button(MimiL10n.string("取消"), role: .cancel) {}
            } message: {
                Text("删除后无法恢复", bundle: .mimiModule)
            }
            .sheet(isPresented: $showingActionSheet) {
                MimiChoiceSheet(
                    title: "添加小票或截图",
                    items: [
                        MimiChoiceItem(id: "camera", icon: "camera", title: "拍摄真实小票", subtitle: "拍纸质小票"),
                        MimiChoiceItem(id: "album", icon: "photo.on.rectangle", title: "从相册选择", subtitle: "小票或付款截图")
                    ],
                    onSelect: { item in
                        showingActionSheet = false
                        #if canImport(UIKit)
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + MimiMotion.handoffDelay(.sheet, reduceMotion: reduceMotion)
                        ) {
                            switch item.id {
                            case "camera":
                                pickerSourceType = .camera
                                showingImagePicker = true
                            case "album":
                                pickerSourceType = .photoLibrary
                                showingImagePicker = true
                            default:
                                break
                            }
                        }
                        #endif
                    },
                    onCancel: { showingActionSheet = false }
                )
                #if os(iOS)
                .mimiInteractiveSheet(detents: [.height(300)], showDragIndicator: false)
                .presentationCornerRadius(24)
                #endif
            }
            .sheet(isPresented: $showAmountKeypad) {
                amountKeypadSheet
                    .mimiInteractiveSheet(detents: [.height(420)])
            }
            .sheet(isPresented: $showCategoryPicker) {
                BillCategoryPickerSheet(
                    store: store,
                    initialType: editableBill.type,
                    initialCategoryPath: editableBill.categoryPath,
                    onConfirm: { type, path, icon in
                        editableBill.type = type
                        editableBill.categoryPath = path
                        editableBill.iconName = icon
                        showCategoryPicker = false
                    },
                    onDismiss: { showCategoryPicker = false },
                    onEditCategories: {
                        showCategoryPicker = false
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + MimiMotion.handoffDelay(.sheet, reduceMotion: reduceMotion)
                        ) {
                            showCategoryEditor = true
                        }
                    }
                )
                .mimiInteractiveSheet(detents: [.large])
            }
            .sheet(isPresented: $showCategoryEditor) {
                CategoryManagementView(store: store) {
                    showCategoryEditor = false
                }
                .mimiInteractiveSheet(detents: [.large])
            }
            #if canImport(UIKit)
            .sheet(isPresented: $showingImagePicker) {
                UIKitImagePicker(sourceType: pickerSourceType) { pickedImage in
                    if let data = pickedImage.jpegData(compressionQuality: 0.8) {
                        let filename = store.saveReceiptImage(data: data)
                        editableBill.receiptImageLabels.append(filename)
                    }
                }
            }
            #endif
            #if os(iOS)
            .fullScreenCover(item: $activeViewerItem) { item in
                FullscreenReceiptViewer(imageData: item.imageData) {
                    activeViewerItem = nil
                }
            }
            #else
            .sheet(item: $activeViewerItem) { item in
                FullscreenReceiptViewer(imageData: item.imageData) {
                    activeViewerItem = nil
                }
            }
            #endif
        }
        // Leave-to-save: swipe-down dismiss, edge-swipe back, close button — any path that
        // removes this screen. Nested sheets (分类 / 金额键盘) do not tear down NavigationStack.
        .onDisappear {
            autoSaveOnLeave()
        }
    }

    // MARK: - 实付金额数字键盘（与记账页同风格）

    private var amountKeypadSheet: some View {
        let accent = editableBill.type == .expense ? MimiTheme.expenseBlue : MimiTheme.incomeOrange
        let rows: [[String]] = [
            ["7", "8", "9", "⌫"],
            ["4", "5", "6", "-"],
            ["1", "2", "3", "+"],
            ["清空", "0", ".", "完成"]
        ]

        return VStack(spacing: 16) {
            Capsule()
                .fill(MimiTheme.strokeSubtle)
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Text("实付金额", bundle: .mimiModule)
                .mimiFont(15, weight: .semibold)
                .foregroundColor(MimiTheme.textSecondary)

            Text(amountExpression.isEmpty ? "RM0.00" : "RM\(amountExpression)")
                .mimiFont(32, weight: .bold, design: .rounded)
                .foregroundColor(accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)

            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                handleAmountKey(key)
                            } label: {
                                Text(key)
                                    .mimiFont(key == "完成" || key == "清空" ? 15 : 20, weight: .semibold, design: .rounded)
                                    .foregroundColor(key == "完成" ? .white : MimiTheme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(key == "完成" ? accent : Color.white)
                                    )
                            }
                            .mimiPressable()
                        }
                    }
                }
            }
            .padding(10)
            .background(MimiTheme.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(MimiTheme.cardBackground.ignoresSafeArea())
    }

    private func handleAmountKey(_ key: String) {
        switch key {
        case "⌫":
            if !amountExpression.isEmpty {
                amountExpression.removeLast()
            }
        case "清空":
            amountExpression = ""
        case "完成":
            let value = max(0.0, KeypadCalculator.evaluate(amountExpression))
            if value > 0 {
                amountString = String(format: "%.2f", value)
                editableBill.amount = value
            }
            // Invalid/zero: keep previous amountString + editableBill.amount (no silent wipe).
            showAmountKeypad = false
        default:
            amountExpression.append(key)
        }
    }

    /// Persist edits when leaving by any path. Invalid amount keeps `previousValidAmount`.
    private func autoSaveOnLeave() {
        guard !skipAutoSave else { return }
        guard store.transactions.contains(where: { $0.id == editableBill.id }) else { return }
        let prepared = BillDetailEditCommit.prepared(
            draft: editableBill,
            amountString: amountString,
            discountString: discountString,
            refundString: refundString,
            previousValidAmount: previousValidAmount
        )
        if let current = store.transactions.first(where: { $0.id == prepared.id }), current == prepared {
            return
        }
        store.updateTransaction(prepared)
    }

    private func fallbackDocIcon(label: String) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(MimiTheme.chipFill)
            .frame(width: 58, height: 58)
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: "doc.text.image")
                        .mimiFont(18)
                        .foregroundColor(MimiTheme.expenseBlue)
                    Text(label)
                        .mimiFont(8)
                        .foregroundColor(MimiTheme.textSecondary)
                        .lineLimit(1)
                }
            )
    }

    private func detailRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .mimiFont(14, weight: .medium)
                .foregroundColor(MimiTheme.textSecondary)
            Spacer()
            content()
        }
        .padding(16)
    }
}
