import Foundation

/// Gemeinsamer Speicher von App und Widgets in der App Group. Die tatsächliche Gruppe steht im Provisioning-Profil
/// (SideStore hängt die Team-ID an); ohne Gruppe liefern alle Zugriffe `nil` und die Widgets bitten ums Öffnen.
nonisolated enum WidgetStore {
  static let groupIdentifier: String? = {
    let profile = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
    let groups = (try? Data(contentsOf: profile)).map(AppGroupProfile.groups(fromProfile:)) ?? []
    return AppGroupProfile.candidates(profileGroups: groups).first {
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
    }
  }()

  static var containerURL: URL? {
    groupIdentifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
  }

  static var isAvailable: Bool { containerURL != nil }

  /// Widget-Arten (`kind`) – App und Erweiterung nutzen dieselben Namen zum Neuladen.
  nonisolated enum Kind {
    static let today = "io.github.hkrb7p794w.coach.widget.today"
    static let nutrition = "io.github.hkrb7p794w.coach.widget.nutrition"
    static let health = "io.github.hkrb7p794w.coach.widget.health"
    static let gym = "io.github.hkrb7p794w.coach.widget.gym"
    static let meals = "io.github.hkrb7p794w.coach.widget.meals"
  }

  // MARK: Stand der App

  static func loadSnapshot() -> WidgetSnapshot? {
    read(WidgetSnapshot.self, WidgetSnapshot.fileName)
  }

  static func save(_ snapshot: WidgetSnapshot) {
    write(snapshot, WidgetSnapshot.fileName)
  }

  // MARK: Aktionen aus Widgets

  static func loadQueue() -> WidgetActionQueue {
    read(WidgetActionQueue.self, WidgetActionQueue.fileName) ?? WidgetActionQueue()
  }

  /// Lesen, ändern, schreiben unter Dateikoordination (Widget und App können gleichzeitig zugreifen).
  static func updateQueue(_ change: (inout WidgetActionQueue) -> Void) {
    guard let url = containerURL?.appendingPathComponent(WidgetActionQueue.fileName) else { return }
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { url in
      var queue =
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(WidgetActionQueue.self, from: $0) }
        ?? WidgetActionQueue()
      change(&queue)
      if let data = try? JSONEncoder().encode(queue) { try? data.write(to: url, options: .atomic) }
    }
  }

  // MARK: Dateien

  private static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
    guard let url = containerURL?.appendingPathComponent(name), let data = try? Data(contentsOf: url) else {
      return nil
    }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func write<T: Encodable>(_ value: T, _ name: String) {
    guard let url = containerURL?.appendingPathComponent(name), let data = try? JSONEncoder().encode(value) else {
      return
    }
    try? data.write(to: url, options: .atomic)
  }
}
