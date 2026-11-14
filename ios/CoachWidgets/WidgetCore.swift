import Foundation

// Auszug aus CoachCore (Swift-App Coach-App, Stand 793d408): nur die Typen, die Widgets und Live-Aktivitäten
// brauchen. Die Logik dahinter rechnet die Flutter-App (coach_core) und schreibt sie als `widget-snapshot.json` in die
// App Group; Dateiformat und Bedeutung bleiben gleich. Änderungen an diesen Typen immer auch in
// `packages/coach_core/lib/src/widgets/widget_snapshot.dart` nachziehen.

/// Kalendertag ohne Uhrzeit und Zeitzone (Garmins `calendarDate`, z. B. `2026-10-23`).
public struct CalendarDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
  public let year: Int
  public let month: Int
  public let day: Int

  public init(year: Int, month: Int, day: Int) {
    self.year = year
    self.month = month
    self.day = day
  }

  /// Liest `yyyy-MM-dd`, auch mit angehängter Uhrzeit (`2026-10-23T00:00:00.0`).
  public init?(iso text: String) {
    let parts = text.prefix(10).split(separator: "-")
    guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      (1...12).contains(month), (1...31).contains(day)
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  public init(date: Date, timeZone: TimeZone = .current) {
    let components = Self.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
    self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
  }

  public var iso: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }

  public var description: String { iso }

  /// Mittag UTC des Tages – stabil für Datumsrechnung ohne Sommerzeit-Effekte.
  public var referenceDate: Date {
    let components = DateComponents(year: year, month: month, day: day, hour: 12)
    let utc = TimeZone(identifier: "UTC") ?? .current
    return Self.calendar(utc).date(from: components) ?? Date(timeIntervalSince1970: 0)
  }

  public func adding(days: Int) -> CalendarDay {
    let utc = TimeZone(identifier: "UTC") ?? .current
    let date = Self.calendar(utc).date(byAdding: .day, value: days, to: referenceDate) ?? referenceDate
    return CalendarDay(date: date, timeZone: utc)
  }

  /// Anzahl Tage von `self` bis `other` (positiv, wenn `other` später liegt).
  public func days(until other: CalendarDay) -> Int {
    let seconds = other.referenceDate.timeIntervalSince(referenceDate)
    return Int((seconds / 86_400).rounded())
  }

  public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
    (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
  }

  private static func calendar(_ timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }
}

public enum MealCategory: String, CaseIterable, Codable, Sendable {
  case breakfast = "fruehstueck"
  case lunch = "mittagessen"
  case dinner = "abendessen"
  case snack
  case other = "sonstiges"

  public var label: String {
    switch self {
    case .breakfast: "Frühstück"
    case .lunch: "Mittagessen"
    case .dinner: "Abendessen"
    case .snack: "Snack"
    case .other: "Sonstiges"
    }
  }

  /// Kategorie nach Uhrzeit (wie `guess_category` im Altbestand).
  public static func guess(hour: Int, minute: Int) -> MealCategory {
    let time = Double(hour) + Double(minute) / 60
    if 4 <= time && time < 10.5 { return .breakfast }
    if 10.5 <= time && time < 14.5 { return .lunch }
    if 17.5 <= time && time < 21.5 { return .dinner }
    return .snack
  }
}

/// Kalorienziel je Mahlzeit für Übersicht und Widget (wie gängige Ernährungs-Apps): Frühstück 25 %, Mittag 35 %,
/// Abend 30 %, Snacks 10 % der Tagesenergie. Eine Orientierung, keine Regel – gezählt wird der Tag.
public enum MealSplit {
  public static let order: [MealCategory] = [.breakfast, .lunch, .dinner, .snack]

  public static func share(_ category: MealCategory) -> Double {
    switch category {
    case .breakfast: 0.25
    case .lunch: 0.35
    case .dinner: 0.30
    case .snack, .other: 0.10
    }
  }

  /// „Sonstiges“ zählt zu den Snacks.
  public static func slot(_ category: MealCategory) -> MealCategory {
    category == .other ? .snack : category
  }

  public static func target(_ category: MealCategory, dayKilocalories: Double?) -> Double? {
    dayKilocalories.map { ($0 * share(slot(category))).rounded() }
  }
}

public enum RecoveryLevel: String, Codable, Sendable, Comparable, CaseIterable {
  case normal
  case locker
  case pause

  private var severity: Int {
    switch self {
    case .normal: 0
    case .locker: 1
    case .pause: 2
    }
  }

  public static func < (lhs: RecoveryLevel, rhs: RecoveryLevel) -> Bool {
    lhs.severity < rhs.severity
  }

  public var label: String {
    switch self {
    case .normal: "Normal trainieren"
    case .locker: "Locker / verkürzt"
    case .pause: "Ruhetag oder sehr locker"
    }
  }

  public var advice: String {
    switch self {
    case .normal: "Geplante Einheit wie vorgesehen durchziehen."
    case .locker:
      "Einheit machen, aber Intensität raus: harte Intervalle durch lockeres Training ersetzen oder um ein "
        + "Drittel kürzen."
    case .pause: "Heute Ruhetag – höchstens 20–30 min sehr locker bewegen."
    }
  }
}

public enum GermanFormat {
  /// Eine Nachkommastelle mit Komma, ohne „,0“ bei ganzen Zahlen: 4,5 / 6.
  public static func decimal(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
  }

  /// Bis zu zwei Nachkommastellen mit Komma, ohne Nullen am Ende: 52,5 / 13,75 / 55 (wie `%g`).
  public static func number(_ value: Double) -> String {
    let rounded = (value * 100).rounded() / 100
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    var text = String(format: "%.2f", rounded)
    while text.hasSuffix("0") { text.removeLast() }
    return text.replacingOccurrences(of: ".", with: ",")
  }

  /// `dd.MM.yyyy`
  public static func date(_ day: CalendarDay) -> String {
    String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
  }

  /// `m:ss`
  public static func minutesSeconds(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

/// Nur die Einordnung des Morning Reports (die Auswertung selbst rechnet die App).
public enum MorningReport {
  public enum Status: String, Codable, Equatable, Sendable {
    case good, normal, attention, missing
  }

  public enum Metric: String, CaseIterable, Sendable {
    case sleepDuration, sleepQuality, sleepStages, restingHeartRate, hrv, stress, bodyBattery, recovery, load

    public var title: String {
      switch self {
      case .sleepDuration: "Schlafdauer"
      case .sleepQuality: "Schlafqualität"
      case .sleepStages: "Schlafphasen"
      case .restingHeartRate: "Ruhepuls"
      case .hrv: "HRV"
      case .stress: "Stress"
      case .bodyBattery: "Body Battery"
      case .recovery: "Erholung"
      case .load: "Trainingsbelastung"
      }
    }
  }
}

public enum AppTab: String, Codable, CaseIterable, Sendable {
  case today, activities, training, nutrition
}

/// Ziele, die von außen angesprungen werden: Schnellaktionen am App-Icon, Kurzbefehle/Siri und (später)
/// Homescreen-Widgets. Eine Route wählt den Reiter und optional eine Aktion darin; als Link `coach://open/<route>`.
public enum AppRoute: String, Codable, CaseIterable, Sendable, Identifiable {
  case today
  /// Gesundheitsbereich (Morning Report, Widgets, Body Battery) im Reiter Training.
  case health
  case nutrition
  /// Erfassen-Bildschirm der Ernährung öffnen.
  case logMeal
  case gym
  /// Laufende Einheit öffnen, sonst die nächste geplante starten (zählt erst mit dem ersten Satz).
  case startWorkout
  case ai
  /// KI-Analyse über alle Themen anstoßen (nur wenn die KI eingerichtet und erlaubt ist).
  case aiAnalysis

  public static let scheme = "coach"
  public static let host = "open"

  public var id: String { rawValue }

  public init?(url: URL) {
    guard url.scheme == Self.scheme, url.host() == Self.host else { return nil }
    let name = url.pathComponents.first { $0 != "/" } ?? ""
    self.init(rawValue: name)
  }

  public var url: URL {
    URL(string: "\(Self.scheme)://\(Self.host)/\(rawValue)") ?? URL(fileURLWithPath: "/")
  }

  /// „Mahlzeit erfassen“ für eine bestimmte Mahlzeit (Mahlzeiten-Widget): `coach://open/logMeal?mahlzeit=…`.
  public static func logMealURL(_ category: MealCategory) -> URL {
    URL(string: "\(AppRoute.logMeal.url.absoluteString)?mahlzeit=\(category.rawValue)") ?? AppRoute.logMeal.url
  }

  /// Mahlzeit aus einem Link (`?mahlzeit=mittagessen`), sonst `nil`.
  public static func mealCategory(from url: URL) -> MealCategory? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == "mahlzeit" }?.value.flatMap(MealCategory.init(rawValue:))
  }

  /// Reiter der Route. Gym-Ziele öffnen den Gym-Bereich im Reiter Training, KI-Ziele die Empfehlungen über „Heute“.
  public var tab: AppTab {
    switch self {
    case .today, .ai, .aiAnalysis: .today
    case .health, .gym, .startWorkout: .training
    case .nutrition, .logMeal: .nutrition
    }
  }

  /// Aktion im Reiter, die die Zielansicht einmal ausführt (danach gilt die Route als erledigt).
  public var hasAction: Bool {
    switch self {
    case .health, .logMeal, .gym, .startWorkout, .ai, .aiAnalysis: true
    default: false
    }
  }

  /// Bereich, den der Reiter zuerst öffnen muss, bevor die Zielansicht die Aktion übernimmt
  /// („Training starten“ öffnet erst den Gym-Bereich, „KI-Analyse“ erst die Empfehlungen).
  public var opensArea: AppRoute? {
    switch self {
    case .gym, .startWorkout: .gym
    case .ai, .aiAnalysis: .ai
    default: nil
    }
  }

  public var title: String {
    switch self {
    case .today: "Heute"
    case .health: "Health öffnen"
    case .nutrition: "Ernährung"
    case .logMeal: "Mahlzeit erfassen"
    case .gym: "Gym"
    case .startWorkout: "Training starten"
    case .ai: "AI"
    case .aiAnalysis: "KI-Analyse starten"
    }
  }

  public var subtitle: String? {
    switch self {
    case .health: "Morning Report, Body Battery, Schlaf"
    case .logMeal: "Foto, Text, Barcode oder Suche"
    case .startWorkout: "Nächste Einheit oder laufende fortsetzen"
    case .aiAnalysis: "Alle Themen auswerten"
    default: nil
    }
  }

  /// SF-Symbol.
  public var symbol: String {
    switch self {
    case .today: "sun.max"
    case .health: "heart.text.square"
    case .nutrition: "fork.knife"
    case .logMeal: "plus.circle"
    case .gym, .startWorkout: "dumbbell"
    case .ai, .aiAnalysis: "sparkles"
    }
  }
}


/// Was die Homescreen-Widgets zeigen. Die App schreibt den Stand in die App Group (nach Abruf, beim Verlassen,
/// im Hintergrund), die Widgets lesen nur diese Datei – kein Zugriff auf die Datenbank der App. Werte sind schon
/// formatiert bzw. fertig berechnet; die Widgets rechnen nur Tageswechsel und wartende Wasser-Einträge ein.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
  public static let fileName = "widget-snapshot.json"
  public static let currentVersion = 1

  public var version: Int
  public var createdAt: Date
  /// Tag, für den die Werte gelten.
  public var day: CalendarDay
  public var today: Today
  public var nutrition: Nutrition?
  /// `nil` ohne Krafttraining im Profil.
  public var gym: Gym?
  /// Gesundheitswerte der letzten Nacht in fester Reihenfolge (nur Metriken des Morning Reports).
  public var health: [Health]
  /// Tages-Serie (`DailyStreak`); fehlt in älteren Ständen.
  public var streak: Streak?
  /// Serie der Mahlzeiten: nur Tage mit eingetragener Mahlzeit, lückenlos (ohne Joker, ohne Training von der Uhr).
  /// Für die Mahlzeiten- und Ernährungs-Anzeigen; fehlt in älteren Ständen.
  public var mealStreak: Streak?

  public init(
    createdAt: Date, day: CalendarDay, today: Today, nutrition: Nutrition?, gym: Gym?, health: [Health]
  ) {
    version = Self.currentVersion
    self.createdAt = createdAt
    self.day = day
    self.today = today
    self.nutrition = nutrition
    self.gym = gym
    self.health = health
  }

  /// Tage in Folge mit Training oder Mahlzeit, für die Kopfzeile der Widgets.
  public struct Streak: Codable, Equatable, Sendable {
    public var days: Int
    /// Heute ist schon etwas erfasst.
    public var activeToday: Bool

    public init(days: Int, activeToday: Bool) {
      self.days = days
      self.activeToday = activeToday
    }

    /// Kurzer Satz zur Serie. Kein Druck: Ohne Eintrag heute steht nur, was die Serie fortsetzt.
    public var headline: String {
      if days <= 0 { return "Heute starten – erster Tag!" }
      if !activeToday { return "Heute noch etwas erfassen" }
      if isRunning { return "Serie läuft – weiter so!" }
      return "Guter Start – dranbleiben!"
    }

    /// Erst ab drei Tagen in Folge und mit Eintrag heute ist es eine laufende Serie.
    public var isRunning: Bool { days >= 3 && activeToday }
  }

  public struct Today: Codable, Equatable, Sendable {
    /// Tagesampel; `nil` ohne Erholungswerte.
    public var level: RecoveryLevel?
    public var headline: String
    public var sessions: [Session]
    /// „3/5 Einheiten · 140/210 min“
    public var week: String?
    public var weekFraction: Double?

    public init(
      level: RecoveryLevel?, headline: String, sessions: [Session] = [], week: String? = nil,
      weekFraction: Double? = nil
    ) {
      self.level = level
      self.headline = headline
      self.sessions = sessions
      self.week = week
      self.weekFraction = weekFraction
    }

    /// Erste noch offene Einheit des Tages.
    public var nextSession: Session? { sessions.first { !$0.done } }
  }

  public struct Session: Codable, Equatable, Sendable {
    public var title: String
    public var target: String
    public var done: Bool
    /// SF-Symbol der Sportart.
    public var symbol: String

    public init(title: String, target: String, done: Bool, symbol: String) {
      self.title = title
      self.target = target
      self.done = done
      self.symbol = symbol
    }
  }

  public struct Nutrition: Codable, Equatable, Sendable {
    public var kcal: Double
    /// `nil`, wenn kein Ziel berechnet werden konnte (fehlendes Profil).
    public var kcalTarget: Double?
    public var protein: Double
    public var proteinTarget: Double?
    public var waterMilliliters: Double
    public var waterTarget: Double?
    public var lastMeal: LastMeal?
    /// kcal je Mahlzeit (Frühstück, Mittag, Abend, Snacks); `nil` bei Ständen von vor dem Mahlzeiten-Widget.
    public var meals: [MealPart]?

    public init(
      kcal: Double, kcalTarget: Double?, protein: Double, proteinTarget: Double?, waterMilliliters: Double,
      waterTarget: Double?, lastMeal: LastMeal?, meals: [MealPart]? = nil
    ) {
      self.kcal = kcal
      self.kcalTarget = kcalTarget
      self.protein = protein
      self.proteinTarget = proteinTarget
      self.waterMilliliters = waterMilliliters
      self.waterTarget = waterTarget
      self.lastMeal = lastMeal
      self.meals = meals
    }

    /// Übrig (negativ = darüber); `nil` ohne Ziel.
    public var kcalRemaining: Double? { kcalTarget.map { $0 - kcal } }

    public var kcalFraction: Double? { Self.fraction(kcal, kcalTarget) }
    public var proteinFraction: Double? { Self.fraction(protein, proteinTarget) }
    public var waterFraction: Double? { Self.fraction(waterMilliliters, waterTarget) }

    static func fraction(_ value: Double, _ target: Double?) -> Double? {
      guard let target, target > 0 else { return nil }
      return min(max(value / target, 0), 1)
    }
  }

  /// Eine Mahlzeit im Mahlzeiten-Widget: gegessen und Richtwert (Anteil am Tagesziel, `MealSplit`).
  public struct MealPart: Codable, Equatable, Sendable, Identifiable {
    public var category: MealCategory
    public var kcal: Double
    public var target: Double?
    public var id: MealCategory { category }

    public init(category: MealCategory, kcal: Double, target: Double?) {
      self.category = category
      self.kcal = kcal
      self.target = target
    }

    public var fraction: Double? { Nutrition.fraction(kcal, target) }
  }

  public struct LastMeal: Codable, Equatable, Sendable {
    public var title: String
    public var at: Date
    public var kcal: Double

    public init(title: String, at: Date, kcal: Double) {
      self.title = title
      self.at = at
      self.kcal = kcal
    }
  }

  public struct Gym: Codable, Equatable, Sendable {
    /// Nächste geplante Einheit (Routine bzw. Einheit laut Plan).
    public var next: String?
    public var nextDetail: String?
    /// Eine Einheit läuft (mindestens ein Satz).
    public var running: Bool
    public var runningTitle: String?
    public var last: LastSession?
    public var weekDone: Int
    /// Geplante Krafteinheiten dieser Woche; `nil`, wenn der Plan keine Zahl hergibt.
    public var weekPlanned: Int?
    /// `next` gehört zu genau diesem Tag (Plan-Einheit statt Routine) und gilt am Folgetag nicht mehr.
    public var nextIsForDay: Bool?

    public init(
      next: String?, nextDetail: String?, running: Bool, runningTitle: String?, last: LastSession?, weekDone: Int,
      weekPlanned: Int?
    ) {
      self.next = next
      self.nextDetail = nextDetail
      self.running = running
      self.runningTitle = runningTitle
      self.last = last
      self.weekDone = weekDone
      self.weekPlanned = weekPlanned
    }

    /// „2/3 diese Woche“ bzw. „2 diese Woche“.
    public var weekText: String {
      weekPlanned.map { "\(weekDone)/\($0) diese Woche" } ?? "\(weekDone) diese Woche"
    }
  }

  public struct LastSession: Codable, Equatable, Sendable {
    public var title: String
    public var day: CalendarDay
    public var sets: Int
    public var volumeKg: Double

    public init(title: String, day: CalendarDay, sets: Int, volumeKg: Double) {
      self.title = title
      self.day = day
      self.sets = sets
      self.volumeKg = volumeKg
    }
  }

  public struct Health: Codable, Equatable, Sendable {
    public var metric: HealthMetric
    /// Formatiert („7,4 h“, „62 ms“); `nil` = kein Wert.
    public var value: String?
    /// Zahl für Ringe (Body Battery 0–100); sonst `nil`.
    public var gauge: Double?
    public var status: MorningReport.Status
    public var note: String

    public init(metric: HealthMetric, value: String?, gauge: Double?, status: MorningReport.Status, note: String) {
      self.metric = metric
      self.value = value
      self.gauge = gauge
      self.status = status
      self.note = note
    }
  }

  public func health(_ metric: HealthMetric) -> Health? {
    health.first { $0.metric == metric }
  }
}

/// Gesundheitswerte, die ein Widget zeigen kann – die Kernwerte des Morning Reports.
public enum HealthMetric: String, Codable, CaseIterable, Sendable {
  case bodyBattery, sleep, hrv, recovery, restingHeartRate, stress

  public var title: String {
    switch self {
    case .bodyBattery: "Body Battery"
    case .sleep: "Schlaf"
    case .hrv: "HRV"
    case .recovery: "Recovery"
    case .restingHeartRate: "Ruhepuls"
    case .stress: "Stress"
    }
  }

  public var symbol: String {
    switch self {
    case .bodyBattery: "battery.75percent"
    case .sleep: "bed.double.fill"
    case .hrv: "waveform.path.ecg"
    case .recovery: "arrow.clockwise.heart"
    case .restingHeartRate: "heart.fill"
    case .stress: "brain.head.profile"
    }
  }

  /// Entsprechender Wert im Morning Report.
  public var reportMetric: MorningReport.Metric {
    switch self {
    case .bodyBattery: .bodyBattery
    case .sleep: .sleepDuration
    case .hrv: .hrv
    case .recovery: .recovery
    case .restingHeartRate: .restingHeartRate
    case .stress: .stress
    }
  }
}

// MARK: - Anzeige

extension WidgetSnapshot {
  /// Stand für die Anzeige an `day`: Am neuen Tag ist nichts gegessen und nichts geplant bekannt (keine Schätzung –
  /// das Widget bittet ums Öffnen der App); Gesundheitswerte gelten ab dem Folgetag als alt. Wartende
  /// Wasser-Einträge aus dem Widget zählen sofort mit.
  public func display(on day: CalendarDay, queue: WidgetActionQueue = WidgetActionQueue()) -> Display {
    var snapshot = self
    let isCurrent = day == self.day
    if !isCurrent {
      // Am Folgetag läuft die Serie weiter, heute ist aber noch nichts erfasst; älter ist sie unbekannt.
      if day == self.day.adding(days: 1) {
        snapshot.streak?.activeToday = false
        snapshot.mealStreak?.activeToday = false
      } else {
        snapshot.streak = nil
        snapshot.mealStreak = nil
      }
      snapshot.today = Today(level: nil, headline: "Neuer Tag – App öffnen")
      snapshot.nutrition = nutrition.map { _ in
        Nutrition(
          kcal: 0, kcalTarget: nil, protein: 0, proteinTarget: nil, waterMilliliters: 0, waterTarget: nil,
          lastMeal: nil, meals: MealSplit.order.map { MealPart(category: $0, kcal: 0, target: nil) })
      }
      if var gym = snapshot.gym {
        gym.running = false
        gym.runningTitle = nil
        if gym.nextIsForDay == true {
          gym.next = "App öffnen"
          gym.nextDetail = nil
        }
        // Neue Woche: Zählung beginnt von vorn.
        if day.adding(days: -day.weekdayIndex) != self.day.adding(days: -self.day.weekdayIndex) { gym.weekDone = 0 }
        snapshot.gym = gym
      }
    }
    let pendingWater = queue.water(on: day)
    if pendingWater > 0, var nutrition = snapshot.nutrition {
      nutrition.waterMilliliters += pendingWater
      snapshot.nutrition = nutrition
    }
    return Display(snapshot: snapshot, isCurrent: isCurrent, healthIsOld: day > self.day)
  }

  public struct Display: Equatable, Sendable {
    public var snapshot: WidgetSnapshot
    /// Stand ist von heute.
    public var isCurrent: Bool
    /// Gesundheitswerte stammen nicht von der letzten Nacht: Der Stand ist von einem früheren Tag.
    public var healthIsOld: Bool
  }
}

/// Aktionen aus interaktiven Widgets, die die App beim nächsten Öffnen übernimmt (das Widget kann die Datenbank
/// der App nicht schreiben). Heute nur Wasser.
public struct WidgetActionQueue: Codable, Equatable, Sendable {
  public static let fileName = "widget-actions.json"
  /// Ältere Einträge verfallen (App lange nicht geöffnet) statt Tage später aufzutauchen.
  public static let maxAgeDays = 7

  public struct Entry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var day: CalendarDay
    public var at: Date
    public var waterMilliliters: Double

    public init(id: UUID = UUID(), day: CalendarDay, at: Date, waterMilliliters: Double) {
      self.id = id
      self.day = day
      self.at = at
      self.waterMilliliters = waterMilliliters
    }
  }

  public var entries: [Entry]

  public init(entries: [Entry] = []) {
    self.entries = entries
  }

  public mutating func addWater(_ milliliters: Double, at date: Date) {
    guard milliliters > 0, milliliters.isFinite else { return }
    entries.append(Entry(day: CalendarDay(date: date), at: date, waterMilliliters: milliliters))
  }

  public func water(on day: CalendarDay) -> Double {
    entries.filter { $0.day == day }.reduce(0) { $0 + $1.waterMilliliters }
  }

  /// Einträge, die die App übernehmen soll (nicht älter als `maxAgeDays`).
  public func pending(today: CalendarDay) -> [Entry] {
    let oldest = today.adding(days: -Self.maxAgeDays)
    return entries.filter { $0.day >= oldest && $0.day <= today }
  }

  /// Nach dem Übernehmen: genau diese Einträge entfernen (später hinzugekommene bleiben).
  public mutating func remove(_ ids: Set<UUID>) {
    entries.removeAll { ids.contains($0.id) }
  }
}


/// Liest die App Groups aus dem eingebetteten Provisioning-Profil (`embedded.mobileprovision`). SideStore hängt bei
/// kostenlosen Konten die Team-ID an (`group.<id>.<TEAMID>`), die App kennt sie also nicht im Voraus.
public enum AppGroupProfile {
  /// Gruppe, die App und Widgets teilen (wie in `project.yml`).
  public static let baseIdentifier = "group.io.github.hkrb7p794w.coach"
  static let entitlementKey = "com.apple.security.application-groups"

  /// Gruppen aus dem Profil (eine CMS-Signatur um eine XML-Plist).
  public static func groups(fromProfile data: Data) -> [String] {
    guard let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
    else { return [] }
    let plist = data.subdata(in: start.lowerBound..<end.upperBound)
    guard
      let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
      let entitlements = root["Entitlements"] as? [String: Any]
    else { return [] }
    return entitlements[entitlementKey] as? [String] ?? []
  }

  /// Kandidaten in der Reihenfolge der Prüfung: passende Gruppen aus dem Profil (kürzeste zuerst), dann die
  /// unveränderte ID (normale Signatur, Simulator).
  public static func candidates(profileGroups: [String], base: String = baseIdentifier) -> [String] {
    let matching = profileGroups.filter { $0 == base || $0.hasPrefix(base + ".") }
      .sorted { ($0.count, $0) < ($1.count, $1) }
    return matching + (matching.contains(base) ? [] : [base])
  }
}


/// Kopfzeile der Mahlzeiten-Anzeigen (Homescreen-Widget, Karte auf dem Sperrbildschirm): ein Satz, der zum Stand
/// des Tages passt – was eingetragen ist, was als Nächstes ansteht, wie viel übrig ist, wie die Serie steht.
/// Feste Regeln, keine KI. Kein Druck: nichts droht mit Verlust, und ohne Kalorienziel (z. B. gesperrte
/// Gewichtsziele) nennt der Satz keine Kalorien.
public enum MealHeadline {
  /// Kurze Namen, damit der Satz in eine Zeile passt.
  static func name(_ category: MealCategory) -> String {
    switch category {
    case .breakfast: "Frühstück"
    case .lunch: "Mittagessen"
    case .dinner: "Abendessen"
    case .snack, .other: "Snack"
    }
  }

  /// - Parameters:
  ///   - meals: Mahlzeiten des Tages in fester Reihenfolge (`MealSplit.order`).
  ///   - kcalRemaining: übrige Kalorien (negativ = darüber); `nil` ohne Ziel.
  ///   - streak: Serie der Mahlzeiten.
  ///   - hour: Stunde des Tages (0–23), für den Satz vor dem ersten Eintrag.
  public static func text(
    meals: [WidgetSnapshot.MealPart], kcalRemaining: Double?, kcalTarget: Double? = nil,
    streak: WidgetSnapshot.Streak?, hour: Int
  ) -> String {
    let mains = meals.filter { $0.category != .snack && $0.category != .other }
    let logged = meals.filter { $0.kcal > 0 }
    let loggedMains = mains.filter { $0.kcal > 0 }
    let days = streak?.days ?? 0

    // Noch nichts eingetragen: nach Tageszeit, mit laufender Serie der nächste Tag.
    if logged.isEmpty {
      if days >= 2 { return "Tag \(days + 1) der Serie – los geht’s" }
      switch hour {
      case ..<10: return "Guten Morgen – Frühstück eintragen?"
      case ..<15: return "Mittagessen eintragen?"
      case ..<21: return "Heute noch nichts eingetragen"
      default: return "Noch kurz den Tag eintragen?"
      }
    }

    // Alle Hauptmahlzeiten eingetragen: Tagesbilanz.
    if !mains.isEmpty, loggedMains.count == mains.count {
      guard let remaining = kcalRemaining else {
        return days >= 3 ? "Alles eingetragen – Tag \(days) der Serie" : "Alles eingetragen – stark!"
      }
      let tolerance = max((kcalTarget ?? 2_000) * 0.07, 100)
      if abs(remaining) <= tolerance { return "Tagesziel getroffen – stark!" }
      if remaining > 0 { return "Alles eingetragen · noch \(Int(remaining.rounded())) kcal frei" }
      return "Alles eingetragen · \(Int((-remaining).rounded())) kcal über Ziel"
    }

    // Dazwischen: die nächste offene Hauptmahlzeit nach der zuletzt eingetragenen, sonst die erste offene.
    let lastIndex = mains.lastIndex { $0.kcal > 0 } ?? -1
    let open = mains.dropFirst(lastIndex + 1).first { $0.kcal <= 0 } ?? mains.first { $0.kcal <= 0 }
    guard let next = open.map({ name($0.category) }) else {
      // Nur ein Snack eingetragen (keine Hauptmahlzeiten in der Liste).
      return "Eingetragen – weiter so!"
    }
    if loggedMains.isEmpty { return "Snack notiert – \(next) eintragen?" }
    if loggedMains.count == mains.count - 1 {
      if let remaining = kcalRemaining, remaining > 0 {
        return "Noch \(Int(remaining.rounded())) kcal – \(next) fehlt"
      }
      return "Fast komplett – \(next) fehlt noch"
    }
    if let streak, streak.isRunning { return "Tag \(streak.days) der Serie – \(next) steht an" }
    return "Guter Start – \(next) steht an"
  }

  /// Satz für einen Widget-Stand.
  public static func text(_ snapshot: WidgetSnapshot, hour: Int) -> String {
    guard let nutrition = snapshot.nutrition else { return "Mahlzeiten" }
    let meals = nutrition.meals ?? MealSplit.order.map { WidgetSnapshot.MealPart(category: $0, kcal: 0, target: nil) }
    return text(
      meals: meals, kcalRemaining: nutrition.kcalRemaining, kcalTarget: nutrition.kcalTarget,
      streak: snapshot.mealStreak, hour: hour)
  }
}
