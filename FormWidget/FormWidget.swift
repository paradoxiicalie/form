import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

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
                            Text(verbatim: "\(entry.currentWeight)кг")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                            Text("·")
                                .foregroundColor(.white.opacity(0.25))
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
struct RestTimerActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // 1. Lock Screen / Always-On Display баннер
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.fromHex(context.state.themeCalHex, fallback: .red).opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "timer")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.fromHex(context.state.themeCalHex, fallback: .red))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("ОТДЫХ")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.fromHex(context.state.themeCalHex, fallback: .red))
                        Text("·")
                            .foregroundColor(.white.opacity(0.4))
                        Text(context.state.exerciseName.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Text("ДО СЛЕДУЮЩЕГО ПОДХОДА")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }
                
                Spacer()
                
                Text(context.state.endTime, style: .timer)
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color.fromHex(context.state.themeCalHex, fallback: .red))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(red: 0.07, green: 0.07, blue: 0.08))
            .widgetURL(URL(string: "form://split"))
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Развернутый вид при долгом зажатии Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .foregroundColor(Color.fromHex(context.state.themeCalHex, fallback: .red))
                        Text("ОТДЫХ")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.endTime, style: .timer)
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color.fromHex(context.state.themeCalHex, fallback: .red))
                        .monospacedDigit()
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("СЛЕДУЮЩИЙ ПОДХОД:")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                            Text(context.state.exerciseName.uppercased())
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Spacer()
                        Link(destination: URL(string: "form://split")!) {
                            Text("К ТРЕНИРОВКЕ →")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.fromHex(context.state.themeCalHex, fallback: .white)))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                // Компактный вид слева внутри острова
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.fromHex(context.state.themeCalHex, fallback: .red))
                    .padding(.leading, 4)
            } compactTrailing: {
                // Компактный вид справа внутри острова: тикающие секунды
                Text(context.state.endTime, style: .timer)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color.fromHex(context.state.themeCalHex, fallback: .red))
                    .monospacedDigit()
                    .frame(minWidth: 38)
                    .padding(.trailing, 4)
            } minimal: {
                // Минимальный вид: отдельный круглый пузырек рядом с Dynamic Island
                // (когда в основном острове играет музыка Spotify / Apple Music)
                Text(context.state.endTime, style: .timer)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color.fromHex(context.state.themeCalHex, fallback: .red))
                    .monospacedDigit()
            }
            .keylineTint(Color.fromHex(context.state.themeCalHex, fallback: .red))
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
            RestTimerActivityWidget()
        }
        #endif
    }
}
