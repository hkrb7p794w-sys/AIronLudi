import ActivityKit
import Foundation

/// Live-Aktivität „Mahlzeiten heute“: farbig und in voller Breite auf dem Sperrbildschirm – das können
/// Sperrbildschirm-Widgets nicht (iOS zeichnet sie einfarbig und höchstens halb so breit). Die Datei gehört zur App
/// und zur Widget-Erweiterung; deshalb ohne CoachCore und ohne Bindung an den MainActor.
nonisolated struct MealsActivityAttributes: ActivityAttributes {
  nonisolated struct ContentState: Codable, Hashable, Sendable {
    nonisolated struct Meal: Codable, Hashable, Sendable, Identifiable {
      /// Rohwert der Mahlzeit (`MealCategory`), auch für den Link zum Erfassen.
      var id: String
      var title: String
      var kcal: Int
      /// Anteil am Ziel der Mahlzeit; `nil` ohne Ziel.
      var fraction: Double?
    }

    var meals: [Meal]
    var streakDays: Int
    var streakActive: Bool
    /// Übrige Kalorien (negativ = darüber); `nil` ohne Ziel.
    var kcalRemaining: Int?
    /// Kopfzeile passend zum Stand des Tages (`MealHeadline`); fehlt in Aktivitäten älterer Versionen.
    var headline: String? = nil
  }

  /// iOS beendet eine Live-Aktivität nach etwa acht Stunden; die App startet sie beim Öffnen rechtzeitig neu.
  var startedAt: Date
}
