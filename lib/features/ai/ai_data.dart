import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../services/providers.dart';
import 'ai_controller.dart';

/// Lädt Tageswerte, Aktivitäten, Mahlzeiten, Krafteinheiten und Gewichte für Regeln, Chat und Analyse.
Future<AIData> loadAIData(WidgetRef ref) async {
  final results = await (
    ref.read(metricsRepositoryProvider).all(),
    ref.read(activityRepositoryProvider).all(),
    ref.read(mealRepositoryProvider).all(),
    ref.read(gymRepositoryProvider).all(),
  ).wait;
  final metrics = [...results.$1]..sort((a, b) => a.day.compareTo(b.day));
  return (
    metrics: metrics,
    activities: results.$2,
    meals: results.$3,
    gym: [for (final record in results.$4) record.session],
    weights: ref.read(appModelProvider).allWeights,
  );
}
