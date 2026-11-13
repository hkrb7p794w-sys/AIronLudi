import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kleine Komfortwerte der Oberfläche (Darstellung, eingeklappte Bereiche). Fachliche Einstellungen (`coach.*`)
/// liegen in der Datenbank, damit sie zur Sicherung gehören (Phase 2f).
///
/// Wird in `main` mit dem geladenen Speicher überschrieben.
final preferencesProvider = Provider<SharedPreferencesWithCache>(
  (ref) => throw UnimplementedError('preferencesProvider muss in main überschrieben werden'),
);
