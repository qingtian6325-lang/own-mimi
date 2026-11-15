import SwiftUI

public struct MimiStickerIconView: View {
    public let iconName: String
    public let categoryName: String
    public let transactionType: TransactionType
    public let useFirstCharIcon: Bool
    public let size: CGFloat
    public let isSelected: Bool

    public init(
        iconName: String,
        categoryName: String = "",
        transactionType: TransactionType = .expense,
        useFirstCharIcon: Bool = false,
        size: CGFloat = 38,
        isSelected: Bool = false
    ) {
        self.iconName = iconName
        self.categoryName = categoryName
        self.transactionType = transactionType
        self.useFirstCharIcon = useFirstCharIcon
        self.size = size
        self.isSelected = isSelected
    }

    public init(name: String, size: CGFloat = 38) {
        self.init(iconName: name, size: size)
    }

    private var firstCharText: String {
        let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else {
            return String(iconName.prefix(1))
        }
        return String(first)
    }

    private var isCustomFirstCharToken: Bool {
        if useFirstCharIcon { return true }
        if iconName.count == 1, let scalar = iconName.unicodeScalars.first, scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
            return true
        }
        return false
    }

    public var body: some View {
        if isCustomFirstCharToken {
            ZStack {
                Circle()
                    .fill(
                        transactionType == .expense
                            ? MimiTheme.expenseBlue
                            : MimiTheme.incomeOrange
                    )
                    .frame(width: size, height: size)

                Text(iconName.count == 1 ? iconName : firstCharText)
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .overlay(
                Circle()
                    .strokeBorder(
                        isSelected ? MimiTheme.expenseBlue : Color.clear,
                        lineWidth: 2
                    )
            )
        } else {
            let spec = Self.stickerSpec(for: iconName, fallbackName: categoryName)
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: size, height: size)
                    .shadow(color: Color.black.opacity(0.04), radius: size * 0.02, x: 0, y: size * 0.006)

                Circle()
                    .fill(spec.background)
                    .frame(width: size * 0.90, height: size * 0.90)

                MimiStickerGlyphView(kind: spec.glyph, systemName: spec.systemName, size: size * 0.58)
            }
            .compositingGroup()
            .overlay(
                Circle()
                    .strokeBorder(
                        isSelected
                            ? (transactionType == .expense ? MimiTheme.expenseBlue : MimiTheme.incomeOrange)
                            : Color.black.opacity(0.10),
                        lineWidth: isSelected ? 2.0 : 1.0
                    )
            )
        }
    }

    public enum GlyphKind: String, Sendable, CaseIterable {
        case noodles, leaf, takeout, coffee, drink, snack, wine
        case bag, clothes, beauty, headphones, scissors, box, tag, gift
        case bus, car, taxi, train, fuel, parking, ticket
        case house, bulb, phone, key, wrench, broom, drop
        case ferris, sports, game, plane, palette, tv
        case meds, tooth, tea, stethoscope, bandage
        case book, graduation, laptop, piano, pencil
        case paw, bone, petMed, petBath, baby, teddy
        case card, shield, chart, sparkle
        case money, trophy, diamond, store, rocket, coin, umbrella, transfer, person, briefcase
        case system
    }

    public struct StickerSpec: Sendable {
        public let glyph: GlyphKind
        public let background: Color
        public let systemName: String

        public init(glyph: GlyphKind, background: Color, systemName: String = "") {
            self.glyph = glyph
            self.background = background
            self.systemName = systemName
        }

        /// Backward-compatible helper used by older call sites that expected SF Symbol specs.
        public init(systemName: String, background: Color, tint: Color = Color(hex: 0x5C4A3A)) {
            _ = tint
            if let mapped = MimiStickerIconView.glyph(forSystemName: systemName) {
                self.glyph = mapped
                self.background = background
                self.systemName = ""
            } else {
                self.glyph = .system
                self.background = background
                self.systemName = systemName
            }
        }
    }

    private static func ink(_ hex: UInt32) -> Color { Color(hex: hex) }

    public static func stickerSpec(for key: String, fallbackName: String = "") -> StickerSpec {
        let normalized = String(key.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E }.map { Character($0) })
        if let home = homeGoldSpec(normalizedKey: normalized, hint: fallbackName) {
            return home
        }

        // Already an SF Symbol token from the picker
        if key.contains("."), !key.contains(" ") {
            if let glyph = glyph(forSystemName: key) {
                return StickerSpec(glyph: glyph, background: Color(hex: 0xFFF3E0))
            }
            return StickerSpec(glyph: .system, background: Color(hex: 0xFFF3E0), systemName: key)
        }

        switch key {
        case "food_group", "food_restaurant":
            return StickerSpec(glyph: .noodles, background: Color(hex: 0xFFE0B2))
        case "food_ingredients":
            return StickerSpec(glyph: .leaf, background: Color(hex: 0xE8F5E9))
        case "food_takeout":
            return StickerSpec(glyph: .takeout, background: Color(hex: 0xFFF8E1))
        case "food_coffee":
            return StickerSpec(glyph: .coffee, background: Color(hex: 0xEFEBE9))
        case "food_drink":
            return StickerSpec(glyph: .drink, background: Color(hex: 0xFCE4EC))
        case "food_snack":
            return StickerSpec(glyph: .snack, background: Color(hex: 0xFFF3E0))
        case "food_bar":
            return StickerSpec(glyph: .wine, background: Color(hex: 0xF3E5F5))

        case "shop_group", "shop_daily":
            return StickerSpec(glyph: .bag, background: Color(hex: 0xE3F2FD))
        case "shop_clothes":
            return StickerSpec(glyph: .clothes, background: Color(hex: 0xFCE4EC))
        case "shop_beauty":
            return StickerSpec(glyph: .beauty, background: Color(hex: 0xF8BBD0).opacity(0.35))
        case "shop_digital":
            return StickerSpec(glyph: .headphones, background: Color(hex: 0xE8EAF6))
        case "shop_care":
            return StickerSpec(glyph: .scissors, background: Color(hex: 0xF3E5F5))
        case "shop_shipping":
            return StickerSpec(glyph: .box, background: Color(hex: 0xFFF3E0))
        case "shop_secondhand":
            return StickerSpec(glyph: .tag, background: Color(hex: 0xE0F2F1))

        case "trans_group", "trans_bus":
            return StickerSpec(glyph: .bus, background: Color(hex: 0xE3F2FD))
        case "trans_taxi":
            return StickerSpec(glyph: .taxi, background: Color(hex: 0xFFFDE7))
        case "trans_train":
            return StickerSpec(glyph: .train, background: Color(hex: 0xE8EAF6))
        case "trans_fuel":
            return StickerSpec(glyph: .fuel, background: Color(hex: 0xD6F1FA))
        case "trans_parking":
            return StickerSpec(glyph: .parking, background: Color(hex: 0xE3F2FD))
        case "trans_car":
            return StickerSpec(glyph: .car, background: Color(hex: 0xE0F7FA))
        case "trans_card":
            return StickerSpec(glyph: .ticket, background: Color(hex: 0xF1F8E9))

        case "house_group", "house_rent":
            return StickerSpec(glyph: .house, background: Color(hex: 0xFFF3E0))
        case "house_util":
            return StickerSpec(glyph: .bulb, background: Color(hex: 0xFFF6D0))
        case "house_phone":
            return StickerSpec(glyph: .phone, background: Color(hex: 0xE3F2FD))
        case "house_prop":
            return StickerSpec(glyph: .key, background: Color(hex: 0xFFF8E1))
        case "house_repair":
            return StickerSpec(glyph: .wrench, background: Color(hex: 0xECEFF1))
        case "house_clean":
            return StickerSpec(glyph: .broom, background: Color(hex: 0xE8F5E9))

        case "fun_group":
            return StickerSpec(glyph: .ferris, background: Color(hex: 0xF3E5F5))
        case "fun_offline":
            return StickerSpec(glyph: .ticket, background: Color(hex: 0xFFE3C2))
        case "fun_sport":
            return StickerSpec(glyph: .sports, background: Color(hex: 0xE8F5E9))
        case "fun_digital":
            return StickerSpec(glyph: .game, background: Color(hex: 0xE8EAF6))
        case "fun_travel":
            return StickerSpec(glyph: .plane, background: Color(hex: 0xE1F5FE))
        case "fun_hobby":
            return StickerSpec(glyph: .palette, background: Color(hex: 0xFFF3E0))
        case "fun_sub":
            return StickerSpec(glyph: .tv, background: Color(hex: 0xFCE4EC))

        case "med_group", "med_doctor":
            return StickerSpec(glyph: .meds, background: Color(hex: 0xFFEBEE))
        case "med_dental":
            return StickerSpec(glyph: .tooth, background: Color(hex: 0xE1F5FE))
        case "med_health":
            return StickerSpec(glyph: .tea, background: Color(hex: 0xE8F5E9))
        case "med_checkup":
            return StickerSpec(glyph: .stethoscope, background: Color(hex: 0xE0F2F1))
        case "med_rehab":
            return StickerSpec(glyph: .bandage, background: Color(hex: 0xFFF3E0))

        case "study_group", "study_book":
            return StickerSpec(glyph: .book, background: Color(hex: 0xE3F2FD))
        case "study_tuition":
            return StickerSpec(glyph: .graduation, background: Color(hex: 0xE8EAF6))
        case "study_pro":
            return StickerSpec(glyph: .laptop, background: Color(hex: 0xECEFF1))
        case "study_hobby":
            return StickerSpec(glyph: .piano, background: Color(hex: 0xF3E5F5))

        case "pet_group", "pet_food":
            return StickerSpec(glyph: .paw, background: Color(hex: 0xFFF3E0))
        case "pet_supply":
            return StickerSpec(glyph: .bone, background: Color(hex: 0xFFF8E1))
        case "pet_med":
            return StickerSpec(glyph: .petMed, background: Color(hex: 0xFFEBEE))
        case "pet_service":
            return StickerSpec(glyph: .petBath, background: Color(hex: 0xE1F5FE))
        case "baby_group", "baby_food":
            return StickerSpec(glyph: .baby, background: Color(hex: 0xFCE4EC))
        case "baby_supply":
            return StickerSpec(glyph: .teddy, background: Color(hex: 0xFFF3E0))
        case "baby_service":
            return StickerSpec(glyph: .baby, background: Color(hex: 0xF3E5F5))

        case "fund_group", "fund_repay":
            return StickerSpec(glyph: .card, background: Color(hex: 0xE3F2FD))
        case "fund_gift":
            return StickerSpec(glyph: .gift, background: Color(hex: 0xFFEBEE))
        case "ins_group":
            return StickerSpec(glyph: .shield, background: Color(hex: 0xE8F5E9))
        case "inv_group":
            return StickerSpec(glyph: .chart, background: Color(hex: 0xFFF3C4))
        case "other_exp":
            return StickerSpec(glyph: .sparkle, background: Color(hex: 0xF3E5F5))

        case "inc_job":
            return StickerSpec(glyph: .money, background: Color(hex: 0xFFF3E0))
        case "inc_bonus":
            return StickerSpec(glyph: .trophy, background: Color(hex: 0xFFF8E1))
        case "inc_allowance":
            return StickerSpec(glyph: .diamond, background: Color(hex: 0xE1F5FE))
        case "inc_biz":
            return StickerSpec(glyph: .store, background: Color(hex: 0xFFF3E0))
        case "inc_side":
            return StickerSpec(glyph: .rocket, background: Color(hex: 0xE8EAF6))
        case "inc_invest", "inc_dividend", "inc_interest":
            return StickerSpec(glyph: .coin, background: Color(hex: 0xFFF8E1))
        case "inc_claim":
            return StickerSpec(glyph: .umbrella, background: Color(hex: 0xE8F5E9))
        case "inc_refund", "inc_cashback", "inc_reimburse", "inc_repay", "inc_tax":
            return StickerSpec(glyph: .transfer, background: Color(hex: 0xE0F2F1))
        case "inc_gift", "inc_living":
            return StickerSpec(glyph: .gift, background: Color(hex: 0xFCE4EC))
        case "inc_other", "inc_secondhand", "inc_luck":
            return StickerSpec(glyph: .leaf, background: Color(hex: 0xE8F5E9))

        default:
            if let mapped = glyphForLegacyEmoji(normalized) {
                return mapped
            }
            return StickerSpec(glyph: .sparkle, background: Color(hex: 0xFFF3E0))
        }
    }

    /// Catalog still stores emoji keys; map them to Canvas sticker glyphs so UI never renders emoji.
    private static func glyphForLegacyEmoji(_ key: String) -> StickerSpec? {
        let table: [String: StickerSpec] = [
            "🍜": StickerSpec(glyph: .noodles, background: Color(hex: 0xFFE0B2)),
            "🎃": StickerSpec(glyph: .leaf, background: Color(hex: 0xE8F5E9)),
            "🛍️": StickerSpec(glyph: .bag, background: Color(hex: 0xE3F2FD)),
            "🛍": StickerSpec(glyph: .bag, background: Color(hex: 0xE3F2FD)),
            "☕": StickerSpec(glyph: .coffee, background: Color(hex: 0xEFEBE9)),
            "☕️": StickerSpec(glyph: .coffee, background: Color(hex: 0xEFEBE9)),
            "🥤": StickerSpec(glyph: .drink, background: Color(hex: 0xFCE4EC)),
            "🧋": StickerSpec(glyph: .drink, background: Color(hex: 0xFCE4EC)),
            "🍟": StickerSpec(glyph: .snack, background: Color(hex: 0xFFF3E0)),
            "🍮": StickerSpec(glyph: .snack, background: Color(hex: 0xFFF3E0)),
            "🍺": StickerSpec(glyph: .wine, background: Color(hex: 0xF3E5F5)),
            "🍹": StickerSpec(glyph: .wine, background: Color(hex: 0xF3E5F5)),
            "🍱": StickerSpec(glyph: .takeout, background: Color(hex: 0xFFF8E1)),
            "🥬": StickerSpec(glyph: .leaf, background: Color(hex: 0xE8F5E9)),
            "🧺": StickerSpec(glyph: .bag, background: Color(hex: 0xE3F2FD)),
            "👕": StickerSpec(glyph: .clothes, background: Color(hex: 0xFCE4EC)),
            "👗": StickerSpec(glyph: .clothes, background: Color(hex: 0xFCE4EC)),
            "🧴": StickerSpec(glyph: .beauty, background: Color(hex: 0xF8BBD0).opacity(0.35)),
            "💄": StickerSpec(glyph: .beauty, background: Color(hex: 0xF8BBD0).opacity(0.35)),
            "📷": StickerSpec(glyph: .headphones, background: Color(hex: 0xE8EAF6)),
            "🎧": StickerSpec(glyph: .headphones, background: Color(hex: 0xE8EAF6)),
            "🧻": StickerSpec(glyph: .bag, background: Color(hex: 0xE3F2FD)),
            "🧼": StickerSpec(glyph: .broom, background: Color(hex: 0xE8F5E9)),
            "💇‍♀️": StickerSpec(glyph: .scissors, background: Color(hex: 0xF3E5F5)),
            "📦": StickerSpec(glyph: .box, background: Color(hex: 0xFFF3E0)),
            "🎁": StickerSpec(glyph: .gift, background: Color(hex: 0xFCE4EC)),
            "🏷️": StickerSpec(glyph: .tag, background: Color(hex: 0xE0F2F1)),
            "🚗": StickerSpec(glyph: .car, background: Color(hex: 0xE0F7FA)),
            "🚙": StickerSpec(glyph: .car, background: Color(hex: 0xE0F7FA)),
            "🚌": StickerSpec(glyph: .bus, background: Color(hex: 0xE3F2FD)),
            "🚕": StickerSpec(glyph: .taxi, background: Color(hex: 0xFFFDE7)),
            "🚄": StickerSpec(glyph: .train, background: Color(hex: 0xE8EAF6)),
            "⛽": StickerSpec(glyph: .fuel, background: Color(hex: 0xD6F1FA)),
            "⛽️": StickerSpec(glyph: .fuel, background: Color(hex: 0xD6F1FA)),
            "🅿️": StickerSpec(glyph: .parking, background: Color(hex: 0xE3F2FD)),
            "🎫": StickerSpec(glyph: .ticket, background: Color(hex: 0xF1F8E9)),
            "🪪": StickerSpec(glyph: .ticket, background: Color(hex: 0xF1F8E9)),
            "🏠": StickerSpec(glyph: .house, background: Color(hex: 0xFFF3E0)),
            "🏡": StickerSpec(glyph: .house, background: Color(hex: 0xFFF3E0)),
            "💧": StickerSpec(glyph: .drop, background: Color(hex: 0xE1F5FE)),
            "💡": StickerSpec(glyph: .bulb, background: Color(hex: 0xFFF6D0)),
            "🖥️": StickerSpec(glyph: .laptop, background: Color(hex: 0xE3F2FD)),
            "📱": StickerSpec(glyph: .phone, background: Color(hex: 0xE3F2FD)),
            "🏢": StickerSpec(glyph: .store, background: Color(hex: 0xFFF8E1)),
            "🔑": StickerSpec(glyph: .key, background: Color(hex: 0xFFF8E1)),
            "🖌️": StickerSpec(glyph: .palette, background: Color(hex: 0xECEFF1)),
            "🛠️": StickerSpec(glyph: .wrench, background: Color(hex: 0xECEFF1)),
            "🧹": StickerSpec(glyph: .broom, background: Color(hex: 0xE8F5E9)),
            "🏀": StickerSpec(glyph: .sports, background: Color(hex: 0xFFF3E0)),
            "🏸": StickerSpec(glyph: .sports, background: Color(hex: 0xE8F5E9)),
            "🎟️": StickerSpec(glyph: .ticket, background: Color(hex: 0xFFE3C2)),
            "🎟": StickerSpec(glyph: .ticket, background: Color(hex: 0xFFE3C2)),
            "🎮": StickerSpec(glyph: .game, background: Color(hex: 0xE8EAF6)),
            "🚩": StickerSpec(glyph: .plane, background: Color(hex: 0xE1F5FE)),
            "✈️": StickerSpec(glyph: .plane, background: Color(hex: 0xE1F5FE)),
            "🎨": StickerSpec(glyph: .palette, background: Color(hex: 0xFFF3E0)),
            "💳": StickerSpec(glyph: .card, background: Color(hex: 0xE3F2FD)),
            "📺": StickerSpec(glyph: .tv, background: Color(hex: 0xFCE4EC)),
            "🏥": StickerSpec(glyph: .meds, background: Color(hex: 0xFFEBEE)),
            "💊": StickerSpec(glyph: .meds, background: Color(hex: 0xFFEBEE)),
            "🦷": StickerSpec(glyph: .tooth, background: Color(hex: 0xE1F5FE)),
            "🫙": StickerSpec(glyph: .tea, background: Color(hex: 0xE8F5E9)),
            "🍵": StickerSpec(glyph: .tea, background: Color(hex: 0xE8F5E9)),
            "💉": StickerSpec(glyph: .stethoscope, background: Color(hex: 0xE0F2F1)),
            "🩺": StickerSpec(glyph: .stethoscope, background: Color(hex: 0xE0F2F1)),
            "🩹": StickerSpec(glyph: .bandage, background: Color(hex: 0xFFF3E0)),
            "🧑‍⚕️": StickerSpec(glyph: .meds, background: Color(hex: 0xFFEBEE)),
            "📖": StickerSpec(glyph: .book, background: Color(hex: 0xE3F2FD)),
            "📚": StickerSpec(glyph: .book, background: Color(hex: 0xE3F2FD)),
            "🎓": StickerSpec(glyph: .graduation, background: Color(hex: 0xE8EAF6)),
            "💻": StickerSpec(glyph: .laptop, background: Color(hex: 0xECEFF1)),
            "🎹": StickerSpec(glyph: .piano, background: Color(hex: 0xF3E5F5)),
            "✏️": StickerSpec(glyph: .pencil, background: Color(hex: 0xE3F2FD)),
            "🐱": StickerSpec(glyph: .paw, background: Color(hex: 0xFFF3E0)),
            "🐶": StickerSpec(glyph: .paw, background: Color(hex: 0xFFF3E0)),
            "🦴": StickerSpec(glyph: .bone, background: Color(hex: 0xFFF8E1)),
            "🐾": StickerSpec(glyph: .paw, background: Color(hex: 0xFFF3E0)),
            "🐕": StickerSpec(glyph: .petMed, background: Color(hex: 0xFFEBEE)),
            "✂️": StickerSpec(glyph: .scissors, background: Color(hex: 0xE1F5FE)),
            "🛁": StickerSpec(glyph: .petBath, background: Color(hex: 0xE1F5FE)),
            "👶": StickerSpec(glyph: .baby, background: Color(hex: 0xFCE4EC)),
            "🍼": StickerSpec(glyph: .baby, background: Color(hex: 0xFCE4EC)),
            "🧸": StickerSpec(glyph: .teddy, background: Color(hex: 0xFFF3E0)),
            "🎠": StickerSpec(glyph: .baby, background: Color(hex: 0xF3E5F5)),
            "🛒": StickerSpec(glyph: .bag, background: Color(hex: 0xFFF3E0)),
            "🧷": StickerSpec(glyph: .baby, background: Color(hex: 0xF3E5F5)),
            "🧧": StickerSpec(glyph: .gift, background: Color(hex: 0xFFEBEE)),
            "🗓️": StickerSpec(glyph: .card, background: Color(hex: 0xE3F2FD)),
            "🛡️": StickerSpec(glyph: .shield, background: Color(hex: 0xE8F5E9)),
            "📈": StickerSpec(glyph: .chart, background: Color(hex: 0xFFF3C4)),
            "✨": StickerSpec(glyph: .sparkle, background: Color(hex: 0xF3E5F5)),
            "💰": StickerSpec(glyph: .money, background: Color(hex: 0xFFF3E0)),
            "🏆": StickerSpec(glyph: .trophy, background: Color(hex: 0xFFF8E1)),
            "💎": StickerSpec(glyph: .diamond, background: Color(hex: 0xE1F5FE)),
            "💴": StickerSpec(glyph: .money, background: Color(hex: 0xE1F5FE)),
            "🏪": StickerSpec(glyph: .store, background: Color(hex: 0xFFF3E0)),
            "💼": StickerSpec(glyph: .briefcase, background: Color(hex: 0xE8EAF6)),
            "🚀": StickerSpec(glyph: .rocket, background: Color(hex: 0xE8EAF6)),
            "🪙": StickerSpec(glyph: .coin, background: Color(hex: 0xFFF8E1)),
            "📊": StickerSpec(glyph: .chart, background: Color(hex: 0xFFF8E1)),
            "☂️": StickerSpec(glyph: .umbrella, background: Color(hex: 0xE8F5E9)),
            "☔": StickerSpec(glyph: .umbrella, background: Color(hex: 0xE8F5E9)),
            "💸": StickerSpec(glyph: .transfer, background: Color(hex: 0xE0F2F1)),
            "📑": StickerSpec(glyph: .card, background: Color(hex: 0xE0F2F1)),
            "🧾": StickerSpec(glyph: .card, background: Color(hex: 0xE0F2F1)),
            "🤝": StickerSpec(glyph: .transfer, background: Color(hex: 0xE0F2F1)),
            "🏦": StickerSpec(glyph: .store, background: Color(hex: 0xE0F2F1)),
            "🍀": StickerSpec(glyph: .leaf, background: Color(hex: 0xE8F5E9)),
            "🧑": StickerSpec(glyph: .person, background: Color(hex: 0xFFE6CC)),
            "🎡": StickerSpec(glyph: .ferris, background: Color(hex: 0xF3E5F5))
        ]
        return table[key]
    }

    private static func homeGoldSpec(normalizedKey key: String, hint: String) -> StickerSpec? {
        if key == "💡"
            || key == "house_util"
            || hint.contains("控制中心")
            || hint.contains("灯泡")
            || hint.contains("电灯")
            || hint.contains("物业水电") {
            return StickerSpec(glyph: .bulb, background: Color(hex: 0xFFF6D0))
        }
        if key == "⛽" || key == "trans_fuel" || hint.contains("加油") {
            return StickerSpec(glyph: .fuel, background: Color(hex: 0xD6F1FA))
        }
        if key == "🍜" || key == "food_restaurant" || key == "food_group" || hint.contains("餐厅") {
            return StickerSpec(glyph: .noodles, background: Color(hex: 0xFFE0B2))
        }
        if key == "📈" || key == "inv_group" || hint == "投资理财" || hint == "投资收入" || hint.hasSuffix("投资理财") {
            return StickerSpec(glyph: .chart, background: Color(hex: 0xFFF3C4))
        }
        if key == "🎟" || key == "fun_offline" || hint.contains("线下娱乐") {
            return StickerSpec(glyph: .ticket, background: Color(hex: 0xFFE3C2))
        }
        let isPersonToken = key.contains("🧑") || key.contains("⚕") || key == "inc_custom_transfer"
        if hint.contains("别人转账") || key == "inc_custom_transfer" || (isPersonToken && hint.contains("转账")) {
            return StickerSpec(glyph: .person, background: Color(hex: 0xFFE6CC))
        }
        return nil
    }

    fileprivate static func glyph(forSystemName name: String) -> GlyphKind? {
        switch name {
        case "fork.knife": return .noodles
        case "leaf.fill", "carrot.fill", "fish.fill": return .leaf
        case "takeoutbag.and.cup.and.straw.fill": return .takeout
        case "cup.and.saucer.fill": return .coffee
        case "wineglass.fill": return .wine
        case "birthday.cake.fill": return .snack
        case "bag.fill", "cart.fill", "basket.fill": return .bag
        case "tshirt.fill": return .clothes
        case "sparkles": return .beauty
        case "headphones", "camera.fill": return .headphones
        case "shippingbox.fill": return .box
        case "tag.fill": return .tag
        case "gift.fill": return .gift
        case "bus.fill": return .bus
        case "car.fill", "car.side.fill": return .car
        case "tram.fill": return .train
        case "fuelpump.fill": return .fuel
        case "parkingsign": return .parking
        case "ticket.fill": return .ticket
        case "airplane", "bicycle": return .plane
        case "house.fill", "sofa.fill": return .house
        case "lightbulb.fill": return .bulb
        case "drop.fill": return .drop
        case "key.fill": return .key
        case "wrench.and.screwdriver.fill": return .wrench
        case "bubbles.and.sparkles.fill": return .broom
        case "iphone", "wifi": return .phone
        case "gamecontroller.fill": return .game
        case "tv.fill", "film", "music.note": return .tv
        case "paintpalette.fill": return .palette
        case "figure.run", "sportscourt.fill": return .sports
        case "ferriswheel": return .ferris
        case "cross.case.fill", "pills.fill", "heart.fill", "syringe.fill": return .meds
        case "stethoscope": return .stethoscope
        case "bandage.fill": return .bandage
        case "mouth.fill": return .tooth
        case "book.fill", "books.vertical.fill", "doc.text.fill", "folder.fill": return .book
        case "graduationcap.fill": return .graduation
        case "laptopcomputer", "desktopcomputer": return .laptop
        case "pencil": return .pencil
        case "pianokeys": return .piano
        case "figure.and.child.holdinghands": return .baby
        case "teddybear.fill": return .teddy
        case "pawprint.fill", "cat.fill", "dog.fill": return .paw
        case "bone.fill": return .bone
        case "banknote.fill", "yensign.circle.fill": return .money
        case "creditcard.fill": return .card
        case "chart.line.uptrend.xyaxis": return .chart
        case "diamond.fill": return .diamond
        case "shield.fill": return .shield
        case "trophy.fill": return .trophy
        case "building.columns.fill", "storefront.fill": return .store
        case "bitcoinsign.circle.fill": return .coin
        case "umbrella.fill": return .umbrella
        case "rocket.fill": return .rocket
        case "arrow.left.arrow.right.circle.fill": return .transfer
        case "person.fill", "person.text.rectangle.fill": return .person
        case "scissors": return .scissors
        default: return nil
        }
    }

    /// Icon picker gallery: SF Symbol names only (no emoji); render maps to Canvas glyphs.
    public static let stickerGalleryItems: [(category: String, icons: [String])] = [
        ("最近使用", [
            "fork.knife", "cup.and.saucer.fill", "bag.fill", "car.fill", "fuelpump.fill",
            "house.fill", "gamecontroller.fill", "pills.fill", "banknote.fill", "gift.fill"
        ]),
        ("餐饮美食", [
            "fork.knife", "takeoutbag.and.cup.and.straw.fill", "cup.and.saucer.fill", "wineglass.fill",
            "birthday.cake.fill", "leaf.fill", "carrot.fill", "fish.fill"
        ]),
        ("日常购物", [
            "bag.fill", "cart.fill", "tshirt.fill", "sparkles", "headphones", "shippingbox.fill",
            "tag.fill", "gift.fill", "basket.fill"
        ]),
        ("交通出行", [
            "bus.fill", "car.fill", "tram.fill", "fuelpump.fill", "parkingsign", "airplane",
            "bicycle", "ticket.fill", "car.side.fill"
        ]),
        ("居家生活", [
            "house.fill", "lightbulb.fill", "drop.fill", "key.fill", "wrench.and.screwdriver.fill",
            "bubbles.and.sparkles.fill", "iphone", "wifi", "sofa.fill"
        ]),
        ("休闲娱乐", [
            "gamecontroller.fill", "ticket.fill", "tv.fill", "music.note", "paintpalette.fill",
            "film", "figure.run", "airplane", "camera.fill"
        ]),
        ("医疗健康", [
            "cross.case.fill", "pills.fill", "stethoscope", "syringe.fill", "bandage.fill",
            "heart.fill", "leaf.fill"
        ]),
        ("母婴宠物", [
            "figure.and.child.holdinghands", "teddybear.fill", "pawprint.fill", "cat.fill",
            "dog.fill", "bone.fill"
        ]),
        ("财务金融", [
            "banknote.fill", "creditcard.fill", "chart.line.uptrend.xyaxis", "yensign.circle.fill",
            "diamond.fill", "shield.fill", "trophy.fill", "building.columns.fill"
        ]),
        ("学习办公", [
            "book.fill", "graduationcap.fill", "laptopcomputer", "pencil", "doc.text.fill",
            "folder.fill", "pianokeys"
        ])
    ]
}

// MARK: - Canvas sticker glyphs (approximate gold home-feed stickers; not cropped assets)

private struct MimiStickerGlyphView: View {
    let kind: MimiStickerIconView.GlyphKind
    let systemName: String
    let size: CGFloat

    var body: some View {
        if kind == .system, !systemName.isEmpty {
            ZStack {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.92, weight: .bold))
                    .foregroundStyle(Color(hex: 0x5C4A3A).opacity(0.18))
                    .offset(y: size * 0.04)
                Image(systemName: systemName)
                    .font(.system(size: size * 0.88, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x5C4A3A))
                    .symbolRenderingMode(.monochrome)
            }
            .frame(width: size, height: size)
        } else {
            Canvas { context, canvasSize in
                drawGlyph(kind, in: &context, size: canvasSize)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}

private func drawGlyph(
    _ kind: MimiStickerIconView.GlyphKind,
    in context: inout GraphicsContext,
    size: CGSize
) {
    let w = size.width
    let h = size.height
    let s = min(w, h)
    let ink = Color(hex: 0x3A2A22)
    let blue = Color(hex: 0x4A90D9)
    let deepBlue = Color(hex: 0x2F6FAE)
    let orange = Color(hex: 0xF0A04B)
    let warm = Color(hex: 0xE8873A)
    let cream = Color(hex: 0xFFF6E8)
    let yellow = Color(hex: 0xF6D35A)
    let pink = Color(hex: 0xE8A0B8)
    let teal = Color(hex: 0x5BB8B0)
    let white = Color.white
    let lw = max(1.1, s * 0.055)

    func r(_ x: CGFloat, _ y: CGFloat, _ ew: CGFloat, _ eh: CGFloat) -> CGRect {
        CGRect(x: x * w, y: y * h, width: ew * w, height: eh * h)
    }
    func oval(_ x: CGFloat, _ y: CGFloat, _ ew: CGFloat, _ eh: CGFloat) -> Path {
        Path(ellipseIn: r(x, y, ew, eh))
    }
    func roundRect(_ x: CGFloat, _ y: CGFloat, _ ew: CGFloat, _ eh: CGFloat, _ radius: CGFloat) -> Path {
        Path(roundedRect: r(x, y, ew, eh), cornerRadius: radius * s)
    }
    func stroke(_ path: Path, _ color: Color = ink, width: CGFloat? = nil) {
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width ?? lw, lineCap: .round, lineJoin: .round))
    }
    func fill(_ path: Path, _ color: Color) {
        context.fill(path, with: .color(color))
    }

    switch kind {
    case .noodles:
        // Gold: blue bowl + orange noodles + chopsticks
        fill(oval(0.14, 0.42, 0.72, 0.42), blue)
        stroke(oval(0.14, 0.42, 0.72, 0.42))
        fill(oval(0.22, 0.38, 0.56, 0.22), cream)
        stroke(oval(0.22, 0.38, 0.56, 0.22))
        var noodle = Path()
        noodle.move(to: CGPoint(x: 0.30 * w, y: 0.48 * h))
        noodle.addQuadCurve(to: CGPoint(x: 0.70 * w, y: 0.50 * h), control: CGPoint(x: 0.50 * w, y: 0.38 * h))
        noodle.move(to: CGPoint(x: 0.32 * w, y: 0.56 * h))
        noodle.addQuadCurve(to: CGPoint(x: 0.68 * w, y: 0.58 * h), control: CGPoint(x: 0.50 * w, y: 0.48 * h))
        stroke(noodle, orange, width: lw * 1.15)
        fill(oval(0.46, 0.44, 0.12, 0.10), warm)
        var sticks = Path()
        sticks.move(to: CGPoint(x: 0.58 * w, y: 0.12 * h))
        sticks.addLine(to: CGPoint(x: 0.72 * w, y: 0.40 * h))
        sticks.move(to: CGPoint(x: 0.66 * w, y: 0.10 * h))
        sticks.addLine(to: CGPoint(x: 0.78 * w, y: 0.38 * h))
        stroke(sticks, ink, width: lw * 0.95)

    case .fuel:
        // Gold: blue pump body + white face + yellow nozzle
        fill(roundRect(0.28, 0.18, 0.36, 0.62, 0.08), blue)
        stroke(roundRect(0.28, 0.18, 0.36, 0.62, 0.08))
        fill(roundRect(0.34, 0.26, 0.24, 0.22, 0.05), white)
        stroke(roundRect(0.34, 0.26, 0.24, 0.22, 0.05))
        fill(roundRect(0.38, 0.54, 0.16, 0.10, 0.04), deepBlue)
        fill(roundRect(0.30, 0.78, 0.32, 0.08, 0.03), deepBlue)
        stroke(roundRect(0.30, 0.78, 0.32, 0.08, 0.03))
        var hose = Path()
        hose.move(to: CGPoint(x: 0.64 * w, y: 0.30 * h))
        hose.addQuadCurve(to: CGPoint(x: 0.82 * w, y: 0.58 * h), control: CGPoint(x: 0.86 * w, y: 0.34 * h))
        stroke(hose, ink, width: lw * 1.2)
        fill(roundRect(0.74, 0.54, 0.14, 0.16, 0.04), yellow)
        stroke(roundRect(0.74, 0.54, 0.14, 0.16, 0.04))

    case .bulb:
        fill(oval(0.26, 0.12, 0.48, 0.52), yellow)
        stroke(oval(0.26, 0.12, 0.48, 0.52))
        fill(roundRect(0.38, 0.58, 0.24, 0.16, 0.04), Color(hex: 0xD9C4A0))
        stroke(roundRect(0.38, 0.58, 0.24, 0.16, 0.04))
        var base = Path()
        base.move(to: CGPoint(x: 0.40 * w, y: 0.74 * h))
        base.addLine(to: CGPoint(x: 0.60 * w, y: 0.74 * h))
        base.move(to: CGPoint(x: 0.42 * w, y: 0.80 * h))
        base.addLine(to: CGPoint(x: 0.58 * w, y: 0.80 * h))
        stroke(base)
        var filament = Path()
        filament.move(to: CGPoint(x: 0.42 * w, y: 0.42 * h))
        filament.addQuadCurve(to: CGPoint(x: 0.58 * w, y: 0.42 * h), control: CGPoint(x: 0.50 * w, y: 0.28 * h))
        stroke(filament, warm, width: lw * 0.9)

    case .chart:
        fill(oval(0.12, 0.12, 0.76, 0.76), cream)
        stroke(oval(0.12, 0.12, 0.76, 0.76), orange, width: lw * 1.1)
        var axis = Path()
        axis.move(to: CGPoint(x: 0.28 * w, y: 0.70 * h))
        axis.addLine(to: CGPoint(x: 0.28 * w, y: 0.30 * h))
        axis.move(to: CGPoint(x: 0.28 * w, y: 0.70 * h))
        axis.addLine(to: CGPoint(x: 0.72 * w, y: 0.70 * h))
        stroke(axis, ink.opacity(0.55), width: lw * 0.75)
        var line = Path()
        line.move(to: CGPoint(x: 0.32 * w, y: 0.62 * h))
        line.addLine(to: CGPoint(x: 0.46 * w, y: 0.48 * h))
        line.addLine(to: CGPoint(x: 0.58 * w, y: 0.54 * h))
        line.addLine(to: CGPoint(x: 0.72 * w, y: 0.30 * h))
        stroke(line, orange, width: lw * 1.25)
        fill(oval(0.68, 0.24, 0.10, 0.10), warm)

    case .ticket:
        fill(roundRect(0.18, 0.28, 0.64, 0.44, 0.08), orange)
        stroke(roundRect(0.18, 0.28, 0.64, 0.44, 0.08))
        fill(oval(0.14, 0.42, 0.12, 0.16), Color(hex: 0xFFE3C2))
        fill(oval(0.74, 0.42, 0.12, 0.16), Color(hex: 0xFFE3C2))
        var dash = Path()
        dash.move(to: CGPoint(x: 0.50 * w, y: 0.34 * h))
        dash.addLine(to: CGPoint(x: 0.50 * w, y: 0.66 * h))
        context.stroke(dash, with: .color(white.opacity(0.85)), style: StrokeStyle(lineWidth: lw * 0.8, dash: [s * 0.06, s * 0.05]))
        fill(roundRect(0.26, 0.40, 0.16, 0.08, 0.03), cream)

    case .person:
        fill(oval(0.30, 0.18, 0.40, 0.40), orange)
        stroke(oval(0.30, 0.18, 0.40, 0.40))
        fill(roundRect(0.26, 0.16, 0.48, 0.14, 0.06), warm)
        stroke(roundRect(0.26, 0.16, 0.48, 0.14, 0.06))
        fill(oval(0.40, 0.32, 0.07, 0.08), ink)
        fill(oval(0.54, 0.32, 0.07, 0.08), ink)
        var smile = Path()
        smile.move(to: CGPoint(x: 0.42 * w, y: 0.46 * h))
        smile.addQuadCurve(to: CGPoint(x: 0.58 * w, y: 0.46 * h), control: CGPoint(x: 0.50 * w, y: 0.54 * h))
        stroke(smile, ink, width: lw * 0.85)
        fill(oval(0.22, 0.58, 0.56, 0.30), Color(hex: 0xF6C28A))
        stroke(oval(0.22, 0.58, 0.56, 0.30))

    case .leaf:
        var leaf = Path()
        leaf.move(to: CGPoint(x: 0.50 * w, y: 0.12 * h))
        leaf.addQuadCurve(to: CGPoint(x: 0.22 * w, y: 0.62 * h), control: CGPoint(x: 0.10 * w, y: 0.28 * h))
        leaf.addQuadCurve(to: CGPoint(x: 0.50 * w, y: 0.86 * h), control: CGPoint(x: 0.28 * w, y: 0.86 * h))
        leaf.addQuadCurve(to: CGPoint(x: 0.78 * w, y: 0.62 * h), control: CGPoint(x: 0.72 * w, y: 0.86 * h))
        leaf.addQuadCurve(to: CGPoint(x: 0.50 * w, y: 0.12 * h), control: CGPoint(x: 0.90 * w, y: 0.28 * h))
        fill(leaf, Color(hex: 0x7BC47F))
        stroke(leaf)
        var vein = Path()
        vein.move(to: CGPoint(x: 0.50 * w, y: 0.22 * h))
        vein.addLine(to: CGPoint(x: 0.50 * w, y: 0.78 * h))
        stroke(vein, Color(hex: 0x3E6B45), width: lw * 0.8)

    case .coffee:
        fill(roundRect(0.28, 0.28, 0.40, 0.46, 0.08), Color(hex: 0x8D6E63))
        stroke(roundRect(0.28, 0.28, 0.40, 0.46, 0.08))
        fill(oval(0.30, 0.24, 0.36, 0.14), Color(hex: 0x6D4C41))
        var handle = Path()
        handle.addArc(center: CGPoint(x: 0.72 * w, y: 0.48 * h), radius: 0.12 * s, startAngle: .degrees(-70), endAngle: .degrees(70), clockwise: false)
        stroke(handle, ink, width: lw * 1.1)
        fill(roundRect(0.30, 0.74, 0.36, 0.08, 0.03), Color(hex: 0xD7CCC8))

    case .drink:
        fill(roundRect(0.32, 0.22, 0.36, 0.56, 0.10), pink.opacity(0.85))
        stroke(roundRect(0.32, 0.22, 0.36, 0.56, 0.10))
        fill(oval(0.34, 0.18, 0.32, 0.14), cream)
        stroke(oval(0.34, 0.18, 0.32, 0.14))
        var straw = Path()
        straw.move(to: CGPoint(x: 0.58 * w, y: 0.08 * h))
        straw.addLine(to: CGPoint(x: 0.52 * w, y: 0.28 * h))
        stroke(straw, orange, width: lw * 1.1)
        fill(oval(0.42, 0.40, 0.08, 0.08), white.opacity(0.7))
        fill(oval(0.52, 0.52, 0.07, 0.07), white.opacity(0.7))

    case .takeout:
        fill(roundRect(0.22, 0.34, 0.56, 0.42, 0.08), orange)
        stroke(roundRect(0.22, 0.34, 0.56, 0.42, 0.08))
        fill(roundRect(0.30, 0.22, 0.40, 0.16, 0.06), cream)
        stroke(roundRect(0.30, 0.22, 0.40, 0.16, 0.06))
        var lid = Path()
        lid.move(to: CGPoint(x: 0.28 * w, y: 0.34 * h))
        lid.addLine(to: CGPoint(x: 0.72 * w, y: 0.34 * h))
        stroke(lid, warm)

    case .snack:
        fill(oval(0.22, 0.40, 0.56, 0.36), Color(hex: 0xF3D19A))
        stroke(oval(0.22, 0.40, 0.56, 0.36))
        fill(oval(0.34, 0.28, 0.32, 0.22), Color(hex: 0xE8B86D))
        stroke(oval(0.34, 0.28, 0.32, 0.22))
        fill(oval(0.44, 0.18, 0.12, 0.12), pink)

    case .wine:
        var glass = Path()
        glass.move(to: CGPoint(x: 0.34 * w, y: 0.18 * h))
        glass.addLine(to: CGPoint(x: 0.66 * w, y: 0.18 * h))
        glass.addQuadCurve(to: CGPoint(x: 0.50 * w, y: 0.58 * h), control: CGPoint(x: 0.72 * w, y: 0.42 * h))
        glass.addQuadCurve(to: CGPoint(x: 0.34 * w, y: 0.18 * h), control: CGPoint(x: 0.28 * w, y: 0.42 * h))
        fill(glass, Color(hex: 0xC96B8A))
        stroke(glass)
        var stem = Path()
        stem.move(to: CGPoint(x: 0.50 * w, y: 0.58 * h))
        stem.addLine(to: CGPoint(x: 0.50 * w, y: 0.78 * h))
        stem.move(to: CGPoint(x: 0.36 * w, y: 0.80 * h))
        stem.addLine(to: CGPoint(x: 0.64 * w, y: 0.80 * h))
        stroke(stem)

    case .bag:
        fill(roundRect(0.24, 0.34, 0.52, 0.46, 0.10), blue)
        stroke(roundRect(0.24, 0.34, 0.52, 0.46, 0.10))
        var handles = Path()
        handles.addArc(center: CGPoint(x: 0.38 * w, y: 0.34 * h), radius: 0.12 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        handles.addArc(center: CGPoint(x: 0.62 * w, y: 0.34 * h), radius: 0.12 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        stroke(handles)
        fill(oval(0.44, 0.50, 0.12, 0.12), cream)

    case .clothes:
        fill(roundRect(0.26, 0.30, 0.48, 0.48, 0.08), pink)
        stroke(roundRect(0.26, 0.30, 0.48, 0.48, 0.08))
        var neck = Path()
        neck.addArc(center: CGPoint(x: 0.50 * w, y: 0.30 * h), radius: 0.12 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        fill(neck, cream)
        stroke(neck)
        fill(oval(0.14, 0.32, 0.16, 0.18), pink)
        fill(oval(0.70, 0.32, 0.16, 0.18), pink)
        stroke(oval(0.14, 0.32, 0.16, 0.18))
        stroke(oval(0.70, 0.32, 0.16, 0.18))

    case .beauty:
        fill(roundRect(0.42, 0.18, 0.16, 0.46, 0.06), pink)
        stroke(roundRect(0.42, 0.18, 0.16, 0.46, 0.06))
        fill(oval(0.38, 0.58, 0.24, 0.24), Color(hex: 0xD46A8E))
        stroke(oval(0.38, 0.58, 0.24, 0.24))
        fill(oval(0.22, 0.22, 0.10, 0.10), yellow)
        fill(oval(0.68, 0.28, 0.08, 0.08), cream)

    case .headphones:
        var band = Path()
        band.addArc(center: CGPoint(x: 0.50 * w, y: 0.42 * h), radius: 0.28 * s, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        stroke(band, deepBlue, width: lw * 1.35)
        fill(oval(0.18, 0.42, 0.18, 0.28), blue)
        fill(oval(0.64, 0.42, 0.18, 0.28), blue)
        stroke(oval(0.18, 0.42, 0.18, 0.28))
        stroke(oval(0.64, 0.42, 0.18, 0.28))

    case .scissors:
        fill(oval(0.22, 0.22, 0.22, 0.22), pink)
        fill(oval(0.22, 0.56, 0.22, 0.22), blue)
        stroke(oval(0.22, 0.22, 0.22, 0.22))
        stroke(oval(0.22, 0.56, 0.22, 0.22))
        var blades = Path()
        blades.move(to: CGPoint(x: 0.40 * w, y: 0.34 * h))
        blades.addLine(to: CGPoint(x: 0.80 * w, y: 0.66 * h))
        blades.move(to: CGPoint(x: 0.40 * w, y: 0.66 * h))
        blades.addLine(to: CGPoint(x: 0.80 * w, y: 0.34 * h))
        stroke(blades, ink, width: lw * 1.15)
        fill(oval(0.44, 0.44, 0.12, 0.12), cream)
        stroke(oval(0.44, 0.44, 0.12, 0.12))

    case .box:
        fill(roundRect(0.20, 0.36, 0.60, 0.42, 0.06), orange)
        stroke(roundRect(0.20, 0.36, 0.60, 0.42, 0.06))
        var flap = Path()
        flap.move(to: CGPoint(x: 0.20 * w, y: 0.36 * h))
        flap.addLine(to: CGPoint(x: 0.50 * w, y: 0.22 * h))
        flap.addLine(to: CGPoint(x: 0.80 * w, y: 0.36 * h))
        fill(flap, warm)
        stroke(flap)
        var tape = Path()
        tape.move(to: CGPoint(x: 0.50 * w, y: 0.22 * h))
        tape.addLine(to: CGPoint(x: 0.50 * w, y: 0.78 * h))
        stroke(tape, cream, width: lw * 1.2)

    case .tag:
        var tag = Path()
        tag.move(to: CGPoint(x: 0.22 * w, y: 0.30 * h))
        tag.addLine(to: CGPoint(x: 0.62 * w, y: 0.18 * h))
        tag.addLine(to: CGPoint(x: 0.78 * w, y: 0.50 * h))
        tag.addLine(to: CGPoint(x: 0.38 * w, y: 0.78 * h))
        tag.closeSubpath()
        fill(tag, teal)
        stroke(tag)
        fill(oval(0.30, 0.34, 0.12, 0.12), cream)
        stroke(oval(0.30, 0.34, 0.12, 0.12))

    case .gift:
        fill(roundRect(0.22, 0.40, 0.56, 0.40, 0.08), Color(hex: 0xE57373))
        stroke(roundRect(0.22, 0.40, 0.56, 0.40, 0.08))
        fill(roundRect(0.22, 0.30, 0.56, 0.14, 0.05), Color(hex: 0xEF9A9A))
        stroke(roundRect(0.22, 0.30, 0.56, 0.14, 0.05))
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: 0.50 * w, y: 0.30 * h))
        ribbon.addLine(to: CGPoint(x: 0.50 * w, y: 0.80 * h))
        ribbon.move(to: CGPoint(x: 0.22 * w, y: 0.48 * h))
        ribbon.addLine(to: CGPoint(x: 0.78 * w, y: 0.48 * h))
        stroke(ribbon, yellow, width: lw * 1.15)
        fill(oval(0.36, 0.16, 0.14, 0.14), yellow)
        fill(oval(0.50, 0.16, 0.14, 0.14), yellow)

    case .bus:
        fill(roundRect(0.16, 0.28, 0.68, 0.42, 0.10), blue)
        stroke(roundRect(0.16, 0.28, 0.68, 0.42, 0.10))
        fill(roundRect(0.22, 0.34, 0.46, 0.16, 0.04), cream)
        stroke(roundRect(0.22, 0.34, 0.46, 0.16, 0.04))
        fill(oval(0.28, 0.66, 0.16, 0.16), ink)
        fill(oval(0.56, 0.66, 0.16, 0.16), ink)
        fill(oval(0.31, 0.69, 0.10, 0.10), white)
        fill(oval(0.59, 0.69, 0.10, 0.10), white)

    case .car, .taxi:
        let body = kind == .taxi ? yellow : blue
        fill(roundRect(0.14, 0.42, 0.72, 0.26, 0.10), body)
        stroke(roundRect(0.14, 0.42, 0.72, 0.26, 0.10))
        fill(roundRect(0.28, 0.28, 0.40, 0.18, 0.08), cream)
        stroke(roundRect(0.28, 0.28, 0.40, 0.18, 0.08))
        fill(oval(0.24, 0.62, 0.18, 0.18), ink)
        fill(oval(0.58, 0.62, 0.18, 0.18), ink)
        fill(oval(0.28, 0.66, 0.10, 0.10), white)
        fill(oval(0.62, 0.66, 0.10, 0.10), white)
        if kind == .taxi {
            fill(roundRect(0.42, 0.18, 0.16, 0.10, 0.03), orange)
        }

    case .train:
        fill(roundRect(0.26, 0.16, 0.48, 0.62, 0.12), deepBlue)
        stroke(roundRect(0.26, 0.16, 0.48, 0.62, 0.12))
        fill(roundRect(0.34, 0.26, 0.32, 0.18, 0.05), cream)
        stroke(roundRect(0.34, 0.26, 0.32, 0.18, 0.05))
        fill(oval(0.34, 0.70, 0.12, 0.12), ink)
        fill(oval(0.54, 0.70, 0.12, 0.12), ink)
        var rail = Path()
        rail.move(to: CGPoint(x: 0.20 * w, y: 0.88 * h))
        rail.addLine(to: CGPoint(x: 0.80 * w, y: 0.88 * h))
        stroke(rail, ink.opacity(0.5), width: lw * 0.8)

    case .parking:
        fill(oval(0.16, 0.16, 0.68, 0.68), blue)
        stroke(oval(0.16, 0.16, 0.68, 0.68))
        var p = Path()
        p.move(to: CGPoint(x: 0.40 * w, y: 0.70 * h))
        p.addLine(to: CGPoint(x: 0.40 * w, y: 0.30 * h))
        p.addLine(to: CGPoint(x: 0.56 * w, y: 0.30 * h))
        p.addQuadCurve(to: CGPoint(x: 0.56 * w, y: 0.52 * h), control: CGPoint(x: 0.70 * w, y: 0.40 * h))
        p.addLine(to: CGPoint(x: 0.40 * w, y: 0.52 * h))
        stroke(p, white, width: lw * 1.4)

    case .house:
        var roof = Path()
        roof.move(to: CGPoint(x: 0.50 * w, y: 0.16 * h))
        roof.addLine(to: CGPoint(x: 0.14 * w, y: 0.46 * h))
        roof.addLine(to: CGPoint(x: 0.86 * w, y: 0.46 * h))
        roof.closeSubpath()
        fill(roof, orange)
        stroke(roof)
        fill(roundRect(0.28, 0.46, 0.44, 0.36, 0.04), cream)
        stroke(roundRect(0.28, 0.46, 0.44, 0.36, 0.04))
        fill(roundRect(0.44, 0.58, 0.14, 0.24, 0.03), warm)
        stroke(roundRect(0.44, 0.58, 0.14, 0.24, 0.03))

    case .phone:
        fill(roundRect(0.34, 0.14, 0.32, 0.72, 0.10), blue)
        stroke(roundRect(0.34, 0.14, 0.32, 0.72, 0.10))
        fill(roundRect(0.38, 0.24, 0.24, 0.42, 0.04), cream)
        fill(oval(0.46, 0.72, 0.08, 0.08), white)

    case .key:
        fill(oval(0.22, 0.28, 0.32, 0.32), yellow)
        stroke(oval(0.22, 0.28, 0.32, 0.32))
        fill(oval(0.30, 0.36, 0.16, 0.16), cream)
        var shaft = Path()
        shaft.move(to: CGPoint(x: 0.50 * w, y: 0.44 * h))
        shaft.addLine(to: CGPoint(x: 0.82 * w, y: 0.44 * h))
        shaft.move(to: CGPoint(x: 0.74 * w, y: 0.44 * h))
        shaft.addLine(to: CGPoint(x: 0.74 * w, y: 0.56 * h))
        shaft.move(to: CGPoint(x: 0.82 * w, y: 0.44 * h))
        shaft.addLine(to: CGPoint(x: 0.82 * w, y: 0.52 * h))
        stroke(shaft, ink, width: lw * 1.15)

    case .wrench:
        fill(roundRect(0.42, 0.18, 0.16, 0.64, 0.06), Color(hex: 0x90A4AE))
        stroke(roundRect(0.42, 0.18, 0.16, 0.64, 0.06))
        fill(oval(0.30, 0.14, 0.40, 0.24), Color(hex: 0x78909C))
        stroke(oval(0.30, 0.14, 0.40, 0.24))
        fill(oval(0.36, 0.68, 0.28, 0.20), Color(hex: 0x78909C))
        stroke(oval(0.36, 0.68, 0.28, 0.20))

    case .broom:
        fill(roundRect(0.46, 0.12, 0.10, 0.46, 0.04), Color(hex: 0xA1887F))
        stroke(roundRect(0.46, 0.12, 0.10, 0.46, 0.04))
        var bristles = Path()
        bristles.move(to: CGPoint(x: 0.28 * w, y: 0.78 * h))
        bristles.addLine(to: CGPoint(x: 0.50 * w, y: 0.52 * h))
        bristles.addLine(to: CGPoint(x: 0.72 * w, y: 0.78 * h))
        bristles.closeSubpath()
        fill(bristles, Color(hex: 0x81C784))
        stroke(bristles)

    case .drop:
        var drop = Path()
        drop.move(to: CGPoint(x: 0.50 * w, y: 0.14 * h))
        drop.addQuadCurve(to: CGPoint(x: 0.22 * w, y: 0.56 * h), control: CGPoint(x: 0.20 * w, y: 0.30 * h))
        drop.addQuadCurve(to: CGPoint(x: 0.78 * w, y: 0.56 * h), control: CGPoint(x: 0.50 * w, y: 0.90 * h))
        drop.addQuadCurve(to: CGPoint(x: 0.50 * w, y: 0.14 * h), control: CGPoint(x: 0.80 * w, y: 0.30 * h))
        fill(drop, blue)
        stroke(drop)
        fill(oval(0.40, 0.40, 0.12, 0.16), white.opacity(0.55))

    case .ferris:
        stroke(oval(0.18, 0.18, 0.64, 0.64), pink, width: lw * 1.2)
        stroke(oval(0.34, 0.34, 0.32, 0.32), orange, width: lw * 0.9)
        for i in 0..<6 {
            let ang = CGFloat(i) * (.pi / 3)
            let cx = 0.50 + 0.30 * cos(ang)
            let cy = 0.50 + 0.30 * sin(ang)
            var spoke = Path()
            spoke.move(to: CGPoint(x: 0.50 * w, y: 0.50 * h))
            spoke.addLine(to: CGPoint(x: cx * w, y: cy * h))
            stroke(spoke, ink.opacity(0.55), width: lw * 0.7)
            fill(oval(cx - 0.06, cy - 0.06, 0.12, 0.12), yellow)
        }

    case .sports:
        fill(oval(0.18, 0.18, 0.64, 0.64), Color(hex: 0xFFCC80))
        stroke(oval(0.18, 0.18, 0.64, 0.64))
        var seam = Path()
        seam.addArc(center: CGPoint(x: 0.50 * w, y: 0.50 * h), radius: 0.22 * s, startAngle: .degrees(-60), endAngle: .degrees(60), clockwise: false)
        seam.addArc(center: CGPoint(x: 0.50 * w, y: 0.50 * h), radius: 0.22 * s, startAngle: .degrees(120), endAngle: .degrees(240), clockwise: false)
        stroke(seam, ink.opacity(0.65), width: lw * 0.8)

    case .game:
        fill(roundRect(0.16, 0.34, 0.68, 0.36, 0.16), deepBlue)
        stroke(roundRect(0.16, 0.34, 0.68, 0.36, 0.16))
        fill(oval(0.28, 0.44, 0.14, 0.14), cream)
        fill(roundRect(0.56, 0.42, 0.08, 0.18, 0.03), pink)
        fill(roundRect(0.52, 0.46, 0.16, 0.08, 0.03), pink)

    case .plane:
        var plane = Path()
        plane.move(to: CGPoint(x: 0.18 * w, y: 0.58 * h))
        plane.addLine(to: CGPoint(x: 0.55 * w, y: 0.42 * h))
        plane.addLine(to: CGPoint(x: 0.82 * w, y: 0.28 * h))
        plane.addLine(to: CGPoint(x: 0.70 * w, y: 0.48 * h))
        plane.addLine(to: CGPoint(x: 0.78 * w, y: 0.70 * h))
        plane.addLine(to: CGPoint(x: 0.60 * w, y: 0.56 * h))
        plane.addLine(to: CGPoint(x: 0.34 * w, y: 0.72 * h))
        plane.closeSubpath()
        fill(plane, blue)
        stroke(plane)

    case .palette:
        fill(oval(0.16, 0.20, 0.68, 0.62), Color(hex: 0xFFE0B2))
        stroke(oval(0.16, 0.20, 0.68, 0.62))
        fill(oval(0.28, 0.34, 0.14, 0.14), Color(hex: 0xEF5350))
        fill(oval(0.48, 0.28, 0.14, 0.14), blue)
        fill(oval(0.58, 0.48, 0.14, 0.14), Color(hex: 0x66BB6A))
        fill(oval(0.36, 0.54, 0.14, 0.14), yellow)
        fill(oval(0.62, 0.34, 0.12, 0.16), cream)

    case .tv:
        fill(roundRect(0.16, 0.24, 0.68, 0.48, 0.08), Color(hex: 0x5C6BC0))
        stroke(roundRect(0.16, 0.24, 0.68, 0.48, 0.08))
        fill(roundRect(0.24, 0.32, 0.52, 0.30, 0.04), cream)
        var stand = Path()
        stand.move(to: CGPoint(x: 0.38 * w, y: 0.72 * h))
        stand.addLine(to: CGPoint(x: 0.50 * w, y: 0.82 * h))
        stand.addLine(to: CGPoint(x: 0.62 * w, y: 0.72 * h))
        stroke(stand)

    case .meds:
        fill(roundRect(0.22, 0.38, 0.28, 0.28, 0.12), Color(hex: 0xEF9A9A))
        fill(roundRect(0.46, 0.38, 0.28, 0.28, 0.12), white)
        stroke(roundRect(0.22, 0.38, 0.56, 0.28, 0.12))
        var seam = Path()
        seam.move(to: CGPoint(x: 0.50 * w, y: 0.38 * h))
        seam.addLine(to: CGPoint(x: 0.50 * w, y: 0.66 * h))
        stroke(seam)
        fill(oval(0.62, 0.20, 0.16, 0.16), Color(hex: 0xE57373))
        stroke(oval(0.62, 0.20, 0.16, 0.16))

    case .tooth:
        var tooth = Path()
        tooth.move(to: CGPoint(x: 0.30 * w, y: 0.28 * h))
        tooth.addQuadCurve(to: CGPoint(x: 0.70 * w, y: 0.28 * h), control: CGPoint(x: 0.50 * w, y: 0.12 * h))
        tooth.addQuadCurve(to: CGPoint(x: 0.66 * w, y: 0.72 * h), control: CGPoint(x: 0.78 * w, y: 0.50 * h))
        tooth.addQuadCurve(to: CGPoint(x: 0.50 * w, y: 0.62 * h), control: CGPoint(x: 0.58 * w, y: 0.82 * h))
        tooth.addQuadCurve(to: CGPoint(x: 0.34 * w, y: 0.72 * h), control: CGPoint(x: 0.42 * w, y: 0.82 * h))
        tooth.addQuadCurve(to: CGPoint(x: 0.30 * w, y: 0.28 * h), control: CGPoint(x: 0.22 * w, y: 0.50 * h))
        fill(tooth, cream)
        stroke(tooth)

    case .tea:
        fill(roundRect(0.28, 0.34, 0.40, 0.38, 0.08), Color(hex: 0xA5D6A7))
        stroke(roundRect(0.28, 0.34, 0.40, 0.38, 0.08))
        fill(oval(0.30, 0.28, 0.36, 0.14), Color(hex: 0x81C784))
        var handle = Path()
        handle.addArc(center: CGPoint(x: 0.74 * w, y: 0.52 * h), radius: 0.11 * s, startAngle: .degrees(-60), endAngle: .degrees(60), clockwise: false)
        stroke(handle)
        var steam = Path()
        steam.move(to: CGPoint(x: 0.40 * w, y: 0.22 * h))
        steam.addQuadCurve(to: CGPoint(x: 0.40 * w, y: 0.10 * h), control: CGPoint(x: 0.34 * w, y: 0.16 * h))
        steam.move(to: CGPoint(x: 0.54 * w, y: 0.22 * h))
        steam.addQuadCurve(to: CGPoint(x: 0.54 * w, y: 0.08 * h), control: CGPoint(x: 0.60 * w, y: 0.15 * h))
        stroke(steam, ink.opacity(0.45), width: lw * 0.75)

    case .stethoscope:
        var tube = Path()
        tube.move(to: CGPoint(x: 0.28 * w, y: 0.20 * h))
        tube.addLine(to: CGPoint(x: 0.28 * w, y: 0.42 * h))
        tube.addQuadCurve(to: CGPoint(x: 0.72 * w, y: 0.42 * h), control: CGPoint(x: 0.50 * w, y: 0.70 * h))
        tube.addLine(to: CGPoint(x: 0.72 * w, y: 0.20 * h))
        stroke(tube, teal, width: lw * 1.2)
        fill(oval(0.20, 0.14, 0.16, 0.14), cream)
        fill(oval(0.64, 0.14, 0.16, 0.14), cream)
        stroke(oval(0.20, 0.14, 0.16, 0.14))
        stroke(oval(0.64, 0.14, 0.16, 0.14))
        fill(oval(0.40, 0.64, 0.20, 0.20), blue)
        stroke(oval(0.40, 0.64, 0.20, 0.20))

    case .bandage:
        fill(roundRect(0.18, 0.38, 0.64, 0.24, 0.08), Color(hex: 0xFFE082))
        stroke(roundRect(0.18, 0.38, 0.64, 0.24, 0.08))
        fill(roundRect(0.40, 0.40, 0.20, 0.20, 0.04), cream)
        stroke(roundRect(0.40, 0.40, 0.20, 0.20, 0.04))

    case .book:
        fill(roundRect(0.22, 0.20, 0.56, 0.62, 0.06), blue)
        stroke(roundRect(0.22, 0.20, 0.56, 0.62, 0.06))
        fill(roundRect(0.30, 0.20, 0.48, 0.62, 0.04), cream)
        stroke(roundRect(0.30, 0.20, 0.48, 0.62, 0.04))
        var lines = Path()
        lines.move(to: CGPoint(x: 0.38 * w, y: 0.38 * h))
        lines.addLine(to: CGPoint(x: 0.68 * w, y: 0.38 * h))
        lines.move(to: CGPoint(x: 0.38 * w, y: 0.50 * h))
        lines.addLine(to: CGPoint(x: 0.68 * w, y: 0.50 * h))
        lines.move(to: CGPoint(x: 0.38 * w, y: 0.62 * h))
        lines.addLine(to: CGPoint(x: 0.60 * w, y: 0.62 * h))
        stroke(lines, ink.opacity(0.45), width: lw * 0.7)

    case .graduation:
        var cap = Path()
        cap.move(to: CGPoint(x: 0.50 * w, y: 0.22 * h))
        cap.addLine(to: CGPoint(x: 0.16 * w, y: 0.40 * h))
        cap.addLine(to: CGPoint(x: 0.50 * w, y: 0.52 * h))
        cap.addLine(to: CGPoint(x: 0.84 * w, y: 0.40 * h))
        cap.closeSubpath()
        fill(cap, deepBlue)
        stroke(cap)
        fill(roundRect(0.34, 0.50, 0.32, 0.18, 0.04), Color(hex: 0x5C6BC0))
        stroke(roundRect(0.34, 0.50, 0.32, 0.18, 0.04))
        var tassel = Path()
        tassel.move(to: CGPoint(x: 0.72 * w, y: 0.36 * h))
        tassel.addLine(to: CGPoint(x: 0.80 * w, y: 0.66 * h))
        stroke(tassel, yellow, width: lw * 1.1)
        fill(oval(0.76, 0.64, 0.10, 0.10), yellow)

    case .laptop:
        fill(roundRect(0.22, 0.24, 0.56, 0.40, 0.06), Color(hex: 0x78909C))
        stroke(roundRect(0.22, 0.24, 0.56, 0.40, 0.06))
        fill(roundRect(0.28, 0.30, 0.44, 0.28, 0.03), cream)
        fill(roundRect(0.16, 0.64, 0.68, 0.12, 0.04), Color(hex: 0x90A4AE))
        stroke(roundRect(0.16, 0.64, 0.68, 0.12, 0.04))

    case .piano:
        fill(roundRect(0.16, 0.34, 0.68, 0.36, 0.06), ink)
        stroke(roundRect(0.16, 0.34, 0.68, 0.36, 0.06))
        for i in 0..<5 {
            let x = 0.22 + CGFloat(i) * 0.12
            fill(roundRect(x, 0.38, 0.08, 0.28, 0.02), cream)
        }

    case .pencil:
        var body = Path()
        body.move(to: CGPoint(x: 0.28 * w, y: 0.72 * h))
        body.addLine(to: CGPoint(x: 0.62 * w, y: 0.20 * h))
        body.addLine(to: CGPoint(x: 0.74 * w, y: 0.28 * h))
        body.addLine(to: CGPoint(x: 0.40 * w, y: 0.80 * h))
        body.closeSubpath()
        fill(body, yellow)
        stroke(body)
        var tip = Path()
        tip.move(to: CGPoint(x: 0.28 * w, y: 0.72 * h))
        tip.addLine(to: CGPoint(x: 0.20 * w, y: 0.86 * h))
        tip.addLine(to: CGPoint(x: 0.40 * w, y: 0.80 * h))
        tip.closeSubpath()
        fill(tip, Color(hex: 0xD7CCC8))
        stroke(tip)

    case .paw:
        fill(oval(0.34, 0.42, 0.32, 0.30), orange)
        stroke(oval(0.34, 0.42, 0.32, 0.30))
        fill(oval(0.22, 0.28, 0.16, 0.18), warm)
        fill(oval(0.40, 0.20, 0.16, 0.18), warm)
        fill(oval(0.58, 0.28, 0.16, 0.18), warm)
        stroke(oval(0.22, 0.28, 0.16, 0.18))
        stroke(oval(0.40, 0.20, 0.16, 0.18))
        stroke(oval(0.58, 0.28, 0.16, 0.18))

    case .bone:
        fill(oval(0.14, 0.34, 0.22, 0.22), cream)
        fill(oval(0.14, 0.48, 0.22, 0.22), cream)
        fill(oval(0.64, 0.34, 0.22, 0.22), cream)
        fill(oval(0.64, 0.48, 0.22, 0.22), cream)
        fill(roundRect(0.26, 0.42, 0.48, 0.18, 0.08), cream)
        stroke(oval(0.14, 0.34, 0.22, 0.22))
        stroke(oval(0.14, 0.48, 0.22, 0.22))
        stroke(oval(0.64, 0.34, 0.22, 0.22))
        stroke(oval(0.64, 0.48, 0.22, 0.22))
        stroke(roundRect(0.26, 0.42, 0.48, 0.18, 0.08))

    case .petMed:
        fill(oval(0.22, 0.28, 0.56, 0.48), Color(hex: 0xFFAB91))
        stroke(oval(0.22, 0.28, 0.56, 0.48))
        fill(oval(0.34, 0.42, 0.10, 0.12), ink)
        fill(oval(0.56, 0.42, 0.10, 0.12), ink)
        fill(roundRect(0.42, 0.18, 0.16, 0.14, 0.04), Color(hex: 0xEF5350))

    case .petBath:
        fill(oval(0.18, 0.40, 0.64, 0.36), blue.opacity(0.85))
        stroke(oval(0.18, 0.40, 0.64, 0.36))
        fill(oval(0.34, 0.28, 0.14, 0.14), cream)
        fill(oval(0.52, 0.24, 0.16, 0.16), cream)
        fill(oval(0.40, 0.18, 0.12, 0.12), white.opacity(0.8))

    case .baby:
        fill(oval(0.30, 0.18, 0.40, 0.40), Color(hex: 0xFFCCBC))
        stroke(oval(0.30, 0.18, 0.40, 0.40))
        fill(oval(0.40, 0.32, 0.07, 0.08), ink)
        fill(oval(0.54, 0.32, 0.07, 0.08), ink)
        fill(roundRect(0.42, 0.48, 0.08, 0.10, 0.03), Color(hex: 0xE57373))
        fill(oval(0.24, 0.58, 0.52, 0.28), Color(hex: 0xF8BBD0))
        stroke(oval(0.24, 0.58, 0.52, 0.28))

    case .teddy:
        fill(oval(0.18, 0.18, 0.22, 0.22), orange)
        fill(oval(0.60, 0.18, 0.22, 0.22), orange)
        fill(oval(0.26, 0.28, 0.48, 0.48), warm)
        stroke(oval(0.18, 0.18, 0.22, 0.22))
        stroke(oval(0.60, 0.18, 0.22, 0.22))
        stroke(oval(0.26, 0.28, 0.48, 0.48))
        fill(oval(0.38, 0.42, 0.08, 0.10), ink)
        fill(oval(0.54, 0.42, 0.08, 0.10), ink)
        fill(oval(0.44, 0.54, 0.12, 0.10), Color(hex: 0xC4654A))

    case .card:
        fill(roundRect(0.16, 0.30, 0.68, 0.42, 0.08), blue)
        stroke(roundRect(0.16, 0.30, 0.68, 0.42, 0.08))
        fill(roundRect(0.16, 0.42, 0.68, 0.10, 0.02), deepBlue)
        fill(roundRect(0.24, 0.58, 0.22, 0.08, 0.03), yellow)

    case .shield:
        var shield = Path()
        shield.move(to: CGPoint(x: 0.50 * w, y: 0.12 * h))
        shield.addLine(to: CGPoint(x: 0.78 * w, y: 0.28 * h))
        shield.addQuadCurve(to: CGPoint(x: 0.50 * w, y: 0.88 * h), control: CGPoint(x: 0.82 * w, y: 0.62 * h))
        shield.addQuadCurve(to: CGPoint(x: 0.22 * w, y: 0.28 * h), control: CGPoint(x: 0.18 * w, y: 0.62 * h))
        shield.closeSubpath()
        fill(shield, Color(hex: 0x81C784))
        stroke(shield)
        var check = Path()
        check.move(to: CGPoint(x: 0.36 * w, y: 0.48 * h))
        check.addLine(to: CGPoint(x: 0.46 * w, y: 0.60 * h))
        check.addLine(to: CGPoint(x: 0.66 * w, y: 0.36 * h))
        stroke(check, white, width: lw * 1.2)

    case .sparkle:
        func star(_ cx: CGFloat, _ cy: CGFloat, _ rad: CGFloat, _ color: Color) {
            var p = Path()
            for i in 0..<8 {
                let ang = CGFloat(i) * (.pi / 4) - .pi / 2
                let len: CGFloat = i % 2 == 0 ? rad : rad * 0.4
                let pt = CGPoint(x: (cx + len * cos(ang)) * w, y: (cy + len * sin(ang)) * h)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            fill(p, color)
            stroke(p)
        }
        star(0.50, 0.46, 0.28, yellow)
        star(0.74, 0.28, 0.12, pink)
        star(0.24, 0.30, 0.10, cream)

    case .money:
        fill(roundRect(0.16, 0.28, 0.68, 0.44, 0.08), Color(hex: 0x81C784))
        stroke(roundRect(0.16, 0.28, 0.68, 0.44, 0.08))
        fill(oval(0.38, 0.36, 0.24, 0.28), cream)
        stroke(oval(0.38, 0.36, 0.24, 0.28))
        var yen = Path()
        yen.move(to: CGPoint(x: 0.44 * w, y: 0.42 * h))
        yen.addLine(to: CGPoint(x: 0.50 * w, y: 0.52 * h))
        yen.addLine(to: CGPoint(x: 0.56 * w, y: 0.42 * h))
        yen.move(to: CGPoint(x: 0.50 * w, y: 0.52 * h))
        yen.addLine(to: CGPoint(x: 0.50 * w, y: 0.62 * h))
        yen.move(to: CGPoint(x: 0.44 * w, y: 0.56 * h))
        yen.addLine(to: CGPoint(x: 0.56 * w, y: 0.56 * h))
        stroke(yen, Color(hex: 0x3E6B45), width: lw * 0.9)

    case .trophy:
        fill(oval(0.28, 0.18, 0.44, 0.40), yellow)
        stroke(oval(0.28, 0.18, 0.44, 0.40))
        var handles = Path()
        handles.addArc(center: CGPoint(x: 0.28 * w, y: 0.36 * h), radius: 0.12 * s, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        handles.addArc(center: CGPoint(x: 0.72 * w, y: 0.36 * h), radius: 0.12 * s, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        stroke(handles, orange, width: lw * 1.1)
        fill(roundRect(0.42, 0.56, 0.16, 0.14, 0.03), Color(hex: 0xD7CCC8))
        fill(roundRect(0.34, 0.70, 0.32, 0.12, 0.04), warm)
        stroke(roundRect(0.34, 0.70, 0.32, 0.12, 0.04))

    case .diamond:
        var diamond = Path()
        diamond.move(to: CGPoint(x: 0.50 * w, y: 0.14 * h))
        diamond.addLine(to: CGPoint(x: 0.78 * w, y: 0.40 * h))
        diamond.addLine(to: CGPoint(x: 0.50 * w, y: 0.86 * h))
        diamond.addLine(to: CGPoint(x: 0.22 * w, y: 0.40 * h))
        diamond.closeSubpath()
        fill(diamond, Color(hex: 0x81D4FA))
        stroke(diamond)
        var facet = Path()
        facet.move(to: CGPoint(x: 0.22 * w, y: 0.40 * h))
        facet.addLine(to: CGPoint(x: 0.78 * w, y: 0.40 * h))
        facet.move(to: CGPoint(x: 0.50 * w, y: 0.14 * h))
        facet.addLine(to: CGPoint(x: 0.38 * w, y: 0.40 * h))
        facet.move(to: CGPoint(x: 0.50 * w, y: 0.14 * h))
        facet.addLine(to: CGPoint(x: 0.62 * w, y: 0.40 * h))
        stroke(facet, white.opacity(0.8), width: lw * 0.75)

    case .store:
        fill(roundRect(0.22, 0.40, 0.56, 0.42, 0.04), cream)
        stroke(roundRect(0.22, 0.40, 0.56, 0.42, 0.04))
        var awning = Path()
        awning.move(to: CGPoint(x: 0.16 * w, y: 0.42 * h))
        awning.addLine(to: CGPoint(x: 0.28 * w, y: 0.24 * h))
        awning.addLine(to: CGPoint(x: 0.72 * w, y: 0.24 * h))
        awning.addLine(to: CGPoint(x: 0.84 * w, y: 0.42 * h))
        awning.closeSubpath()
        fill(awning, orange)
        stroke(awning)
        fill(roundRect(0.40, 0.54, 0.20, 0.28, 0.03), warm)
        stroke(roundRect(0.40, 0.54, 0.20, 0.28, 0.03))

    case .rocket:
        var body = Path()
        body.move(to: CGPoint(x: 0.50 * w, y: 0.10 * h))
        body.addQuadCurve(to: CGPoint(x: 0.66 * w, y: 0.62 * h), control: CGPoint(x: 0.70 * w, y: 0.30 * h))
        body.addLine(to: CGPoint(x: 0.34 * w, y: 0.62 * h))
        body.addQuadCurve(to: CGPoint(x: 0.50 * w, y: 0.10 * h), control: CGPoint(x: 0.30 * w, y: 0.30 * h))
        fill(body, Color(hex: 0x90CAF9))
        stroke(body)
        fill(oval(0.44, 0.30, 0.12, 0.12), cream)
        stroke(oval(0.44, 0.30, 0.12, 0.12))
        var finL = Path()
        finL.move(to: CGPoint(x: 0.34 * w, y: 0.52 * h))
        finL.addLine(to: CGPoint(x: 0.18 * w, y: 0.70 * h))
        finL.addLine(to: CGPoint(x: 0.36 * w, y: 0.62 * h))
        fill(finL, pink)
        stroke(finL)
        var finR = Path()
        finR.move(to: CGPoint(x: 0.66 * w, y: 0.52 * h))
        finR.addLine(to: CGPoint(x: 0.82 * w, y: 0.70 * h))
        finR.addLine(to: CGPoint(x: 0.64 * w, y: 0.62 * h))
        fill(finR, pink)
        stroke(finR)
        fill(oval(0.42, 0.66, 0.08, 0.16), orange)
        fill(oval(0.50, 0.70, 0.08, 0.18), yellow)

    case .coin:
        fill(oval(0.18, 0.18, 0.64, 0.64), yellow)
        stroke(oval(0.18, 0.18, 0.64, 0.64))
        stroke(oval(0.28, 0.28, 0.44, 0.44), warm, width: lw * 0.9)
        var mark = Path()
        mark.move(to: CGPoint(x: 0.40 * w, y: 0.40 * h))
        mark.addLine(to: CGPoint(x: 0.50 * w, y: 0.50 * h))
        mark.addLine(to: CGPoint(x: 0.60 * w, y: 0.40 * h))
        mark.move(to: CGPoint(x: 0.50 * w, y: 0.50 * h))
        mark.addLine(to: CGPoint(x: 0.50 * w, y: 0.64 * h))
        mark.move(to: CGPoint(x: 0.40 * w, y: 0.56 * h))
        mark.addLine(to: CGPoint(x: 0.60 * w, y: 0.56 * h))
        stroke(mark, warm)

    case .umbrella:
        var canopy = Path()
        canopy.move(to: CGPoint(x: 0.16 * w, y: 0.48 * h))
        canopy.addQuadCurve(to: CGPoint(x: 0.84 * w, y: 0.48 * h), control: CGPoint(x: 0.50 * w, y: 0.08 * h))
        canopy.addLine(to: CGPoint(x: 0.16 * w, y: 0.48 * h))
        fill(canopy, Color(hex: 0x81C784))
        stroke(canopy)
        var pole = Path()
        pole.move(to: CGPoint(x: 0.50 * w, y: 0.48 * h))
        pole.addLine(to: CGPoint(x: 0.50 * w, y: 0.78 * h))
        pole.addQuadCurve(to: CGPoint(x: 0.60 * w, y: 0.86 * h), control: CGPoint(x: 0.50 * w, y: 0.88 * h))
        stroke(pole)

    case .transfer:
        fill(oval(0.16, 0.16, 0.68, 0.68), teal.opacity(0.85))
        stroke(oval(0.16, 0.16, 0.68, 0.68))
        var arrows = Path()
        arrows.move(to: CGPoint(x: 0.30 * w, y: 0.40 * h))
        arrows.addLine(to: CGPoint(x: 0.66 * w, y: 0.40 * h))
        arrows.addLine(to: CGPoint(x: 0.58 * w, y: 0.32 * h))
        arrows.move(to: CGPoint(x: 0.66 * w, y: 0.40 * h))
        arrows.addLine(to: CGPoint(x: 0.58 * w, y: 0.48 * h))
        arrows.move(to: CGPoint(x: 0.70 * w, y: 0.60 * h))
        arrows.addLine(to: CGPoint(x: 0.34 * w, y: 0.60 * h))
        arrows.addLine(to: CGPoint(x: 0.42 * w, y: 0.52 * h))
        arrows.move(to: CGPoint(x: 0.34 * w, y: 0.60 * h))
        arrows.addLine(to: CGPoint(x: 0.42 * w, y: 0.68 * h))
        stroke(arrows, white, width: lw * 1.15)

    case .briefcase:
        fill(roundRect(0.18, 0.36, 0.64, 0.42, 0.08), Color(hex: 0x8D6E63))
        stroke(roundRect(0.18, 0.36, 0.64, 0.42, 0.08))
        fill(roundRect(0.40, 0.24, 0.20, 0.16, 0.04), Color(hex: 0x6D4C41))
        stroke(roundRect(0.40, 0.24, 0.20, 0.16, 0.04))
        fill(roundRect(0.44, 0.50, 0.12, 0.10, 0.03), yellow)

    case .system:
        fill(oval(0.28, 0.28, 0.44, 0.44), orange.opacity(0.85))
        stroke(oval(0.28, 0.28, 0.44, 0.44))
    }
}

// MARK: - Ask-bar mascot (Canvas cat face for「任何事情都能问我」)

public struct MimiAskMascotView: View {
    public var size: CGFloat = 28

    public init(size: CGFloat = 28) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let fur = Color(hex: 0xE39A4B)
            let ear = Color(hex: 0xC4783A)
            let innerEar = Color(hex: 0xF0C08A)
            let muzzle = Color(hex: 0xF6D7B0)
            let ink = Color(hex: 0x3A2A22)
            let nose = Color(hex: 0xC4654A)

            func ellipse(_ x: CGFloat, _ y: CGFloat, _ ew: CGFloat, _ eh: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: x * w, y: y * h, width: ew * w, height: eh * h))
            }

            context.fill(ellipse(0.10, 0.00, 0.26, 0.30), with: .color(ear))
            context.fill(ellipse(0.64, 0.00, 0.26, 0.30), with: .color(ear))
            context.fill(ellipse(0.06, 0.14, 0.88, 0.82), with: .color(fur))
            context.fill(ellipse(0.16, 0.06, 0.14, 0.16), with: .color(innerEar))
            context.fill(ellipse(0.70, 0.06, 0.14, 0.16), with: .color(innerEar))
            context.fill(ellipse(0.24, 0.50, 0.52, 0.38), with: .color(muzzle))
            context.fill(ellipse(0.30, 0.38, 0.10, 0.12), with: .color(ink))
            context.fill(ellipse(0.60, 0.38, 0.10, 0.12), with: .color(ink))
            context.fill(ellipse(0.43, 0.55, 0.14, 0.10), with: .color(nose))

            var smile = Path()
            smile.move(to: CGPoint(x: 0.40 * w, y: 0.70 * h))
            smile.addQuadCurve(
                to: CGPoint(x: 0.60 * w, y: 0.70 * h),
                control: CGPoint(x: 0.50 * w, y: 0.78 * h)
            )
            context.stroke(smile, with: .color(nose), lineWidth: max(1, w * 0.04))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
