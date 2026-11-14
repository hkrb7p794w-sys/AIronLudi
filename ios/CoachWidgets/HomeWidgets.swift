import AppIntents
import SwiftUI
import WidgetKit

// Homescreen- und Sperrbildschirm-Widgets. Sie lesen nur den Stand, den die App in die App Group schreibt
// (`WidgetStore`); interaktiv ist allein „+250 ml Wasser“ (Warteschlange, die App übernimmt beim Öffnen).
// Diese Erweiterung läuft ohne MainActor-Voreinstellung (project.yml), damit `@Parameter` in den
// Konfigurations-Intents geht.

// MARK: - Zeitleiste

struct HomeEntry<Config: Sendable>: TimelineEntry {
  let date: Date
  /// `nil`: noch kein Stand (App nie geöffnet oder keine App Group).
  let display: WidgetSnapshot.Display?
  let config: Config
}

enum HomeTimeline {
  /// Jetzt und ab Mitternacht (neuer Tag ohne Mahlzeiten und Plan); danach liest das Widget neu.
  static func entries<Config: Sendable>(config: Config, now: Date = .now) -> Timeline<HomeEntry<Config>> {
    let snapshot = WidgetStore.loadSnapshot()
    let queue = WidgetStore.loadQueue()
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    let midnight = tomorrow.addingTimeInterval(60)
    let entries = [now, midnight].map { date in
      HomeEntry(
        date: date, display: snapshot?.display(on: CalendarDay(date: date), queue: queue), config: config)
    }
    return Timeline(entries: entries, policy: .atEnd)
  }

  static func preview<Config: Sendable>(config: Config) -> HomeEntry<Config> {
    HomeEntry(date: .now, display: SampleSnapshot.value.display(on: SampleSnapshot.value.day), config: config)
  }
}

struct ConfiguredHomeProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> HomeEntry<Intent> { HomeTimeline.preview(config: Intent()) }

  func snapshot(for configuration: Intent, in context: Context) async -> HomeEntry<Intent> {
    context.isPreview
      ? HomeTimeline.preview(config: configuration) : HomeTimeline.entries(config: configuration).entries[0]
  }

  func timeline(for configuration: Intent, in context: Context) async -> Timeline<HomeEntry<Intent>> {
    HomeTimeline.entries(config: configuration)
  }
}

// MARK: - Konfiguration

struct TodayWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Heute"

  @Parameter(title: "Kalorien zeigen", default: true) var showsNutrition: Bool
  @Parameter(title: "Body Battery zeigen", default: true) var showsBodyBattery: Bool

  init() {}
}

enum NutritionWidgetDisplay: String, AppEnum {
  case remaining, eaten, protein, lastMeal

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Anzeige"
  static let caseDisplayRepresentations: [NutritionWidgetDisplay: DisplayRepresentation] = [
    .remaining: "Verbleibende Kalorien",
    .eaten: "Tageskalorien",
    .protein: "Protein",
    .lastMeal: "Letzte Mahlzeit",
  ]
}

struct NutritionWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Ernährung"

  @Parameter(title: "Anzeige", default: .remaining) var display: NutritionWidgetDisplay

  init() {}
}

struct MealsWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Mahlzeiten"

  init() {}
}

enum HealthWidgetMetric: String, AppEnum {
  case bodyBattery, sleep, hrv, recovery, restingHeartRate, stress

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wert"
  static let caseDisplayRepresentations: [HealthWidgetMetric: DisplayRepresentation] = [
    .bodyBattery: "Body Battery",
    .sleep: "Schlaf",
    .hrv: "HRV",
    .recovery: "Recovery",
    .restingHeartRate: "Ruhepuls",
    .stress: "Stress",
  ]

  var metric: HealthMetric { HealthMetric(rawValue: rawValue) ?? .bodyBattery }
}

struct HealthWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Health"

  @Parameter(title: "Wert", default: .bodyBattery) var metric: HealthWidgetMetric

  init() {}
}

enum GymWidgetFocus: String, AppEnum {
  case next, last, week

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Anzeige"
  static let caseDisplayRepresentations: [GymWidgetFocus: DisplayRepresentation] = [
    .next: "Nächstes Training",
    .last: "Letzte Einheit",
    .week: "Wochenfortschritt",
  ]
}

struct GymWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Gym"

  @Parameter(title: "Anzeige", default: .next) var focus: GymWidgetFocus

  init() {}
}

/// Einziger interaktiver Knopf: 250 ml Wasser vormerken. Läuft in der Erweiterung; die App übernimmt den Eintrag
/// beim nächsten Öffnen, das Widget zählt ihn sofort mit.
struct AddWaterIntent: AppIntent {
  static let title: LocalizedStringResource = "250 ml Wasser"
  static let isDiscoverable = false

  init() {}

  func perform() async throws -> some IntentResult {
    WidgetStore.updateQueue { $0.addWater(250, at: .now) }
    return .result()
  }
}

// MARK: - Widgets

struct TodayHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.today, intent: TodayWidgetIntent.self,
      provider: ConfiguredHomeProvider<TodayWidgetIntent>()
    ) { entry in
      TodayWidgetView(
        display: entry.display, showsNutrition: entry.config.showsNutrition,
        showsBodyBattery: entry.config.showsBodyBattery
      )
      .widgetURL(AppRoute.today.url)
      .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Heute")
    .description("Tagesampel, nächste Einheit, Kalorien und Body Battery.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct NutritionHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.nutrition, intent: NutritionWidgetIntent.self,
      provider: ConfiguredHomeProvider<NutritionWidgetIntent>()
    ) { entry in
      NutritionWidgetView(display: entry.display, choice: entry.config.display)
        .widgetURL(AppRoute.nutrition.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Ernährung")
    .description("Kalorien, Protein oder letzte Mahlzeit – mittelgroß mit Wasser-Knopf.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

/// Mahlzeiten wie bei gängigen Ernährungs-Apps: je Mahlzeit ein Ring (gegessen gegen Richtwert) und „+“, das die App
/// direkt beim Erfassen dieser Mahlzeit öffnet. Auf dem Sperrbildschirm kompakt (Tippen öffnet das Erfassen).
struct MealsHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.meals, intent: MealsWidgetIntent.self,
      provider: ConfiguredHomeProvider<MealsWidgetIntent>()
    ) { entry in
      MealsWidgetView(display: entry.display)
        .widgetURL(AppRoute.logMeal.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Mahlzeiten")
    .description("Kalorien je Mahlzeit mit „+“ zum Eintragen – auch für den Sperrbildschirm.")
    .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryCircular])
  }
}

struct HealthHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.health, intent: HealthWidgetIntent.self,
      provider: ConfiguredHomeProvider<HealthWidgetIntent>()
    ) { entry in
      HealthWidgetView(display: entry.display, metric: entry.config.metric.metric)
        .widgetURL(AppRoute.health.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Health")
    .description("Body Battery, Schlaf, HRV, Recovery, Ruhepuls oder Stress der letzten Nacht.")
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

struct GymHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.gym, intent: GymWidgetIntent.self, provider: ConfiguredHomeProvider<GymWidgetIntent>()
    ) { entry in
      GymWidgetView(display: entry.display, focus: entry.config.focus)
        .widgetURL(AppRoute.gym.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Gym")
    .description("Nächstes Training, letzte Einheit oder Wochenfortschritt.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

// MARK: - Ansichten

/// Ohne Stand: kurz erklären statt leerer Zahlen.
private struct NoDataView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: "arrow.up.forward.app").font(.title3)
      Text(WidgetStore.isAvailable ? "AIronLudi einmal öffnen" : "Widget-Daten nicht verfügbar")
        .font(.caption.bold())
      if !WidgetStore.isAvailable {
        Text("Die App-Gruppe fehlt (Installation über SideStore prüfen).").font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

enum Style {
  static func color(_ level: RecoveryLevel?) -> Color {
    switch level {
    case .normal?: .green
    case .locker?: .orange
    case .pause?: .red
    case nil: .gray
    }
  }

  static func color(_ status: MorningReport.Status) -> Color {
    switch status {
    case .good: .green
    case .normal: .blue
    case .attention: .orange
    case .missing: .gray
    }
  }

  static func label(_ status: MorningReport.Status) -> String {
    switch status {
    case .good: "gut"
    case .normal: "üblich"
    case .attention: "auffällig"
    case .missing: "fehlt"
    }
  }

  /// Farbe der Ringe und Plaketten.
  static let accent = Color.blue
  /// Flamme der Serie.
  static let flame = Color(red: 1, green: 0.27, blue: 0.23)

  static func kcal(_ value: Double) -> String { "\(Int(value.rounded()))" }
  static func grams(_ value: Double) -> String { "\(Int(value.rounded())) g" }
  static func liters(_ milliliters: Double) -> String { "\(GermanFormat.decimal(milliliters / 1_000)) l" }
}

// MARK: - Bausteine im gemeinsamen Stil

/// Kopfzeile aller Widgets: kurzer Satz links, Serie mit Flamme rechts.
struct WidgetHeader: View {
  let title: String
  let streak: WidgetSnapshot.Streak?
  var dot: Color?

  var body: some View {
    HStack(spacing: 6) {
      if let dot { Circle().fill(dot).frame(width: 9, height: 9) }
      Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.65)
      Spacer(minLength: 4)
      if let streak, streak.days > 0 {
        HStack(spacing: 3) {
          Image(systemName: "flame.fill")
          Text("\(streak.days)").fontWeight(.heavy).monospacedDigit()
        }
        .font(.subheadline)
        .foregroundStyle(streak.activeToday ? Style.flame : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Serie: \(streak.days) Tage")
      }
    }
  }
}

/// Kachel: Fortschrittsring mit Symbol in der Mitte, Plakette unten rechts, darunter Titel und Wert.
struct RingTile: View {
  enum Badge { case hidden, plus, check, play }

  var emoji: String?
  var symbol: String?
  var fraction: Double?
  var badge: Badge = .hidden
  let title: String
  let value: String
  /// Ausgegraut, solange nichts erfasst ist.
  var active = true
  var tint: Color = Style.accent
  var size: CGFloat = 46

  private var badgeSymbol: String {
    switch badge {
    case .plus: "plus"
    case .check: "checkmark"
    case .play: "play.fill"
    case .hidden: ""
    }
  }

  var body: some View {
    VStack(spacing: 3) {
      ZStack(alignment: .bottomTrailing) {
        ZStack {
          Circle().stroke(Color.primary.opacity(0.12), lineWidth: size * 0.11)
          Circle().trim(from: 0, to: min(max(fraction ?? 0, 0), 1))
            .stroke(tint, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
            .rotationEffect(.degrees(-90))
          if let emoji {
            Text(emoji).font(.system(size: size * 0.42))
          } else if let symbol {
            Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold))
          }
        }
        .frame(width: size, height: size)
        if badge != .hidden {
          Image(systemName: badgeSymbol)
            .font(.system(size: size * 0.2, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size * 0.4, height: size * 0.4)
            .background(Style.accent, in: Circle())
            .offset(x: size * 0.1, y: size * 0.1)
        }
      }
      Text(title).font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(active ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
      Text(value).font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(active ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title): \(value)")
  }
}

// MARK: - Bausteine für den Sperrbildschirm (einfarbig)

/// Kopfzeile auf dem Sperrbildschirm: kurzer Text links, Serie mit Flamme rechts.
private struct LockHeader: View {
  let title: String
  let streak: WidgetSnapshot.Streak?

  var body: some View {
    HStack(spacing: 2) {
      Text(title).lineLimit(1).minimumScaleFactor(0.7)
      Spacer(minLength: 2)
      if let streak, streak.days > 0 {
        Image(systemName: streak.activeToday ? "flame.fill" : "flame")
        Text("\(streak.days)").fontWeight(.heavy).monospacedDigit()
      }
    }
    .font(.system(size: 10, weight: .semibold))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(streak.map { "\(title), Serie: \($0.days) Tage" } ?? title)
  }
}

/// Ring mit Symbol und optionaler Plakette; iOS zeichnet ihn auf dem Sperrbildschirm einfarbig.
private struct LockRing: View {
  let symbol: String
  var fraction: Double?
  /// SF-Symbol der Plakette unten rechts, z. B. `plus.circle.fill`.
  var badge: String?
  var size: CGFloat = 28

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      ZStack {
        Circle().stroke(Color.primary.opacity(0.25), lineWidth: size * 0.11)
        Circle().trim(from: 0, to: min(max(fraction ?? 0, 0), 1))
          .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Image(systemName: symbol).font(.system(size: size * 0.4, weight: .semibold))
      }
      .frame(width: size, height: size)
      if let badge {
        Image(systemName: badge).font(.system(size: size * 0.4, weight: .bold))
          .offset(x: size * 0.14, y: size * 0.1)
      }
    }
  }
}

/// Kachel auf dem Sperrbildschirm: Ring, darunter Titel und Wert.
private struct LockTile: View {
  let symbol: String
  var fraction: Double?
  var badge: String?
  let title: String
  let value: String
  var active = true

  var body: some View {
    VStack(spacing: 1) {
      LockRing(symbol: symbol, fraction: fraction, badge: badge)
      Text(title).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
      Text(value).font(.system(size: 9)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity)
    .opacity(active ? 1 : 0.75)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title): \(value)")
  }
}

/// Rundes Sperrbildschirm-Widget: Ring über die ganze Fläche, innen Symbol und Wert.
private struct LockCircle: View {
  let symbol: String
  var fraction: Double?
  let value: String

  var body: some View {
    ZStack {
      Circle().stroke(Color.primary.opacity(0.25), lineWidth: 5)
      Circle().trim(from: 0, to: min(max(fraction ?? 0, 0), 1))
        .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        .rotationEffect(.degrees(-90))
      VStack(spacing: 0) {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        Text(value).font(.system(size: 14, weight: .bold)).monospacedDigit().lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .padding(.horizontal, 8)
    }
    .padding(2.5)
    .widgetAccentable()
  }
}

/// Rechteckiges Sperrbildschirm-Widget mit einem Ring links und drei Zeilen rechts.
private struct LockRow: View {
  let symbol: String
  var fraction: Double?
  var badge: String?
  let title: String
  let value: String
  let detail: String
  let streak: WidgetSnapshot.Streak?

  var body: some View {
    VStack(spacing: 3) {
      LockHeader(title: title, streak: streak)
      HStack(spacing: 8) {
        LockRing(symbol: symbol, fraction: fraction, badge: badge, size: 34)
        VStack(alignment: .leading, spacing: 0) {
          Text(value).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
          Text(detail).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
        }
        Spacer(minLength: 0)
      }
    }
    .widgetAccentable()
  }
}

struct TodayWidgetView: View {
  let display: WidgetSnapshot.Display?
  let showsNutrition: Bool
  let showsBodyBattery: Bool
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let snapshot = display?.snapshot {
      let today = snapshot.today
      VStack(alignment: .leading, spacing: 8) {
        WidgetHeader(
          title: family == .systemSmall ? "Heute" : today.headline, streak: snapshot.streak,
          dot: Style.color(today.level))
        if family == .systemSmall {
          Text(today.headline).font(.footnote.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
          Spacer(minLength: 0)
          HStack(alignment: .top, spacing: 0) {
            trainingTile(today, size: 40)
            if showsNutrition, let nutrition = snapshot.nutrition, let remaining = nutrition.kcalRemaining {
              RingTile(
                emoji: "🍽️", fraction: nutrition.kcalFraction, title: "Kalorien",
                value: "\(Style.kcal(remaining)) übrig", size: 40)
            }
          }
        } else {
          Spacer(minLength: 0)
          HStack(alignment: .top, spacing: 0) {
            trainingTile(today, size: 46)
            if showsNutrition, let nutrition = snapshot.nutrition, let remaining = nutrition.kcalRemaining {
              RingTile(
                emoji: "🍽️", fraction: nutrition.kcalFraction, title: "Kalorien",
                value: "\(Style.kcal(remaining)) übrig")
            }
            if showsBodyBattery, !(display?.healthIsOld ?? true), let battery = snapshot.health(.bodyBattery),
              let value = battery.value
            {
              RingTile(
                symbol: "bolt.fill", fraction: battery.gauge.map { $0 / 100 }, title: "Battery", value: value,
                tint: Style.color(battery.status))
            }
            if let week = today.week {
              RingTile(
                symbol: "calendar", fraction: today.weekFraction, title: "Woche",
                value: String(week.split(separator: "·").first ?? "").trimmingCharacters(in: .whitespaces))
            }
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      NoDataView()
    }
  }

  /// Nächste Einheit mit Anteil der erledigten Einheiten des Tages.
  private func trainingTile(_ today: WidgetSnapshot.Today, size: CGFloat) -> some View {
    let done = today.sessions.filter(\.done).count
    let total = today.sessions.count
    let next = today.nextSession
    return RingTile(
      symbol: next?.symbol ?? (total > 0 ? "checkmark" : "moon.zzz.fill"),
      fraction: total > 0 ? Double(done) / Double(total) : nil,
      badge: total > 0 && next == nil ? .check : .hidden, title: "Training",
      value: next?.title ?? (total > 0 ? "erledigt" : "frei"), active: total > 0, size: size)
  }
}

struct MealsWidgetView: View {
  let display: WidgetSnapshot.Display?
  @Environment(\.widgetFamily) private var family

  private static func symbol(_ category: MealCategory) -> String {
    switch category {
    case .breakfast: "cup.and.saucer.fill"
    case .lunch: "fork.knife"
    case .dinner: "moon.stars.fill"
    case .snack, .other: "carrot.fill"
    }
  }

  static func emoji(_ category: MealCategory) -> String {
    switch category {
    case .breakfast: "☕️"
    case .lunch: "🍲"
    case .dinner: "🥗"
    case .snack, .other: "🍎"
    }
  }

  private static func short(_ category: MealCategory) -> String {
    switch category {
    case .breakfast: "Früh"
    case .lunch: "Mittag"
    case .dinner: "Abend"
    case .snack, .other: "Snack"
    }
  }

  var body: some View {
    if let snapshot = display?.snapshot, let nutrition = snapshot.nutrition {
      let parts =
        nutrition.meals ?? MealSplit.order.map { WidgetSnapshot.MealPart(category: $0, kcal: 0, target: nil) }
      switch family {
      case .accessoryRectangular: rectangular(parts, streak: snapshot.mealStreak)
      case .accessoryCircular: circular(nutrition)
      default:
        medium(
          parts, title: MealHeadline.text(snapshot, hour: Calendar.current.component(.hour, from: .now)),
          streak: snapshot.mealStreak)
      }
    } else {
      NoDataView()
    }
  }

  /// Je Mahlzeit ein Ring mit „+“ (oder Haken, sobald etwas eingetragen ist); Tippen öffnet das Erfassen dieser
  /// Mahlzeit. Snacks stehen abgesetzt rechts.
  private func medium(
    _ parts: [WidgetSnapshot.MealPart], title: String, streak: WidgetSnapshot.Streak?
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      WidgetHeader(title: title, streak: streak)
      Spacer(minLength: 0)
      HStack(alignment: .top, spacing: 0) {
        ForEach(parts) { part in
          if part.category == .snack, parts.count > 1 {
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 70)
          }
          Link(destination: AppRoute.logMealURL(part.category)) {
            RingTile(
              emoji: Self.emoji(part.category), fraction: part.fraction, badge: part.kcal > 0 ? .check : .plus,
              title: part.category.label, value: "\(Style.kcal(part.kcal)) kcal", active: part.kcal > 0)
          }
          .accessibilityLabel("\(part.category.label) eintragen, bisher \(Style.kcal(part.kcal)) kcal")
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// Sperrbildschirm im selben Aufbau wie auf dem Homescreen: Serie oben, je Mahlzeit ein Ring mit Symbol und „+“
  /// bzw. Haken. iOS zeichnet Sperrbildschirm-Widgets einfarbig, deshalb Symbole statt farbiger Emojis. Tippen
  /// öffnet das Erfassen.
  private func rectangular(_ parts: [WidgetSnapshot.MealPart], streak: WidgetSnapshot.Streak?) -> some View {
    VStack(spacing: 2) {
      if let streak, streak.days > 0 {
        LockHeader(
          title: streak.isRunning ? "Weiter so!" : streak.activeToday ? "Guter Start" : "Heute eintragen",
          streak: streak)
      }
      HStack(alignment: .top, spacing: 0) {
        ForEach(parts) { part in
          LockTile(
            symbol: Self.symbol(part.category), fraction: part.fraction,
            badge: part.kcal > 0 ? "checkmark.circle.fill" : "plus.circle.fill", title: Self.short(part.category),
            value: Style.kcal(part.kcal), active: part.kcal > 0)
        }
      }
    }
    .widgetAccentable()
  }

  private func circular(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
    LockCircle(
      symbol: "plus", fraction: nutrition.kcalFraction, value: Style.kcal(nutrition.kcalRemaining ?? nutrition.kcal))
  }
}

struct NutritionWidgetView: View {
  let display: WidgetSnapshot.Display?
  let choice: NutritionWidgetDisplay
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let snapshot = display?.snapshot, let nutrition = snapshot.nutrition {
      switch family {
      case .accessoryCircular: circular(nutrition)
      case .accessoryRectangular: rectangular(nutrition, streak: snapshot.mealStreak)
      case .accessoryInline: Text(headline(nutrition))
      case .systemMedium: medium(nutrition, streak: snapshot.mealStreak)
      default: small(nutrition, streak: snapshot.mealStreak)
      }
    } else {
      NoDataView()
    }
  }

  private func headline(_ nutrition: WidgetSnapshot.Nutrition) -> String {
    switch choice {
    case .remaining:
      nutrition.kcalRemaining.map { $0 >= 0 ? "\(Style.kcal($0)) kcal übrig" : "\(Style.kcal(-$0)) kcal drüber" }
        ?? "\(Style.kcal(nutrition.kcal)) kcal"
    case .eaten:
      nutrition.kcalTarget.map { "\(Style.kcal(nutrition.kcal)) / \(Style.kcal($0)) kcal" }
        ?? "\(Style.kcal(nutrition.kcal)) kcal"
    case .protein:
      nutrition.proteinTarget.map { "Protein \(Style.grams(nutrition.protein)) / \(Style.grams($0))" }
        ?? "Protein \(Style.grams(nutrition.protein))"
    case .lastMeal:
      nutrition.lastMeal.map { "\($0.title) · \($0.at.formatted(date: .omitted, time: .shortened))" }
        ?? "Noch keine Mahlzeit"
    }
  }

  private func fraction(_ nutrition: WidgetSnapshot.Nutrition) -> Double? {
    choice == .protein ? nutrition.proteinFraction : nutrition.kcalFraction
  }

  /// Ein großer Ring für den gewählten Wert.
  private func small(_ nutrition: WidgetSnapshot.Nutrition, streak: WidgetSnapshot.Streak?) -> some View {
    VStack(spacing: 6) {
      WidgetHeader(title: "Ernährung", streak: streak)
      Spacer(minLength: 0)
      if choice == .lastMeal, let meal = nutrition.lastMeal {
        RingTile(
          emoji: "🍽️", fraction: nutrition.kcalFraction, badge: .check, title: meal.title,
          value: "\(meal.at.formatted(date: .omitted, time: .shortened)) · \(Style.kcal(meal.kcal)) kcal", size: 64)
      } else {
        RingTile(
          emoji: choice == .protein ? "💪" : "🍽️", fraction: fraction(nutrition),
          title: choice == .protein ? "Protein" : "Kalorien", value: headline(nutrition),
          active: nutrition.kcal > 0, size: 64)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  /// Kalorien, Protein, Wasser (Tippen: +250 ml) und Erfassen.
  private func medium(_ nutrition: WidgetSnapshot.Nutrition, streak: WidgetSnapshot.Streak?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      WidgetHeader(title: headline(nutrition), streak: streak)
      Spacer(minLength: 0)
      HStack(alignment: .top, spacing: 0) {
        RingTile(
          emoji: "🍽️", fraction: nutrition.kcalFraction, title: "Kalorien", value: "\(Style.kcal(nutrition.kcal)) kcal",
          active: nutrition.kcal > 0)
        RingTile(
          emoji: "💪", fraction: nutrition.proteinFraction, title: "Protein", value: Style.grams(nutrition.protein),
          active: nutrition.protein > 0)
        if WidgetStore.isAvailable {
          Button(intent: AddWaterIntent()) { waterTile(nutrition, badge: .plus) }
            .buttonStyle(.plain)
            .accessibilityLabel("250 Milliliter Wasser eintragen")
        } else {
          waterTile(nutrition, badge: .hidden)
        }
        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 70)
        Link(destination: AppRoute.logMeal.url) {
          RingTile(symbol: "camera.fill", badge: .plus, title: "Erfassen", value: "Foto, Text")
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func waterTile(_ nutrition: WidgetSnapshot.Nutrition, badge: RingTile.Badge) -> some View {
    RingTile(
      emoji: "💧", fraction: nutrition.waterFraction, badge: badge, title: "Wasser",
      value: Style.liters(nutrition.waterMilliliters), active: nutrition.waterMilliliters > 0)
  }

  private func circular(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
    LockCircle(
      symbol: choice == .protein ? "bolt.fill" : "fork.knife", fraction: fraction(nutrition),
      value: choice == .protein
        ? "\(Int(nutrition.protein.rounded()))" : Style.kcal(nutrition.kcalRemaining ?? nutrition.kcal))
  }

  /// Kalorien, Protein und Wasser als Ringe, darüber der gewählte Wert und die Serie.
  private func rectangular(_ nutrition: WidgetSnapshot.Nutrition, streak: WidgetSnapshot.Streak?) -> some View {
    VStack(spacing: 2) {
      LockHeader(title: headline(nutrition), streak: streak)
      HStack(alignment: .top, spacing: 0) {
        LockTile(
          symbol: "fork.knife", fraction: nutrition.kcalFraction, title: "kcal", value: Style.kcal(nutrition.kcal),
          active: nutrition.kcal > 0)
        LockTile(
          symbol: "bolt.fill", fraction: nutrition.proteinFraction, title: "Protein",
          value: Style.grams(nutrition.protein), active: nutrition.protein > 0)
        LockTile(
          symbol: "drop.fill", fraction: nutrition.waterFraction, title: "Wasser",
          value: Style.liters(nutrition.waterMilliliters), active: nutrition.waterMilliliters > 0)
      }
    }
    .widgetAccentable()
  }
}

struct HealthWidgetView: View {
  let display: WidgetSnapshot.Display?
  let metric: HealthMetric
  @Environment(\.widgetFamily) private var family

  private static func ringFraction(_ health: WidgetSnapshot.Health?) -> Double {
    guard let gauge = health?.gauge else { return 1 }
    return gauge / 100
  }

  var body: some View {
    if let display {
      let health = display.snapshot.health(metric)
      let value = display.healthIsOld ? nil : health?.value
      // Ring nach Wert (Body Battery) bzw. ganz gefüllt; ohne Wert leer.
      let ring: Double? = value == nil ? nil : Self.ringFraction(health)
      switch family {
      case .accessoryCircular:
        LockCircle(symbol: metric.symbol, fraction: ring, value: value ?? "–")
      case .accessoryRectangular:
        LockRow(
          symbol: metric.symbol, fraction: ring, title: metric.title, value: value ?? "–",
          detail: value == nil ? "kein Wert" : (health.map { Style.label($0.status) } ?? "fehlt"),
          streak: display.snapshot.streak)
      case .accessoryInline:
        Text("\(metric.title) \(value ?? "–")")
      default:
        // Ring in der Farbe der Einordnung; gefüllt nach Wert (Body Battery) bzw. ganz.
        VStack(spacing: 6) {
          WidgetHeader(title: metric.title, streak: display.snapshot.streak)
          Spacer(minLength: 0)
          if let health, let value {
            RingTile(
              symbol: metric.symbol, fraction: health.gauge.map { $0 / 100 } ?? 1, title: value,
              value: Style.label(health.status), tint: Style.color(health.status), size: 64)
          } else {
            RingTile(
              symbol: metric.symbol, fraction: nil, title: "–",
              value: display.healthIsOld ? "noch kein Wert" : "kein Wert", active: false, size: 64)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
    } else {
      NoDataView()
    }
  }
}

struct GymWidgetView: View {
  let display: WidgetSnapshot.Display?
  let focus: GymWidgetFocus
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let snapshot = display?.snapshot, let gym = snapshot.gym {
      switch family {
      case .accessoryRectangular:
        LockRow(
          symbol: "dumbbell.fill", fraction: Self.weekFraction(gym), badge: "play.circle.fill",
          title: gym.running ? "Training läuft" : "Gym", value: gym.runningTitle ?? gym.next ?? "Kein Plan",
          detail: gym.weekText, streak: snapshot.streak)
      case .systemMedium:
        VStack(alignment: .leading, spacing: 8) {
          WidgetHeader(title: gym.running ? "Training läuft" : "Gym", streak: snapshot.streak)
          Spacer(minLength: 0)
          HStack(alignment: .top, spacing: 0) {
            Link(destination: AppRoute.startWorkout.url) { tile(.next, gym, size: 46) }
            tile(.last, gym, size: 46)
            tile(.week, gym, size: 46)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      default:
        VStack(spacing: 6) {
          WidgetHeader(title: "Gym", streak: snapshot.streak)
          Spacer(minLength: 0)
          tile(gym.running ? .next : focus, gym, size: 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
    } else if display != nil {
      VStack(alignment: .leading, spacing: 4) {
        Image(systemName: "dumbbell")
        Text("Kein Krafttraining im Profil").font(.caption)
      }
    } else {
      NoDataView()
    }
  }

  /// Anteil der geplanten Krafteinheiten dieser Woche.
  private static func weekFraction(_ gym: WidgetSnapshot.Gym) -> Double? {
    guard let planned = gym.weekPlanned, planned > 0 else { return nil }
    return min(Double(gym.weekDone) / Double(planned), 1)
  }

  private func tile(_ focus: GymWidgetFocus, _ gym: WidgetSnapshot.Gym, size: CGFloat) -> some View {
    switch focus {
    case .next:
      return RingTile(
        symbol: "dumbbell.fill", fraction: gym.running ? 1 : nil, badge: .play,
        title: gym.runningTitle ?? gym.next ?? "Kein Plan",
        value: gym.running ? "läuft" : (gym.nextDetail ?? "starten"), size: size)
    case .last:
      if let last = gym.last {
        return RingTile(
          symbol: "clock.arrow.circlepath", fraction: 1, badge: .check, title: last.title,
          value: "\(GermanFormat.date(last.day).prefix(6)) · \(last.sets) Sätze", size: size)
      }
      return RingTile(
        symbol: "clock.arrow.circlepath", fraction: nil, title: "Letzte", value: "noch keine", active: false,
        size: size)
    case .week:
      var fraction: Double?
      if let planned = gym.weekPlanned, planned > 0 { fraction = min(Double(gym.weekDone) / Double(planned), 1) }
      return RingTile(
        symbol: "calendar", fraction: fraction, badge: fraction == 1 ? .check : .hidden, title: "Woche",
        value: gym.weekText, size: size)
    }
  }
}

// MARK: - Vorschau in der Widget-Galerie

enum SampleSnapshot {
  static let value = WidgetSnapshot(
    createdAt: .now, day: CalendarDay(date: .now),
    today: .init(
      level: .normal, headline: "Normal trainieren",
      sessions: [.init(title: "Push", target: "6 Übungen", done: false, symbol: "dumbbell")],
      week: "2/4 Einheiten · 95 min", weekFraction: 0.5),
    nutrition: .init(
      kcal: 1_450, kcalTarget: 2_400, protein: 95, proteinTarget: 150, waterMilliliters: 1_250, waterTarget: 2_500,
      lastMeal: .init(title: "Mittagessen", at: .now, kcal: 680),
      meals: [
        .init(category: .breakfast, kcal: 520, target: 600), .init(category: .lunch, kcal: 680, target: 840),
        .init(category: .dinner, kcal: 0, target: 720), .init(category: .snack, kcal: 250, target: 240),
      ]),
    gym: .init(
      next: "Push", nextDetail: "6 Übungen · ca. 55 min", running: false, runningTitle: nil,
      last: .init(title: "Pull", day: CalendarDay(date: .now).adding(days: -2), sets: 18, volumeKg: 7_400),
      weekDone: 1, weekPlanned: 3),
    health: [
      .init(metric: .bodyBattery, value: "72", gauge: 72, status: .normal, note: "Im üblichen Bereich"),
      .init(metric: .sleep, value: "7,4 h", gauge: nil, status: .good, note: "Über deinem Bedarf"),
      .init(metric: .hrv, value: "58 ms", gauge: nil, status: .normal, note: "Im Bereich der Baseline"),
    ]
  ).withStreak()
}

extension WidgetSnapshot {
  /// Beispiel-Serie für die Vorschau in der Widget-Galerie.
  fileprivate func withStreak() -> WidgetSnapshot {
    var copy = self
    copy.streak = Streak(days: 34, activeToday: true)
    copy.mealStreak = Streak(days: 34, activeToday: true)
    return copy
  }
}
