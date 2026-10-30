import WidgetKit
import AppIntents
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

let APP_GROUP_ID = "group.com.macro.shared"

extension Color {
    init(hex: String, fallback: Color = Color(red: 0.84, green: 0.16, blue: 0.16)) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else {
            self = fallback
            return
        }
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }

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
    let restTimerEndDate: Double
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
        
        let rawTargetCal = d?.integer(forKey: "targetCal") ?? 0
        let targetCal = rawTargetCal > 0 ? rawTargetCal : 2000
        let rawTargetP = d?.integer(forKey: "targetP") ?? 0
        let targetP = rawTargetP > 0 ? rawTargetP : 140
        let rawTargetF = d?.integer(forKey: "targetF") ?? 0
        let targetF = rawTargetF > 0 ? rawTargetF : 65
        let rawTargetC = d?.integer(forKey: "targetC") ?? 0
        let targetC = rawTargetC > 0 ? rawTargetC : 215

        return MacroEntry(
            date: Date(),
            calHex: d?.string(forKey: "calHex") ?? "#E6DFD3",
            pHex: d?.string(forKey: "pHex") ?? "#9CA3AF",
            cHex: d?.string(forKey: "cHex") ?? "#C2593F",
            fHex: d?.string(forKey: "fHex") ?? "#8C8275",
            cal: d?.integer(forKey: "cal") ?? 0,
            targetCal: targetCal,
            p: d?.integer(forKey: "p") ?? 0,
            targetP: targetP,
            f: d?.integer(forKey: "f") ?? 0,
            targetF: targetF,
            c: d?.integer(forKey: "c") ?? 0,
            targetC: targetC,
            splitTitle: d?.string(forKey: "splitTitle") ?? "День 1 · Жим",
            isRestDay: d?.bool(forKey: "isRestDay") ?? false,
            setsDone: d?.integer(forKey: "setsDone") ?? 0,
            setsTarget: max(10, d?.integer(forKey: "setsTarget") ?? 60),
            weekBadges: badges.count == 7 ? badges : ["Д1","Д2","ОТД","Д3","ОТД","Д4","ОТД"],
            currentWeight: d?.string(forKey: "currentWeight") ?? "",
            stackDone: d?.integer(forKey: "stackDone") ?? 0,
            stackTotal: max(1, d?.integer(forKey: "stackTotal") ?? 4),
            restTimerEndDate: d?.double(forKey: "restTimerEndDate") ?? 0.0
        )
    }
}

// Элегантная вертикальная колонка макроса (сочное кольцо 27pt с буквой + граммы + цель)
struct MacroPillarView: View {
    let letter: String
    let label: String
    let current: Int
    let target: Int
    let color: Color
    
    var progress: Double { target > 0 ? min(1.0, Double(current) / Double(target)) : 0 }
    
    var body: some View {
        VStack(spacing: 2.5) {
            ZStack {
                // Фоновый трек кольца в мягком оттенке своего цвета
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 3.5)
                
                // Активный сектор со скругленными концами
                Circle()
                    .trim(from: 0, to: max(0.04, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                // Буква макроса по центру кольца (Б, У, Ж)
                Text(letter)
                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
            }
            .frame(width: 27, height: 27)
            
            VStack(spacing: 0.5) {
                Text("\(current)г")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("/\(target)")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
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
        let calProgress = entry.targetCal > 0 ? min(1.0, Double(entry.cal) / Double(entry.targetCal)) : 0

        VStack(alignment: .leading, spacing: 6) {
            // ВЕРХНЯЯ ЗОНА ТАПА: ведет в «РАЦИОН»
            Link(destination: URL(string: "form://diet")!) {
                VStack(alignment: .leading, spacing: 5.5) {
                    // 1. Шапка: бренд + умный вес и статус стека
                    HStack {
                        HStack(spacing: 3.5) {
                            Text("FORM")
                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                            Text("// РАЦИОН & ТРЕНИ")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            if !entry.currentWeight.isEmpty && entry.currentWeight != "0" {
                                Text(verbatim: "\(entry.currentWeight)кг")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                Text("·")
                                    .foregroundColor(.white.opacity(0.25))
                            }
                            if entry.stackDone >= entry.stackTotal && entry.stackTotal > 0 {
                                HStack(spacing: 2) {
                                    Text("Стек")
                                    Text("✓")
                                        .foregroundColor(Color.green)
                                    Text(verbatim: "\(entry.stackDone)/\(entry.stackTotal)")
                                }
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color.green)
                            } else {
                                Text(verbatim: "Стек \(entry.stackDone)/\(entry.stackTotal)")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }
                    }

                    // 2. Блок питания: Крупный фокус на Калориях (Hero) слева + Трио макросов Б · У · Ж справа
                    HStack(alignment: .center, spacing: 9) {
                        // Калории: выразительное кольцо с огоньком + крупные цифры съедено / осталось
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(calColor.opacity(0.18), lineWidth: 4)
                                Circle()
                                    .trim(from: 0, to: max(0.04, calProgress))
                                    .stroke(calColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(calColor)
                            }
                            .frame(width: 36, height: 36)
                            
                            VStack(alignment: .leading, spacing: 0.5) {
                                Text("КАЛОРИИ")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.45))
                                HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                                    Text("\(entry.cal)")
                                        .font(.system(size: 16.5, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text("ккал")
                                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                let leftCal = max(0, entry.targetCal - entry.cal)
                                Text("еще \(leftCal)")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(calColor)
                            }
                        }
                        
                        // Тонкий вертикальный разделитель
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 0.5, height: 42)

                        // Трио макросов в классическом порядке КБЖУ (Белки -> Жиры -> Углеводы)
                        HStack(spacing: 3) {
                            MacroPillarView(letter: "Б", label: "Белки", current: entry.p, target: entry.targetP, color: pColor)
                            MacroPillarView(letter: "Ж", label: "Жиры",  current: entry.f, target: entry.targetF, color: fColor)
                            MacroPillarView(letter: "У", label: "Угли",  current: entry.c, target: entry.targetC, color: cColor)
                        }
                    }
                }
            }

            // Тончайший разделитель между блоком питания и тренировками
            Rectangle()
                .fill(Color.white.opacity(0.065))
                .frame(height: 0.5)
                .padding(.vertical, 0.5)

            // НИЖНЯЯ ЗОНА ТАПА: ведет в «ТРЕНИ»
            Link(destination: URL(string: "form://split")!) {
                VStack(spacing: 5) {
                    // 3. Полоска расписания ПН - ВС (воздушный таймлайн)
                    HStack(spacing: 3.5) {
                        ForEach(Array(0..<7), id: \.self) { (idx: Int) in
                            let badge = entry.weekBadges[idx].replacingOccurrences(of: "День ", with: "Д")
                            let isRest = badge == "ОТД"
                            let isToday = idx == currentMondayIndex
                            
                            VStack(spacing: 2) {
                                Text(dayLabels[idx])
                                    .font(.system(size: 8, weight: isToday ? .heavy : .semibold, design: .monospaced))
                                    .foregroundColor(isToday ? Color.white : Color.white.opacity(0.38))
                                
                                Text(badge)
                                    .font(.system(size: 8.5, weight: isToday ? .heavy : (isRest ? .medium : .bold), design: .monospaced))
                                    .foregroundColor(isToday ? Color.contrastText(forHex: entry.calHex) : (isRest ? Color.white.opacity(0.32) : Color.white.opacity(0.9)))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(isToday ? calColor : (isRest ? Color.white.opacity(0.03) : Color.white.opacity(0.065)))
                                    )
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isToday ? calColor.opacity(0.16) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isToday ? calColor.opacity(0.7) : Color.clear, lineWidth: 1)
                                    )
                            )
                        }
                    }

                    // 4. Нижняя строка: если идет отдых между подходами — ЖИВОЙ ТАЙМЕР, иначе программа и подходы
                    let nowMs = Date().timeIntervalSince1970 * 1000.0
                    let isRestActive = entry.restTimerEndDate > nowMs
                    
                    if isRestActive {
                        let restEnd = Date(timeIntervalSince1970: entry.restTimerEndDate / 1000.0)
                        HStack(spacing: 5) {
                            Image(systemName: "timer")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(calColor)
                            Text("ОТДЫХ:")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text(restEnd, style: .timer)
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundColor(calColor)
                                .monospacedDigit()
                            Spacer()
                            Text(entry.splitTitle.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(calColor.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(calColor.opacity(0.35), lineWidth: 0.8))
                        )
                    } else {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(entry.isRestDay ? Color.white.opacity(0.3) : calColor)
                                .frame(width: 4.5, height: 4.5)
                            Text(entry.isRestDay ? "ОТДЫХ // ВОССТАНОВЛЕНИЕ" : entry.splitTitle.uppercased())
                                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.95))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                let pct = entry.setsTarget > 0 ? min(1.0, Double(entry.setsDone) / Double(entry.setsTarget)) : 0
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.16))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
                                    Capsule()
                                        .fill(calColor)
                                        .frame(width: max(3.5, 34 * CGFloat(pct)))
                                }
                                .frame(width: 34, height: 4)
                                
                                Text(verbatim: "\(entry.setsDone)/\(entry.setsTarget)")
                                    .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                                    .foregroundColor(calColor)
                                Text("подх.")
                                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 2)
        .containerBackground(.ultraThinMaterial, for: .widget)
        .environment(\.colorScheme, .dark)
    }
}

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

// =============================================================================
// LIVE ACTIVITY & DYNAMIC ISLAND ДЛЯ ТАЙМЕРА ОТДЫХА МЕЖДУ ПОДХОДАМИ
// =============================================================================
#if canImport(ActivityKit)

@available(iOS 16.2, *)
struct RestTimerLiveActivity: Widget {
    private func accentColor(_ hex: String) -> Color {
        let c = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: c).scanHexInt64(&int)
        if c.count == 6 {
            let r = Double((int >> 16) & 0xFF) / 255.0
            let g = Double((int >> 8) & 0xFF) / 255.0
            let b = Double(int & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        return Color(red: 0.84, green: 0.16, blue: 0.16)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            let accent = accentColor(context.state.themeCalHex)
            let range = context.state.startDate...context.state.endDate

            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(accent.opacity(0.45), lineWidth: 1)
                            )
                            .frame(width: 38, height: 38)

                        Image(systemName: context.isStale ? "checkmark" : "timer")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(accent)
                                .frame(width: 5, height: 5)
                            Text(context.isStale ? "ОТДЫХ ОКОНЧЕН" : "ОТДЫХ // ТАЙМЕР")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(accent)
                        }

                        Text(context.state.exerciseName.uppercased())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(context.isStale ? "ВРЕМЯ РАБОЧЕГО ПОДХОДА" : "ДО СЛЕДУЮЩЕГО ПОДХОДА")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    if !context.isStale {
                        Text(timerInterval: range, countsDown: true)
                            .monospacedDigit()
                            .font(.system(size: 24, weight: .black, design: .monospaced))
                            .foregroundColor(accent)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72, alignment: .trailing)
                    }

                    if #available(iOS 17.0, *) {
                        Button(intent: StopRestTimerIntent()) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                    )
                                    .frame(width: 32, height: 32)

                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(white: 0.85))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !context.isStale {
                    ProgressView(timerInterval: range, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .activityBackgroundTint(Color(red: 0.05, green: 0.05, blue: 0.06))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "form://split"))

        } dynamicIsland: { context in
            let accent = accentColor(context.state.themeCalHex)
            let range = context.state.startDate...context.state.endDate

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(accent)
                        Text("FORM // REST")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(white: 0.8))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 8) {
                        if context.isStale {
                            Text("ГОТОВО")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundColor(accent)
                        } else {
                            Text(timerInterval: range, countsDown: true)
                                .monospacedDigit()
                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                .foregroundColor(accent)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 64, alignment: .trailing)
                        }

                        if #available(iOS 17.0, *) {
                            Button(intent: StopRestTimerIntent()) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: 26, height: 26)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(context.state.exerciseName.uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(context.isStale ? "В РАБОЧИЙ ПОДХОД" : "СЛЕД. ПОДХОД")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(context.isStale ? accent : Color(white: 0.5))
                        }

                        if !context.isStale {
                            ProgressView(timerInterval: range, countsDown: true) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(accent)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }

            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: context.isStale ? "checkmark" : "timer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accent)
                    Text("ОТД")
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                }
                .fixedSize()

            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accent)
                } else {
                    Text("0:00")
                        .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                        .hidden()
                        .overlay(alignment: .trailing) {
                            Text(timerInterval: range, countsDown: true)
                                .monospacedDigit()
                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                .foregroundColor(accent)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 46, alignment: .trailing)
                        }
                }

            } minimal: {
                if context.isStale {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(accent)
                } else {
                    Text("0:00")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .hidden()
                        .overlay(alignment: .center) {
                            Text(timerInterval: range, countsDown: true)
                                .monospacedDigit()
                                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                                .foregroundColor(accent)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.7)
                                .frame(width: 36, alignment: .center)
                        }
                }
            }
            .keylineTint(accent)
            .widgetURL(URL(string: "form://split"))
        }
    }
}
#endif

@main
struct FormWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacroWidget()
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            RestTimerLiveActivity()
        }
        #endif
    }
}
