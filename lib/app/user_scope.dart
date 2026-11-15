import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'theme.dart';
import 'user_session.dart';

/// Oberfläche des aktiven Benutzers. Der Schlüssel wechselt mit jedem Benutzerwechsel: Alle Bildschirme, Navigation
/// und Zustände der Widgets entstehen neu – nichts aus der Ansicht des bisherigen Benutzers bleibt stehen.
class UserScope extends StatelessWidget {
  const UserScope({super.key, required this.session});

  final UserSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      if (session.isSwitching) return const _SwitchingApp();
      return UncontrolledProviderScope(
        key: ValueKey('${session.user.id}#${session.generation}'),
        container: session.container,
        child: const AIronLudiApp(),
      );
    },
  );
}

class _SwitchingApp extends StatelessWidget {
  const _SwitchingApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    home: const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [CircularProgressIndicator(), Text('Benutzer wird gewechselt …')],
        ),
      ),
    ),
  );
}
