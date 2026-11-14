import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/storage.dart';
import '../../features/gym/gym_providers.dart';
import '../providers.dart';
import 'widget_publisher.dart';
import 'widget_store.dart';

/// Plattformteil der Widgets (in Tests ein fester Ordner).
final widgetHostProvider = Provider<WidgetHost>((ref) => ChannelWidgetHost());

final widgetStoreProvider = Provider<WidgetStore>((ref) => WidgetStore(ref.watch(widgetHostProvider)));

final widgetPublisherProvider = Provider<WidgetPublisher>((ref) {
  final sync = ref.watch(garminSyncServiceProvider);
  return WidgetPublisher(
    store: ref.watch(widgetStoreProvider),
    settings: ref.read(coachSettingsProvider),
    settingsStore: ref.watch(settingsStoreProvider),
    metrics: ref.watch(metricsRepositoryProvider),
    activities: ref.watch(activityRepositoryProvider),
    gymSessions: ref.watch(gymRepositoryProvider),
    meals: ref.watch(mealRepositoryProvider),
    gym: ref.read(gymControllerProvider),
    garminProfile: () => sync.profile,
    schedule: ref.watch(seasonScheduleProvider),
    isDemo: ref.read(appModelProvider).isDemo,
  );
});
