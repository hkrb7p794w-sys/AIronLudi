import ActivityKit
import Flutter
import UIKit
import UserNotifications
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: Antippen, Aktionen und Anzeige im Vordergrund laufen über diesen Delegate.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WidgetBridge") {
      WidgetBridge.register(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ActivityBridge") {
      let messenger = registrar.messenger()
      MainActor.assumeIsolated { ActivityBridge.register(messenger: messenger) }
    }
  }
}

/// Kanal `aironludi/widgets`: gemeinsamer Speicher mit den Widgets (App Group). Die Gruppe ermittelt Dart aus dem
/// Provisioning-Profil (`AppGroupProfile`), hier nur Profil lesen, Ordner auflösen, Warteschlange koordiniert ändern
/// und Widgets neu laden (wie `WidgetStore` und `WidgetPublisher` der Swift-App).
enum WidgetBridge {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "aironludi/widgets", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "profile":
        let url = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        if let data = try? Data(contentsOf: url) {
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(nil)
        }
      case "containerPath":
        guard let group = arguments["group"] as? String else { return result(nil) }
        result(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.path)
      case "removeQueueEntries":
        guard let path = arguments["path"] as? String, let ids = arguments["ids"] as? [String] else {
          return result(FlutterError(code: "arguments", message: "path und ids fehlen", details: nil))
        }
        removeQueueEntries(at: URL(fileURLWithPath: path), ids: Set(ids))
        result(nil)
      case "reload":
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Lesen, ändern, schreiben unter Dateikoordination: Das Widget kann gleichzeitig Wasser eintragen.
  private static func removeQueueEntries(at url: URL, ids: Set<String>) {
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
      guard let data = try? Data(contentsOf: url),
        var queue = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let entries = queue["entries"] as? [[String: Any]]
      else { return }
      queue["entries"] = entries.filter { entry in !ids.contains(entry["id"] as? String ?? "") }
      if let changed = try? JSONSerialization.data(withJSONObject: queue) {
        try? changed.write(to: url, options: .atomic)
      }
    }
  }
}

/// Kanal `aironludi/activities`: Live-Aktivitäten der laufenden Einheit und „Mahlzeiten heute“ (Port von
/// `WorkoutActivityController` und `MealsActivityController`). Die Inhalte rechnet Dart; die Knöpfe der Live-Aktivität
/// (`WorkoutActions`, laufen im Prozess der App) gehen als `workoutAction` an Dart zurück.
@MainActor
enum ActivityBridge {
  private static var channel: FlutterMethodChannel?

  /// iOS beendet Live-Aktivitäten nach etwa acht Stunden. Beim Öffnen der App beginnt die Zeit deshalb neu, sobald
  /// die laufende Aktivität älter ist als das hier.
  static let restartAfter: TimeInterval = 2 * 3600

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "aironludi/activities", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      MainActor.assumeIsolated {
        switch call.method {
        case "updateWorkout":
          updateWorkout(arguments)
          result(nil)
        case "updateMeals":
          updateMeals(arguments)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    WorkoutActions.handler = { action in
      let arguments: [String: Any] =
        switch action {
        case .completeSet: ["action": "completeSet"]
        case .skipRest: ["action": "skipRest"]
        case .weight(let steps): ["action": "weight", "steps": steps]
        case .reps(let delta): ["action": "reps", "steps": delta]
        }
      self.channel?.invokeMethod("workoutAction", arguments: arguments)
    }
  }

  // MARK: Laufende Einheit

  private static func workoutState(_ values: [String: Any]) -> WorkoutActivityAttributes.ContentState? {
    guard let exercise = values["exercise"] as? String, let detail = values["detail"] as? String else { return nil }
    return WorkoutActivityAttributes.ContentState(
      exercise: exercise, detail: detail,
      restEndsAt: (values["restEndsAt"] as? Double).map(Date.init(timeIntervalSince1970:)),
      doneSets: values["doneSets"] as? Int ?? 0, allDone: values["allDone"] as? Bool ?? false,
      weight: values["weight"] as? String, reps: values["reps"] as? String,
      weightStep: values["weightStep"] as? String, repsStep: values["repsStep"] as? String,
      next: values["next"] as? String)
  }

  /// Nach jeder Änderung der Einheit; ohne Stand (keine Einheit, ausgeschaltet) endet die Aktivität.
  private static func updateWorkout(_ arguments: [String: Any]) {
    let running = Activity<WorkoutActivityAttributes>.activities
    guard let state = (arguments["state"] as? [String: Any]).flatMap(workoutState) else {
      for activity in running {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
      }
      return
    }
    let content = ActivityContent(state: state, staleDate: nil)
    if let activity = running.first {
      Task { await activity.update(content) }
    } else if ActivityAuthorizationInfo().areActivitiesEnabled {
      let title = arguments["title"] as? String ?? ""
      _ = try? Activity.request(attributes: WorkoutActivityAttributes(title: title), content: content)
    }
  }

  // MARK: Mahlzeiten heute

  private static func mealsState(_ values: [String: Any]) -> MealsActivityAttributes.ContentState? {
    guard let meals = values["meals"] as? [[String: Any]] else { return nil }
    return MealsActivityAttributes.ContentState(
      meals: meals.compactMap { meal in
        guard let id = meal["id"] as? String, let title = meal["title"] as? String else { return nil }
        return .init(id: id, title: title, kcal: meal["kcal"] as? Int ?? 0, fraction: meal["fraction"] as? Double)
      },
      streakDays: values["streakDays"] as? Int ?? 0, streakActive: values["streakActive"] as? Bool ?? false,
      kcalRemaining: values["kcalRemaining"] as? Int, headline: values["headline"] as? String)
  }

  /// Nach jedem neuen Widget-Stand. Starten darf iOS nur, solange die App sichtbar ist; im Hintergrund wird eine
  /// laufende Aktivität nur aktualisiert.
  private static func updateMeals(_ arguments: [String: Any]) {
    let now = (arguments["now"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
    let running = Activity<MealsActivityAttributes>.activities.filter {
      $0.activityState == .active || $0.activityState == .stale
    }
    guard let state = (arguments["state"] as? [String: Any]).flatMap(mealsState) else {
      for activity in running {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
      }
      return
    }
    // Ab Mitternacht gilt der Stand als veraltet; die Anzeige zeigt dann einen leeren Tag.
    let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 3600)
    let content = ActivityContent(state: state, staleDate: midnight)
    let canStart =
      UIApplication.shared.applicationState != .background && ActivityAuthorizationInfo().areActivitiesEnabled
    if let activity = running.first {
      guard canStart, now.timeIntervalSince(activity.attributes.startedAt) > restartAfter else {
        Task { await activity.update(content) }
        return
      }
      for old in running {
        Task { await old.end(nil, dismissalPolicy: .immediate) }
      }
    }
    guard canStart else { return }
    _ = try? Activity.request(attributes: MealsActivityAttributes(startedAt: now), content: content)
  }
}
