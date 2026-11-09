import SwiftUI
import WidgetKit

private let prayerIDs = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]
private let prayerLabels = ["الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء"]
private let widgetGreen = Color(red: 0.09, green: 0.24, blue: 0.21)
private let widgetGold = Color(red: 0.81, green: 0.83, blue: 0.86)

struct PrayerHijriDate: Decodable {
  let day: Int
  let month: Int
  let year: Int
}

struct PrayerWidgetDay: Decodable {
  let date: String
  let times: [String: Double]
  let hijri: PrayerHijriDate?
}

struct PrayerWidgetCalendar: Decodable {
  let version: Int
  let location: String
  let timezone: String
  let days: [PrayerWidgetDay]

  static func load() -> PrayerWidgetCalendar? {
    guard let json = UserDefaults(suiteName: "group.com.azkar.azkar")?.string(forKey: "calendar"),
          let data = json.data(using: .utf8),
          let calendar = try? JSONDecoder().decode(PrayerWidgetCalendar.self, from: data),
          calendar.version == 1,
          TimeZone(identifier: calendar.timezone) != nil else { return nil }
    return calendar
  }
}

struct PrayerWidgetEntry: TimelineEntry {
  let date: Date
  let calendar: PrayerWidgetCalendar?

  var today: PrayerWidgetDay? {
    guard let calendar = calendar else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: calendar.timezone)
    formatter.dateFormat = "yyyy-MM-dd"
    let key = formatter.string(from: date)
    return calendar.days.first { $0.date == key }
  }

  var next: (String, Date)? {
    guard today != nil, let calendar = calendar else { return nil }
    return calendar.days.flatMap { day in
      prayerIDs.enumerated().compactMap { index, id -> (String, Date)? in
        guard id != "sunrise", let epoch = day.times[id] else { return nil }
        let time = Date(timeIntervalSince1970: epoch / 1000)
        return time > date ? (prayerLabels[index], time) : nil
      }
    }.min { $0.1 < $1.1 }
  }

  func formatted(_ time: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ar")
    formatter.timeZone = TimeZone(identifier: calendar?.timezone ?? "UTC")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: time)
  }

  var calendarDates: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ar")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: calendar?.timezone ?? "UTC")
    formatter.dateFormat = "d/M/yyyy"
    let gregorian = formatter.string(from: date)
    guard let hijri = today?.hijri else { return "\(gregorian) م • — هـ" }
    let numbers = NumberFormatter()
    numbers.locale = Locale(identifier: "ar")
    numbers.numberStyle = .none
    func local(_ value: Int) -> String { numbers.string(from: NSNumber(value: value)) ?? String(value) }
    return "\(gregorian) م • \(local(hijri.day))/\(local(hijri.month))/\(local(hijri.year)) هـ"
  }
}

struct PrayerTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> PrayerWidgetEntry {
    PrayerWidgetEntry(date: Date(), calendar: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (PrayerWidgetEntry) -> Void) {
    completion(PrayerWidgetEntry(date: Date(), calendar: PrayerWidgetCalendar.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerWidgetEntry>) -> Void) {
    let now = Date()
    let calendar = PrayerWidgetCalendar.load()
    let horizon = now.addingTimeInterval(48 * 3600)
    var dates: Set<Date> = [now]
    if let calendar = calendar {
      // Advance the next prayer at each occurrence and roll today's rows over
      // at midnight in the SELECTED location, independent of the phone's zone.
      var gregorian = Calendar(identifier: .gregorian)
      gregorian.timeZone = TimeZone(identifier: calendar.timezone) ?? .current
      for offset in 1...2 {
        if let day = gregorian.date(byAdding: .day, value: offset, to: now) {
          dates.insert(gregorian.startOfDay(for: day))
        }
      }
      for day in calendar.days {
        for epoch in day.times.values {
          let time = Date(timeIntervalSince1970: epoch / 1000)
          if time > now && time < horizon { dates.insert(time) }
        }
      }
    }
    completion(Timeline(entries: dates.sorted().map {
      PrayerWidgetEntry(date: $0, calendar: calendar)
    }, policy: .after(horizon)))
  }
}

struct PrayerWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: PrayerWidgetEntry

  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image("AzkarLogo").resizable().scaledToFit().frame(width: 20, height: 20)
        Text(entry.calendar?.location ?? "أذكار • مواقيت الصلاة")
          .font(.subheadline).lineLimit(1)
      }
      Text(entry.calendarDates).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.8)
      if let today = entry.today {
        if let next = entry.next {
          Text("القادمة: \(next.0) • \(entry.formatted(next.1))")
            .font(.subheadline).foregroundColor(widgetGold)
        }
        if family == .systemSmall {
          Text("افتح أذكار لمتابعة الصلاة").font(.caption)
        } else {
          HStack {
            ForEach(0..<prayerIDs.count, id: \.self) { index in
              VStack(spacing: 6) {
                Text(prayerLabels[index]).font(.caption)
                if let epoch = today.times[prayerIDs[index]] {
                  Text(entry.formatted(Date(timeIntervalSince1970: epoch / 1000)))
                    .font(.caption).monospacedDigit()
                }
              }.frame(maxWidth: .infinity)
            }
          }
        }
      } else {
        Text("افتح أذكار واختر موقع الصلاة لتحديث المواقيت")
          .font(.subheadline).foregroundColor(widgetGold)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .foregroundColor(.white)
    .environment(\.layoutDirection, .rightToLeft)
    .widgetURL(URL(string: "azkar://app/worship"))
  }

  var body: some View {
    if #available(iOS 17.0, *) {
      content.containerBackground(widgetGreen, for: .widget)
    } else {
      content.padding().background(widgetGreen)
    }
  }
}

struct AzkarPrayerWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "AzkarPrayerWidget", provider: PrayerTimelineProvider()) {
      PrayerWidgetView(entry: $0)
    }
    .configurationDisplayName("أذكار • مواقيت الصلاة")
    .description("مواقيت اليوم والصلاة القادمة حسب موقع الصلاة المحفوظ")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct RemembranceCard: Decodable {
  let id: String
  let title: String
  let text: String
  let route: String
}
private struct RemembrancePayload: Decodable { let cards: [RemembranceCard] }
struct RemembranceEntry: TimelineEntry { let date: Date; let card: RemembranceCard? }
struct RemembranceTimeline: TimelineProvider {
  func placeholder(in context: Context) -> RemembranceEntry { RemembranceEntry(date: Date(), card: nil) }
  private func cards() -> [RemembranceCard] {
    guard let raw = UserDefaults(suiteName: "group.com.azkar.azkar")?.string(forKey: "remembrance"),
          let data = raw.data(using: .utf8),
          let payload = try? JSONDecoder().decode(RemembrancePayload.self, from: data) else { return [] }
    return payload.cards
  }
  func getSnapshot(in context: Context, completion: @escaping (RemembranceEntry) -> Void) {
    completion(RemembranceEntry(date: Date(), card: cards().first))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<RemembranceEntry>) -> Void) {
    let items = cards()
    let now = Date()
    let offset = UserDefaults(suiteName: "group.com.azkar.azkar")?.integer(forKey: "remembranceIndex") ?? 0
    let entries = (0..<12).map { step in
      RemembranceEntry(date: now.addingTimeInterval(Double(step * 300)),
        card: items.isEmpty ? nil : items[((offset + step) % items.count + items.count) % items.count])
    }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
  }
}

struct RemembranceWidgetView: View {
  let entry: RemembranceEntry
  private var content: some View {
    VStack(spacing: 8) {
      HStack {
        Text(entry.card?.title ?? "أذكار • دعاء وإهداء").font(.caption).foregroundColor(widgetGold)
        Spacer()
      }
      Text(entry.card?.text ?? "افتح أذكار لتحديث الأذكار والإهداءات المنشورة")
        .font(.body).minimumScaleFactor(0.6).multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .foregroundColor(.white).environment(\.layoutDirection, .rightToLeft)
    .widgetURL(URL(string: "azkar://app\(entry.card?.route ?? "/")"))
  }
  var body: some View {
    if #available(iOS 17.0, *) { content.containerBackground(widgetGreen, for: .widget) }
    else { content.padding().background(widgetGreen) }
  }
}

struct AzkarRemembranceWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "AzkarRemembranceWidget", provider: RemembranceTimeline()) {
      RemembranceWidgetView(entry: $0)
    }.configurationDisplayName("أذكار • دعاء وإهداء")
      .description("أذكار وأدعية وإهداءات متجدّدة")
      .supportedFamilies([.systemMedium])
  }
}

@main
struct AzkarWidgetBundle: WidgetBundle {
  var body: some Widget {
    AzkarPrayerWidget()
    AzkarRemembranceWidget()
  }
}
