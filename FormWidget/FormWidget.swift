import WidgetKit
import SwiftUI

let APP_GROUP_ID = "group.com.macro.shared"

extension Color {
    static func fromHex(_ hex: String, fallback: Color) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return fallback }
        return Color(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
    
    // Проверяет, нужен ли черный текст поверх этого HEX-цвета
    static func contrastText(forHex hex: String) -> Color {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return .black }
        let r = Double((rgb & 0xFF0000) >> 16)
        let g = Double((rgb & 0x00FF00) >> 8)
        let b = Double(rgb & 0x0000FF)
        let yiq = (r * 299 + g * 587 + b * 114) / 1000
        return yiq >= 150 ? .black : .white
    }
}

struct MacroEntry: TimelineEntry {
    let date: Date
    let calHex: String; let pHex: String; let cHex: String; let fHex: String
    let cal: Int; let targetCal: Int
    let p: Int; let targetP: Int
    let f: Int; let targetF: Int
    let c: Int; let targetC: Int
    let splitTitle: String
    let isRestDay: Bool
    let setsDone: Int; let setsTarget: Int
    let weekBadges: [String]
    let currentWeight: String
    let stackDone: Int; let stackTotal: Int
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MacroEntry { loadFromSharedDefaults() }
    func getSnapshot(in context: Context, completion: @escaping (MacroEntry) -> Void) { completion(loadFromSharedDefaults()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MacroEntry>) -> Void) {
        let entry = loadFromSharedDefaults()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
    
    private func loadFromSharedDefaults() -> MacroEntry {
        let d = UserDefaults(suiteName: APP_GROUP_ID)
        let badgesRaw = d?.string(forKey: "weekBadges") ?? "Д1,Д2,ОТД,Д3,ОТД,Д4,ОТД"
        let badges = badgesRaw.split(separator: ",").map(String.init)
        
        return MacroEntry(
            date: Date(),
            calHex: d?.string(forKey: "calHex") ?? "#E6DFD3",
            pHex: d?.string(forKey: "pHex") ?? "#9CA3AF",
            cHex: d?.string(forKey: "cHex") ?? "#C2593F",
            fHex: d?.string(forKey: "fHex") ?? "#8C8275",
            cal: d?.integer(forKey: "cal") ?? 0,
            targetCal: max(500, d?.integer(forKey: "targetCal") ?? 2979),
            p: d?.integer(forKey: "p") ?? 0,
            targetP: max(10, d?.integer(forKey: "targetP") ?? 130),
            f: d?.integer(forKey: "f") ?? 0,
            targetF: max(10, d?.integer(forKey: "targetF") ?? 67),
            c: d?.integer(forKey: "c") ?? 0,
            targetC: max(10, d?.integer(forKey: "targetC") ?? 464),
            splitTitle: d?.string(forKey: "splitTitle") ?? "День 1 · Жим",
            isRestDay: d?.bool(forKey: "isRestDay") ?? false,
            setsDone: d?.integer(forKey: "setsDone") ?? 0,
            setsTarget: max(10, d?.integer(forKey: "setsTarget") ?? 52),
            weekBadges: badges.count == 7 ? badges : ["Д1","Д2","ОТД","Д3","ОТД","Д4","ОТД"],
            currentWeight: d?.string(forKey: "currentWeight") ?? "70",
            stackDone: d?.integer(forKey: "stackDone") ?? 0,
            stackTotal: max(1, d?.integer(forKey: "stackTotal") ?? 4)
        )
    }
}

// Компактное кольцо для умещения всего комбайна в Medium-виджет (на пол-экрана)
struct CompactMacroRing: View {
    let label: String
    let current: Int
    let target: Int
    let color: Color
    
    var progress: Double { target > 0 ? min(1.0, Double(current) / Double(target)) : 0 }
    
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.13), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: max(0.05, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
            
            VStack(alignment: .leading, spacing: 0.5) {
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                Text(verbatim: "\(current)/\(target)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }
}

struct MacroWidgetEntryView: View {
    var entry: Provider.Entry

    let dayLabels = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]
    var currentMondayIndex: Int {
        let w = Calendar.current.component(.weekday, from: entry.date)
        return w == 1 ? 6 : (w - 2)
    }

    var body: some View {
        let calColor = Color.fromHex(entry.calHex, fallback: Color(red: 0.84, green: 0.16, blue: 0.16))
        let pColor   = Color.fromHex(entry.pHex,   fallback: Color(red: 0.89, green: 0.89, blue: 0.91))
        let cColor   = Color.fromHex(entry.cHex,   fallback: Color(red: 0.78, green: 0.75, blue: 0.66))
        let fColor   = Color.fromHex(entry.fHex,   fallback: Color(red: 0.39, green: 0.45, blue: 0.55))

        VStack(alignment: .leading, spacing: 7) {
            // 1. Шапка: бренд + вес и стек
            HStack {
                Text("FORM // РАЦИОН И ТРЕНИ")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(verbatim: "\(entry.currentWeight)кг · Стек \(entry.stackDone)/\(entry.stackTotal)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(calColor)
            }

            // 2. Кольца КБЖУ в 2 компактных ряда
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    CompactMacroRing(label: "Калории", current: entry.cal, target: entry.targetCal, color: calColor)
                    CompactMacroRing(label: "Белки", current: entry.p, target: entry.targetP, color: pColor)
                }
                HStack(spacing: 8) {
                    CompactMacroRing(label: "Углеводы", current: entry.c, target: entry.targetC, color: cColor)
                    CompactMacroRing(label: "Жиры", current: entry.f, target: entry.targetF, color: fColor)
                }
            }

            // 3. Полоска расписания ПН - ВС
            HStack(spacing: 4) {
                ForEach(Array(0..<7), id: \.self) { (idx: Int) in
                    let badge = entry.weekBadges[idx].replacingOccurrences(of: "День ", with: "Д")
                    let isRest = badge == "ОТД"
                    let isToday = idx == currentMondayIndex
                    
                    let todayText = Color.contrastText(forHex: entry.calHex)
                    let badgeColor: Color = isToday ? todayText : (isRest ? Color.white.opacity(0.35) : Color.white.opacity(0.9))
                    let badgeBg: Color = isToday ? calColor : (isRest ? Color.white.opacity(0.03) : Color.white.opacity(0.08))
                    let strokeColor: Color = isToday ? calColor.opacity(0.8) : Color.white.opacity(0.06)

                    VStack(spacing: 1.5) {
                        Text(dayLabels[idx])
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(isToday ? Color.white : Color.white.opacity(0.45))
                        Text(badge)
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundColor(badgeColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(badgeBg)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(strokeColor, lineWidth: 1)
                    )
                }
            }

            // 4. Нижняя строка: текущая тренировка / отдых + подходы за неделю
            HStack {
                Text(entry.isRestDay ? "СЕГОДНЯ: ДЕНЬ ОТДЫХА" : entry.splitTitle.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                Text(verbatim: "\(entry.setsDone)/\(entry.setsTarget) подх. за нед.")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(calColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        }
        .padding(.horizontal, 2)
        .containerBackground(.ultraThinMaterial, for: .widget)
        .environment(\.colorScheme, .dark)
    }
}

@main
struct MacroWidget: Widget {
    let kind: String = "MacroWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MacroWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("form // Комбайн (Пол-экрана)")
        .description("КБЖУ, расписание ПН-ВС, подходы и вес в компактном размере.")
        .supportedFamilies([.systemMedium])
    }
}
