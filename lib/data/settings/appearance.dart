import 'package:coach_core/coach_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'preferences.dart';

/// Gewählte Darstellung (Einstellungen › Darstellung): Wie System, Hell oder Dunkel.
final appearanceProvider = NotifierProvider<AppearanceController, AppAppearance>(AppearanceController.new);

class AppearanceController extends Notifier<AppAppearance> {
  @override
  AppAppearance build() => AppAppearance.fromStored(ref.read(preferencesProvider).getString(AppAppearance.storageKey));

  Future<void> select(AppAppearance appearance) async {
    state = appearance;
    await ref.read(preferencesProvider).setString(AppAppearance.storageKey, appearance.name);
  }
}

extension AppAppearanceThemeMode on AppAppearance {
  ThemeMode get themeMode => switch (this) {
    AppAppearance.system => ThemeMode.system,
    AppAppearance.light => ThemeMode.light,
    AppAppearance.dark => ThemeMode.dark,
  };
}
