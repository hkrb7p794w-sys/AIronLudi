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
