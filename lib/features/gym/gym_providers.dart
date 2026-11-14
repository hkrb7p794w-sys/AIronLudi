import 'package:flutter_riverpod/legacy.dart';

import '../../data/storage.dart';
import '../../services/gym/rest_alarm.dart';
import '../../services/providers.dart';
import 'gym_controller.dart';

/// Eine Einheit für App und Live-Aktivität (deren Knöpfe laufen auch ohne geöffnete Gym-Ansicht) – wie
/// `GymViewModel.shared`.
final gymControllerProvider = ChangeNotifierProvider<GymController>(
  (ref) => GymController(
    store: ref.watch(settingsStoreProvider),
    alarm: NotificationRestAlarm(ref.watch(notificationCenterProvider)),
    sound: AssetRestSoundPlayer(),
  ),
);
