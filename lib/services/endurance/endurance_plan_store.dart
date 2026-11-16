import 'package:coach_core/coach_core.dart';

import '../../data/settings/settings_store.dart';

/// Ausdauerplan im Speicher des aktiven Benutzers (`coach.endurancePlan` in dessen Datenbank). Zusätzlich zur
/// Trennung über die Datenbankdatei je Benutzer trägt der Plan den `username`: Ein Plan eines anderen Benutzers (z. B.
/// aus einer eingespielten Sicherung) wird nicht geladen und nie überschrieben, ohne dass der Benutzer neu plant.
final class EndurancePlanStore {
  EndurancePlanStore(this._store, {required this.username});

  final SettingsStore _store;
  final String username;

  static const key = SettingsKeys.endurancePlan;

  EndurancePlan? load() =>
      _store.read<EndurancePlan?>(key, (json) => EndurancePlan.fromJson(json, username: username), null);

  /// Liegt ein Plan vor, der einem anderen Benutzer gehört?
  bool get hasForeignPlan => _store.contains(key) && load() == null;

  Future<void> save(EndurancePlan plan) {
    if (plan.username != username || plan.request.username != username) {
      throw StateError('Der Plan gehört nicht dem angemeldeten Benutzer.');
    }
    return _store.setJson(key, plan.toJson());
  }

  Future<void> delete() => _store.remove(key);
}
