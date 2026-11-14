import ActivityKit
import SwiftUI
import WidgetKit

/// Live-Aktivität „Mahlzeiten heute“ im Stil der Widgets: Kopfzeile mit Serie, je Mahlzeit ein farbiger Ring mit
/// Emoji und „+“ bzw. Haken – farbig und in voller Breite auf dem Sperrbildschirm.
struct MealsLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: MealsActivityAttributes.self) { context in
      MealsActivityView(state: context.state, stale: context.isStale)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(Color.black.opacity(0.45))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
          MealsActivityView(state: context.state, stale: context.isStale)
        }
      } compactLeading: {
        HStack(spacing: 2) {
          Image(systemName: "flame.fill")
          Text("\(context.state.streakDays)").fontWeight(.heavy).monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(context.state.streakActive && !context.isStale ? Style.flame : Color.secondary)
      } compactTrailing: {
        Text("\(context.isStale ? 0 : context.state.meals.reduce(0) { $0 + $1.kcal })")
          .font(.caption.weight(.semibold)).monospacedDigit()
      } minimal: {
        Image(systemName: "fork.knife")
      }
    }
  }
}

private struct MealsActivityView: View {
  let state: MealsActivityAttributes.ContentState
  /// Nach Mitternacht: Der Stand ist von gestern, heute ist noch nichts eingetragen.
  let stale: Bool

  private var streak: WidgetSnapshot.Streak {
    WidgetSnapshot.Streak(days: state.streakDays, activeToday: state.streakActive && !stale)
  }

  /// Der Satz stammt vom letzten Stand der App. Nach Mitternacht gilt er nicht mehr: neuer Tag, noch leer.
  private var title: String {
    if stale { return state.streakDays >= 2 ? "Neuer Tag – Serie fortsetzen?" : "Neuer Tag – Frühstück eintragen?" }
    return state.headline ?? streak.headline
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      WidgetHeader(title: title, streak: streak)
      HStack(alignment: .top, spacing: 0) {
        ForEach(state.meals) { meal in
          let category = MealCategory(rawValue: meal.id)
          let kcal = stale ? 0 : meal.kcal
          if category == .snack, state.meals.count > 1 {
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 74)
          }
          Link(destination: category.map(AppRoute.logMealURL) ?? AppRoute.logMeal.url) {
            RingTile(
              emoji: MealsWidgetView.emoji(category ?? .other), fraction: stale ? 0 : meal.fraction,
              badge: kcal > 0 ? .check : .plus, title: meal.title, value: "\(kcal) kcal",
              active: kcal > 0, size: 48)
          }
          .accessibilityLabel("\(meal.title) eintragen, bisher \(kcal) kcal")
        }
      }
    }
    .foregroundStyle(.white)
  }
}
