import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CoachWidgetsBundle: WidgetBundle {
  var body: some Widget {
    WorkoutLiveActivity()
    MealsLiveActivity()
    TodayHomeWidget()
    NutritionHomeWidget()
    MealsHomeWidget()
    HealthHomeWidget()
    GymHomeWidget()
  }
}

/// Pause und nächster Satz auf dem Sperrbildschirm und in der Dynamic Island, mit „Satz erledigt“ zum Antippen –
/// ohne Entsperren mit verschwitzten Händen.
struct WorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
      LockScreenView(state: context.state, title: context.attributes.title)
        .padding()
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.exercise).font(.headline).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          RestTimer(end: context.state.restEndsAt).font(.title3.bold())
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 8) {
            Text(context.state.detail).font(.subheadline).foregroundStyle(.secondary)
            ActionButtons(state: context.state)
          }
        }
      } compactLeading: {
        Image(systemName: "dumbbell.fill")
      } compactTrailing: {
        RestTimer(end: context.state.restEndsAt).frame(maxWidth: 48)
      } minimal: {
        Image(systemName: "dumbbell.fill")
      }
    }
  }
}

/// Eine Live-Aktivität ist höchstens 160 Punkte hoch. Drei klar getrennte Zeilen: oben, was dran ist (Übung
/// ungekürzt, Satz, Pausenuhr), in der Mitte die Werte als zwei zusammenhängende Regler, unten die Aktion.
private struct LockScreenView: View {
  let state: WorkoutActivityAttributes.ContentState
  let title: String

  private var resting: Bool { state.restEndsAt.map { $0 > .now } ?? false }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        VStack(alignment: .leading, spacing: 1) {
          Text(state.allDone ? "Fertig" : resting ? "Pause – gleich" : "Jetzt")
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(resting ? Color.orange : Color.green)
          Text(state.exercise).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
          Text(state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 4)
        if resting {
          RestTimer(end: state.restEndsAt)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .frame(maxWidth: 96, alignment: .trailing)
            .accessibilityLabel("Pause")
        }
      }
      if !state.allDone, let weight = state.weight, let reps = state.reps {
        AdjustRow(weight: weight, reps: reps, weightStep: state.weightStep, repsStep: state.repsStep)
      }
      ActionButtons(state: state)
    }
  }
}

/// Gewicht und Wiederholungen des aktuellen Satzes – ändern, ohne das iPhone zu entsperren.
private struct AdjustRow: View {
  let weight: String
  let reps: String
  let weightStep: String?
  let repsStep: String?

  var body: some View {
    HStack(spacing: 10) {
      ValueStepper(
        value: weight, down: WeightDownIntent(), up: WeightUpIntent(),
        label: "Gewicht", step: weightStep ?? "einen Schritt")
      ValueStepper(
        value: reps, down: RepsDownIntent(), up: RepsUpIntent(),
        label: "Wiederholungen", step: repsStep ?? "1")
    }
  }
}

/// Ein Wert mit − und + in einer gemeinsamen Fläche, damit erkennbar ist, welche Knöpfe zu welchem Wert gehören.
private struct ValueStepper<Down: LiveActivityIntent, Up: LiveActivityIntent>: View {
  let value: String
  let down: Down
  let up: Up
  let label: String
  let step: String

  var body: some View {
    HStack(spacing: 0) {
      Button(intent: down) { symbol("minus") }
        .accessibilityLabel("\(label) um \(step) verringern")
      Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(label): \(value)")
      Button(intent: up) { symbol("plus") }
        .accessibilityLabel("\(label) um \(step) erhöhen")
    }
    .buttonStyle(.plain)
    .background(Color.white.opacity(0.12), in: Capsule())
  }

  private func symbol(_ name: String) -> some View {
    Image(systemName: name)
      .font(.body.weight(.bold))
      .frame(width: 40, height: 36)
      .contentShape(Rectangle())
  }
}

/// Restzeit der Pause; ohne Pause „Los“.
private struct RestTimer: View {
  let end: Date?

  var body: some View {
    if let end, end > .now {
      Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit().multilineTextAlignment(.trailing)
    } else {
      Text("Los").bold()
    }
  }
}

private struct ActionButtons: View {
  let state: WorkoutActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 10) {
      if !state.allDone {
        // Die eine Hauptaktion: gefüllt und über die ganze Breite.
        Button(intent: CompleteSetIntent()) {
          Label("Satz erledigt", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
      }
      if let end = state.restEndsAt, end > .now {
        Button(intent: SkipRestIntent()) {
          Label("Pause aus", systemImage: "forward.end.fill")
            .frame(maxWidth: state.allDone ? .infinity : nil, minHeight: 24)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .accessibilityLabel("Pause überspringen")
      }
    }
    .font(.subheadline.weight(.semibold))
  }
}
